import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/input_formatters.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../discovery/discovery_repository.dart';
import '../../../profile/data/profile_models.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/availability_models.dart';
import '../../data/business_repository.dart';
import '../../data/profile_limits.dart';
import '../../data/rate_models.dart';

/// Three-step SP profile setup:
/// details (+charges if !hasMenu) → availability & timing (if hasDateBooking) → preview.
class SpSetupWizardScreen extends ConsumerStatefulWidget {
  const SpSetupWizardScreen({
    super.key,
    this.initialAvailability,
    this.initialName,
    this.hasMenu = false,
    this.hasDateBooking = false,
  });

  final SpAvailability? initialAvailability;
  final String? initialName;
  final bool hasMenu;
  final bool hasDateBooking;

  @override
  ConsumerState<SpSetupWizardScreen> createState() => _SpSetupWizardScreenState();
}

/// The replace-all body for `setProfessions` when the wizard's single title field is saved.
///
/// The wizard owns only the first entry, so the rest go back untouched by master id. Returns
/// null when there's nothing to write — an unchanged title mustn't cost a request. Entries with
/// no master id (legacy rows with no catalog link, whose label is only a placeholder) are
/// dropped rather than round-tripped as free text, which would mint a junk pending category.
List<Map<String, dynamic>>? professionsPayload(String title, List<IdName> existing) {
  if (title.isEmpty) return null;
  if (existing.isNotEmpty && existing.first.label == title) return null;
  return [
    {'category': title},
    for (final p in existing.skip(1))
      if (p.masterId != null)
        {'professionMasterId': p.masterId, if (p.subtitle != null) 'companyOrDetail': p.subtitle},
  ];
}

// Weekday chips in Figma order (Mon-first). Value is 0=Sun … 6=Sat.
const _dayOrder = [1, 2, 3, 4, 5, 6, 0];
const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _rateTypes = ['per_session', 'monthly', 'hourly'];

class _SpSetupWizardScreenState extends ConsumerState<SpSetupWizardScreen> {
  int _step = 0;

  final _name = TextEditingController();
  final _title = TextEditingController();
  final _experience = TextEditingController();
  final _about = TextEditingController();
  final _maxDistance = TextEditingController();
  final Map<String, TextEditingController> _rates = {for (final t in _rateTypes) t: TextEditingController()};

  final Set<int> _days = {1, 2, 3, 4, 5};
  TimeOfDay _start = const TimeOfDay(hour: 16, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 20, minute: 0);
  int? _slotMinutes = 120; // null ⇒ whole window
  bool _willingToTravel = true;
  bool _saving = false;
  /// Shown under the travel-distance field; set when Next / Save finds a problem, then kept
  /// up to date as the provider edits.
  String? _distanceError;

  /// Problems with the "Set up your profile" fields, shown under each field: keys are
  /// 'name', 'title', 'experience', 'about' and `rate:${type}`.
  final _detailErrors = <String, String>{};

  /// The profile's professions as loaded, so a save can replace just the wizard's own title
  /// (the first entry) without dropping ones added from the profile section.
  List<IdName> _professions = const [];

  bool get _hasDateBooking => widget.hasDateBooking;
  bool get _isService => !widget.hasMenu;

  @override
  void initState() {
    super.initState();
    _name.text = widget.initialName ?? ref.read(authControllerProvider).user?.name ?? '';
    final a = widget.initialAvailability;
    if (a != null) {
      _days
        ..clear()
        ..addAll(a.workingDays);
      _start = _parse(a.startTime);
      _end = _parse(a.endTime);
      _slotMinutes = a.slotMinutes;
      _willingToTravel = a.willingToTravel;
      if (a.maxTravelKm != null) _maxDistance.text = a.maxTravelKm!.toStringAsFixed(0);
    }
    _loadDetails();
    if (_isService) _loadRates(); // load charges for non-menu SPs
  }

