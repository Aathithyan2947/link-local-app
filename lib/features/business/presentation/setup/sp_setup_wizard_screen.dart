import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/application/auth_controller.dart';
import '../../data/availability_models.dart';
import '../../data/business_repository.dart';
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
    if (_isService) _loadRates(); // load charges for non-menu SPs
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
  void _next() {
    if (_step == 0) {
      if (_name.text.trim().isEmpty) return _toast('Please enter your name');
      setState(() => _step = _hasDateBooking ? 1 : 2);
      return;
    } else if (_step == 1) {
      if (_days.isEmpty) return _toast('Pick at least one working day');
      if (_mins(_end) <= _mins(_start)) return _toast('End time must be after start time');
    }
    setState(() => _step++);
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

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      await repo.updateProfile({
        'name': _name.text.trim(),
        if (_experience.text.trim().isNotEmpty) 'yearsOfExperience': int.tryParse(_experience.text.trim()),
        if (_about.text.trim().isNotEmpty) 'aboutMe': _about.text.trim(),
      });
      if (_title.text.trim().isNotEmpty) await repo.addProfession(_title.text.trim());
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
      if (_hasDateBooking) {
        await repo.setAvailability({
          'workingDays': _days.toList()..sort(),
          'startTime': _hhmm(_start),
          'endTime': _hhmm(_end),
          'slotMinutes': _slotMinutes,
          'willingToTravel': _willingToTravel,
          if (_willingToTravel && _maxDistance.text.trim().isNotEmpty)
            'maxTravelKm': double.tryParse(_maxDistance.text.trim()),
          'horizonDays': 14,
        });
      }
      if (!mounted) return;
      ref.invalidate(myAvailabilityProvider);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile & availability saved')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      _toast('Could not save. Please try again.');
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
              ? ElevatedButton(onPressed: _next, child: const Text('Next'))
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
          _field(_name, 'Your Name'),
          const SizedBox(height: 12),
          _field(_title, 'Your professional title'),
          const SizedBox(height: 12),
          _field(_experience, 'Years of experience', keyboard: TextInputType.number),
          const SizedBox(height: 12),
          _field(_about, 'About yourself', maxLines: 4),
          if (_isService) ...[
            const SizedBox(height: 18),
            const Text('Your charges', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Residents pick one when booking. Leave blank to hide.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            ..._rateTypes.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _field(_rates[t]!, rateTypeLabels[t]!, keyboard: TextInputType.number, prefix: '₹ '),
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
            _field(_maxDistance, 'Maximum distance can you travel (km)', keyboard: TextInputType.number),
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
  Widget _field(TextEditingController c, String label, {int maxLines = 1, TextInputType? keyboard, String? prefix}) => TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, prefixText: prefix),
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

  Widget _travelToggle() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.primary,
          title: const Text('Are you willing to travel?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          value: _willingToTravel,
          onChanged: (v) => setState(() => _willingToTravel = v),
        ),
      );
}