  /// Fills the Details step from what's already saved. Without this, everything the SP typed
  /// here last time comes back blank — the step writes these fields but never read them back.
  Future<void> _loadDetails() async {
    try {
      final p = await ref.read(myProfileProvider.future);
      if (!mounted) return;
      setState(() {
        _professions = p.professions;
        // Don't clobber anything typed while the request was in flight.
        if (_title.text.isEmpty && p.professions.isNotEmpty) _title.text = p.professions.first.label;
        if (_experience.text.isEmpty && p.yearsOfExperience != null) {
          _experience.text = p.yearsOfExperience!.toString();
        }
        if (_about.text.isEmpty) _about.text = p.aboutMe ?? '';
        if (_name.text.isEmpty) _name.text = p.name;
      });
    } catch (_) {
      // Prefill is a convenience — a failed load must not block the wizard.
    }
  }

  Future<void> _loadRates() async {
    try {
      final rates = await ref.read(businessRepositoryProvider).myRates();
      if (!mounted) return;
      setState(() {
        for (final r in rates) {
          _rates[r.rateType]?.text = r.amount.toStringAsFixed(0);
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _experience, _about, _maxDistance, ..._rates.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TimeOfDay _parse(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;

  // Steps: 0=Details, 1=Availability (only if hasDateBooking), 2=Preview
  // When !hasDateBooking the wizard jumps from 0 directly to 2.
  //
  // Each step persists as it's left, so backing out mid-wizard keeps whatever was filled in
  // rather than discarding it. Every write is a replace, so re-entering a step and pressing
  // Next again just rewrites the same values.
  Future<void> _next() async {
    if (_step == 0) {
      if (!_validateDetails()) return; // messages under the fields; nothing saved
      if (!await _persist(_persistDetails)) return;
      setState(() => _step = _hasDateBooking ? 1 : 2);
      return;
    } else if (_step == 1) {
      if (_days.isEmpty) return _toast('Pick at least one working day');
      if (_mins(_end) <= _mins(_start)) return _toast('End time must be after start time');
      if (!_checkDistance()) return;
      if (!await _persist(_persistAvailability)) return;
    }
    setState(() => _step++);
  }

  /// Every "Set up your profile" field's problem, by field key.
  Map<String, String> _checkDetails() {
    final errors = <String, String?>{
      'name': ProfileLimits.nameError(_name.text),
      'title': ProfileLimits.titleError(_title.text),
      'experience': ProfileLimits.experienceError(_experience.text),
      'about': ProfileLimits.aboutError(_about.text),
      if (_isService)
        for (final t in _rateTypes) 'rate:$t': ProfileLimits.rateError(_rates[t]!.text),
    };
    return {
      for (final e in errors.entries)
        if (e.value != null) e.key: e.value!,
    };
  }

  /// Shows every problem on the details step under its field. Returns false if any.
  bool _validateDetails() {
    final errors = _checkDetails();
    setState(() => _detailErrors
      ..clear()
      ..addAll(errors));
    return errors.isEmpty;
  }

  /// Once a field's problem is shown, keep it current as the provider edits that field.
  void _recheckDetail(String key) {
    if (!_detailErrors.containsKey(key)) return;
    final e = _checkDetails()[key];
    setState(() => e == null ? _detailErrors.remove(key) : _detailErrors[key] = e);
  }

  /// Validates the travel distance in place (message under the field, no save). Returns
  /// false when it's not acceptable.
  bool _checkDistance() {
    final error = _willingToTravel ? travelDistanceError(_maxDistance.text) : null;
    setState(() => _distanceError = error);
    return error == null;
  }

  /// Runs one save with the button in its loading state. Returns false (and leaves the wizard
  /// on the current step) if it failed, so a dropped save can't look like it succeeded.
  Future<bool> _persist(Future<void> Function() save) async {
    setState(() => _saving = true);
    try {
      await save();
      return true;
    } catch (e) {
      if (mounted) _showSaveError(e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The server's own reason when it rejected the input (e.g. a validation message) — under
  /// the travel field if that's what it was about — else the generic failure toast.
  void _showSaveError(Object e) {
    final api = e is DioException ? ApiException.fromDio(e) : (e is ApiException ? e : null);
    final status = api?.statusCode;
    if (api == null || status == null || status < 400 || status >= 500) {
      _toast('Could not save. Please try again.');
      return;
    }
    final details = api.details;
    // A details-step field the server rejected: show it under that field, on that step.
    String? first(String k) =>
        details is Map && details[k] is List && (details[k] as List).isNotEmpty ? '${(details[k] as List).first}' : null;
    final byField = <String, String>{
      if (first('name') case final String m) 'name': m,
      if (first('professions') case final String m) 'title': m,
      if (first('yearsOfExperience') case final String m) 'experience': m,
      if (first('aboutMe') case final String m) 'about': m,
      // Rates come back for the list as a whole; mark the charges the app also finds
      // wrong, or else the first one filled in.
      if (first('rates') case final String m)
        for (final t in _rateTypes)
          if (ProfileLimits.rateError(_rates[t]!.text) != null ||
              t == _rateTypes.firstWhere((x) => _rates[x]!.text.trim().isNotEmpty, orElse: () => _rateTypes.first))
            'rate:$t': m,
    };
    if (byField.isNotEmpty) {
      setState(() {
        _detailErrors
          ..clear()
          ..addAll(byField);
        _step = 0;
      });
      return;
    }
    if (details is Map && details['maxTravelKm'] is List && (details['maxTravelKm'] as List).isNotEmpty) {
      setState(() {
        _distanceError = '${(details['maxTravelKm'] as List).first}';
        if (_hasDateBooking) _step = 1; // show the field the message belongs to
      });
      return;
    }
    _toast(api.message);
  }

  void _backToEdit() => setState(() => _step = _hasDateBooking ? 1 : 0);

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Step 1's answers: the profile columns, the professional title and (service SPs) charges.
  Future<void> _persistDetails() async {
    final repo = ref.read(businessRepositoryProvider);
    await repo.updateProfile({
      'name': _name.text.trim(),
      if (_experience.text.trim().isNotEmpty) 'yearsOfExperience': int.tryParse(_experience.text.trim()),
      if (_about.text.trim().isNotEmpty) 'aboutMe': _about.text.trim(),
    });

    // Replace-all rather than POST, which would append a duplicate row on every save.
    final title = _title.text.trim();
    final professions = professionsPayload(title, _professions);
    if (professions != null) {
      await repo.setProfessions(professions);
      // Reflect the write locally so re-saving an unchanged step doesn't repeat it. Only the
      // first entry's label is read back — professionsPayload always rewrites it as free text.
      _professions = [IdName(0, title), ..._professions.skip(1)];
    }

    if (_isService) {
      final rates = <SpRate>[];
      for (final t in _rateTypes) {
        final v = double.tryParse(_rates[t]!.text.trim());
        if (v != null && v > 0) rates.add(SpRate(rateType: t, amount: v));
      }
      if (rates.isNotEmpty) {
        await repo.setRates(rates);
        ref.invalidate(myRatesProvider);
      }
    }
    ref.invalidate(myProfileProvider);
  }

  /// Step 2's answers. Only date-booking SPs reach this step.
  Future<void> _persistAvailability() async {
    await ref.read(businessRepositoryProvider).setAvailability({
      'workingDays': _days.toList()..sort(),
      'startTime': _hhmm(_start),
      'endTime': _hhmm(_end),
      'slotMinutes': _slotMinutes,
      'willingToTravel': _willingToTravel,
      if (_willingToTravel && _maxDistance.text.trim().isNotEmpty)
        'maxTravelKm': double.tryParse(_maxDistance.text.trim()),
      'horizonDays': 14,
    });
    ref.invalidate(myAvailabilityProvider);
  }

  /// Re-saves every step — the SP can edit on the preview step's "go back to edit", and the
  /// writes are replaces, so this is safe to repeat.
  Future<void> _confirm() async {
    // Details edited from the preview's "go back to edit" are checked again before saving.
    if (!_validateDetails()) {
      setState(() => _step = 0);
      return;
    }
    // The preview step can be reached with an invalid distance only by editing elsewhere;
    // send the provider back to the field rather than saving.
    if (_hasDateBooking && _willingToTravel && travelDistanceError(_maxDistance.text) != null) {
      setState(() => _step = 1);
      _checkDistance();
      return;
    }
    setState(() => _saving = true);
    try {
      await _persistDetails();
      if (_hasDateBooking) await _persistAvailability();
      // ServiceProviderDetailScreen ("My Profile") reads a separate cache that nothing else
      // here touches — without this, edits made via My Shop only show up after a reload.
      ref.invalidate(serviceProviderDetailProvider);
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile & availability saved')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showSaveError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Set up your profile', 'Availability & Timing', 'Preview your profile'];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text(titles[_step]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _step < 2
              ? ElevatedButton(
                  onPressed: _saving ? null : _next,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Next'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _saving ? null : _confirm,
                      child: _saving
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Confirm'),
                    ),
                    TextButton(onPressed: _saving ? null : _backToEdit, child: const Text('Go back to edit profile')),
                  ],
                ),
        ),
      ),
      body: Column(
        children: [
          _progress(),
          Expanded(child: switch (_step) {
            0 => _stepDetails(),
            1 when _hasDateBooking => _stepAvailability(),
            _ => _stepPreview(),
          }),
        ],
      ),
    );
  }

  Widget _progress() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      );

  // ── Step 1: details ──────────────────────────────────────────
  Widget _stepDetails() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Enter your Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 16),
          _field(_name, 'Your Name',
              maxLength: ProfileLimits.name, error: _detailErrors['name'], onChanged: (_) => _recheckDetail('name')),
          const SizedBox(height: 12),
          _field(_title, 'Your professional title',
              maxLength: ProfileLimits.professionTitle,
              error: _detailErrors['title'],
              onChanged: (_) => _recheckDetail('title')),
          const SizedBox(height: 12),
          _field(_experience, 'Years of experience',
              keyboard: TextInputType.number,
              formatters: kIntegerInput,
              helper: '0 to ${ProfileLimits.yearsOfExperience}',
              error: _detailErrors['experience'],
              onChanged: (_) => _recheckDetail('experience')),
          const SizedBox(height: 12),
          _field(_about, 'About yourself',
              maxLines: 4,
              maxLength: ProfileLimits.aboutMe,
              error: _detailErrors['about'],
              onChanged: (_) => _recheckDetail('about')),
          if (_isService) ...[
            const SizedBox(height: 18),
            const Text('Your charges', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Residents pick one when booking. Leave blank to hide.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            ..._rateTypes.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _field(_rates[t]!, rateTypeLabels[t]!,
                      keyboard: kDecimalKeyboard,
                      formatters: kDecimalInput,
                      prefix: '₹ ',
                      error: _detailErrors['rate:$t'],
                      onChanged: (_) => _recheckDetail('rate:$t')),
                )),
          ],
          const SizedBox(height: 16),
          _travelToggle(),
        ],
      );

  // ── Step 2: availability & timing ────────────────────────────
  Widget _stepAvailability() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Working days', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_dayOrder.length, (i) {
              final d = _dayOrder[i];
              final on = _days.contains(d);
              return GestureDetector(
                onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? AppColors.primary : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(_dayLetters[i],
                      style: TextStyle(color: on ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w700)),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _timeField('Start Time', _start, (t) => setState(() => _start = t))),
            const SizedBox(width: 12),
            Expanded(child: _timeField('End Time', _end, (t) => setState(() => _end = t))),
          ]),
          const SizedBox(height: 20),
          const Text('Slot length', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _slotChip('Whole window', null),
              _slotChip('30 min', 30),
              _slotChip('1 hour', 60),
              _slotChip('2 hours', 120),
            ],
          ),
          const SizedBox(height: 20),
          _travelToggle(),
          if (_willingToTravel) ...[
            const SizedBox(height: 12),
            _field(
              _maxDistance,
              'Maximum distance can you travel (km)',
              keyboard: kDecimalKeyboard,
              formatters: kDecimalInput,
              helper: 'Up to $kMaxTravelKm km',
              error: _distanceError,
              // Once a problem is shown, keep it current as they fix it.
              onChanged: (_) {
                if (_distanceError != null) _checkDistance();
              },
            ),
          ],
        ],
      );

  // ── Step 3: preview ──────────────────────────────────────────
  Widget _stepPreview() {
    final days = (_days.toList()..sort()).map(weekdayShort).join(', ');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name.text.trim().isEmpty ? 'Your Name' : _name.text.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
              if (_title.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_title.text.trim(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              ],
              const Divider(height: 28),
              if (_experience.text.trim().isNotEmpty) _preview('Experience', '${_experience.text.trim()} Years'),
              if (_isService)
                for (final t in _rateTypes)
                  if (_rates[t]!.text.trim().isNotEmpty) _preview(rateTypeLabels[t]!, '₹${_rates[t]!.text.trim()}'),
              if (_hasDateBooking) ...[
                _preview('Working Days', days.isEmpty ? '—' : days),
                _preview('Timings', '${formatHm(_hhmm(_start))} – ${formatHm(_hhmm(_end))}'),
                _preview('Slot length', _slotMinutes == null ? 'Whole window' : '$_slotMinutes min'),
                _preview('Availability', _willingToTravel
                    ? 'Willing to travel${_maxDistance.text.trim().isNotEmpty ? ' · ${_maxDistance.text.trim()} km' : ''}'
                    : 'At my location'),
              ],
              if (_about.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('About Me', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_about.text.trim(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          ],
        ),
      );

  // ── Shared widgets ───────────────────────────────────────────
  Widget _field(TextEditingController c, String label,
          {int maxLines = 1,
          TextInputType? keyboard,
          String? prefix,
          List<TextInputFormatter>? formatters,
          String? helper,
          String? error,
          int? maxLength,
          ValueChanged<String>? onChanged}) =>
      TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        inputFormatters: formatters,
        onChanged: onChanged,
        // A live "37/100" counter that turns red past the limit. Typing past it is allowed so
        // the provider sees why it's wrong; Next is blocked until it fits.
        maxLength: maxLength,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        decoration: InputDecoration(labelText: label, prefixText: prefix, helperText: helper, errorText: error),
      );

  Widget _timeField(String label, TimeOfDay value, ValueChanged<TimeOfDay> onPick) => InkWell(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: value);
          if (picked != null) onPick(picked);
        },
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Text(formatHm(_hhmm(value)), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _slotChip(String label, int? minutes) {
    final on = _slotMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => setState(() => _slotMinutes = minutes),
      selectedColor: AppColors.primarySurface,
      labelStyle: TextStyle(color: on ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600),
      side: BorderSide(color: on ? AppColors.primary : AppColors.border),
      backgroundColor: AppColors.surface,
    );
  }

  // A Material (not a coloured Container) so the switch tile's ripple shows on this surface;
  // a decorated box in between hides it, which Flutter flags in debug builds.
  Widget _travelToggle() => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.primary,
          title: const Text('Are you willing to travel?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          value: _willingToTravel,
          onChanged: (v) => setState(() {
            _willingToTravel = v;
            if (!v) _distanceError = null; // the distance isn't sent when not travelling
          }),
        ),
        ),
      );
}
