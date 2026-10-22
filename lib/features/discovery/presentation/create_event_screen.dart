import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/content_limits.dart';
import '../../../core/widgets/input_formatters.dart';
import '../../address/presentation/widgets/place_search_field.dart';
import '../../profile/data/profile_repository.dart';
import '../data/event_detail_models.dart';
import '../discovery_repository.dart';
import '../event_lists_refresh.dart';
import 'event_detail_screen.dart';

/// Form to host a new event, or edit one you already host when [event] is passed.
/// Create uploads an optional cover image via /media then POSTs to /events and opens the
/// created event; edit PATCHes the existing event and pops back.
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key, this.event});
  final EventDetail? event;
  bool get isEdit => event != null;

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _onlineLink = TextEditingController();
  final _price = TextEditingController();
  final _maxAttendees = TextEditingController();
  final _duration = TextEditingController(text: '60');

  /// Map position of the location when picked from place search; null when typed.
  PickedPlace? _place;
  final List<TextEditingController> _materials = [TextEditingController()];

  DateTime? _date;
  TimeOfDay? _time;
  String _mode = 'offline';
  bool _isPaid = false;
  XFile? _image;
  String? _existingPhotoUrl;
  bool _submitting = false;
  /// The server's rejection of a field, shown under it until that field is edited.
  Map<String, String> _serverErrors = const {};
  // Date and time are pickers, not text fields, so their messages are kept here.
  String? _dateError;
  String? _timeError;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e == null) return;
    _title.text = e.title;
    _description.text = e.description ?? '';
    _location.text = e.location ?? '';
    if (e.latitude != null && e.longitude != null) {
      _place = PickedPlace(latitude: e.latitude!, longitude: e.longitude!, googlePlaceId: e.googlePlaceId);
    }
    _onlineLink.text = e.onlineLink ?? '';
    _price.text = e.price != null ? ContentLimits.priceText(e.price!) : '';
    _maxAttendees.text = e.maxAttendees?.toString() ?? '';
    _duration.text = e.durationMinutes?.toString() ?? '60';
    _date = e.date;
    _time = e.startTime != null ? TimeOfDay(hour: e.startTime!.hour, minute: e.startTime!.minute) : null;
    _mode = e.mode;
    _isPaid = e.isPaid;
    _existingPhotoUrl = e.photoUrl;
    if (e.rawMaterials.isNotEmpty) {
      _materials
        ..clear()
        ..addAll(e.rawMaterials.map((m) => TextEditingController(text: m)));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _location, _onlineLink, _price, _maxAttendees, _duration, ..._materials]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    if (!mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final edited = await editPickedImageBytes(context, bytes);
    if (edited == null) return;
    final path = await writeEditedImageToTempFile(edited);
    setState(() => _image = XFile(path));
  }

  /// The picked date + time, as a local instant (the host is in the event's city).
  DateTime? get _startsAt => _date == null || _time == null
      ? null
      : DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);

  /// Only a new or rescheduled event has to start in the future — the server says the same, so
  /// editing the description of an event that has started still saves.
  bool get _startsInPast {
    final at = _startsAt;
    if (at == null) return false;
    final e = widget.event;
    if (e != null && e.date != null && e.startTime != null) {
      final was = DateTime(e.date!.year, e.date!.month, e.date!.day, e.startTime!.hour, e.startTime!.minute);
      if (was == at) return false;
    }
    return !at.isAfter(DateTime.now());
  }

  Future<void> _submit() async {
    setState(() {
      _serverErrors = const {};
      _dateError = _date == null ? 'Pick a date' : null;
      _timeError = _time == null
          ? 'Pick a start time'
          : (_startsInPast ? 'Start time must be in the future' : null);
    });
    final formOk = _formKey.currentState!.validate();
    if (!formOk || _dateError != null || _timeError != null) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(discoveryRepositoryProvider);
      String? photoUrl;
      if (_image != null) photoUrl = await repo.uploadImage(_image!.path, type: 'event');

      final materials = _materials.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      final data = {
        'title': _title.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        'photoUrl': ?photoUrl,
        'date': _date!.toIso8601String(),
        'startTime': '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
        if (_duration.text.trim().isNotEmpty) 'durationMinutes': int.tryParse(_duration.text.trim()),
        'mode': _mode,
        if (_mode == 'offline' && _location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        // Sent explicitly (null included) so an edit that switches to typed text clears them.
        if (_mode == 'offline') ...{
          'latitude': _place?.latitude,
          'longitude': _place?.longitude,
          'googlePlaceId': _place?.googlePlaceId,
        },
        if (_mode == 'online' && _onlineLink.text.trim().isNotEmpty) 'onlineLink': _onlineLink.text.trim(),
        'isPaid': _isPaid,
        if (_isPaid && _price.text.trim().isNotEmpty) 'price': double.tryParse(_price.text.trim()),
        if (_maxAttendees.text.trim().isNotEmpty) 'maxAttendees': int.tryParse(_maxAttendees.text.trim()),
        if (materials.isNotEmpty) 'rawMaterials': materials,
      };

      if (widget.isEdit) {
        final id = widget.event!.id;
        await repo.updateEvent(id, data);
        if (!mounted) return;
        ref.invalidateEventLists();
        ref.invalidate(eventDetailProvider(id));
        await ref.read(eventDetailProvider(id).future);
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        final id = await repo.createEvent(data);
        if (!mounted) return;
        ref.invalidateEventLists();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => EventDetailScreen(id: id)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSubmitError(e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// A rejected field goes under that field; anything else says what the server said, not a
  /// generic "Could not create event" (BUG-074).
  void _showSubmitError(Object e) {
    final err = ApiException.from(e);
    final fields = err.fieldErrors;
    if (fields.isNotEmpty) {
      setState(() {
        _serverErrors = fields;
        _dateError = fields['date'];
        _timeError = fields['startTime'];
      });
      _formKey.currentState!.validate();
      return;
    }
    final fallback = widget.isEdit ? 'Could not save event' : 'Could not create event';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err.message == 'Something went wrong' ? fallback : err.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Event' : 'Host an Event')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _imagePicker(),
            const SizedBox(height: 16),
            // Same rules and counters as Start a Group's name and description.
            _field(_title, 'Event title', serverKey: 'title',
                maxLength: ContentLimits.titleMax,
                formatters: [ContentLimits.titleInputFormatter],
                validator: (v) => ContentLimits.titleError('Event title', v)),
            const SizedBox(height: 12),
            _field(_description, 'Description', serverKey: 'description', maxLines: 3,
                maxLength: ContentLimits.description, validator: ContentLimits.descriptionError),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _dateField()),
              const SizedBox(width: 12),
              Expanded(child: _timeField()),
            ]),
            const SizedBox(height: 12),
            _field(_duration, 'Duration (minutes)', serverKey: 'durationMinutes',
                keyboard: TextInputType.number, formatters: kIntegerInput, validator: ContentLimits.durationError),
            const SizedBox(height: 16),
            _modeSelector(),
            const SizedBox(height: 12),
            if (_mode == 'offline')
              PlaceSearchField(
                controller: _location,
                // Suggestions come from the host's own city.
                cityId: ref.watch(myProfileProvider).asData?.value.cityId,
                onChanged: (p) {
                  _place = p;
                  if (_serverErrors.containsKey('location')) {
                    setState(() => _serverErrors = {..._serverErrors}..remove('location'));
                  }
                },
                validator: (v) => _serverErrors['location'] ?? ContentLimits.locationError(v ?? ''),
              )
            else
              _field(_onlineLink, 'Online link', serverKey: 'onlineLink', keyboard: TextInputType.url,
                  validator: ContentLimits.onlineLinkError),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              title: const Text('Paid event', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _isPaid,
              onChanged: (v) => setState(() => _isPaid = v),
            ),
            if (_isPaid)
              _field(_price, 'Price (₹)', serverKey: 'price', keyboard: kDecimalKeyboard, formatters: kDecimalInput,
                  validator: (v) => ContentLimits.priceError(v, what: 'event')),
            const SizedBox(height: 12),
            _field(_maxAttendees, 'Max attendees (optional)', serverKey: 'maxAttendees',
                keyboard: TextInputType.number, formatters: kIntegerInput, validator: ContentLimits.maxAttendeesError),
            const SizedBox(height: 20),
            const Text('What to bring / Guidelines', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            ..._materials.asMap().entries.map((e) => _materialRow(e.key)),
            if (_serverErrors['rawMaterials'] case final msg?)
              Text(msg, style: const TextStyle(color: AppColors.error, fontSize: 12)),
            // At most 20 items, the server's limit too.
            if (_materials.length < ContentLimits.materialItems)
              TextButton.icon(
                onPressed: () => setState(() => _materials.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add item'),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(widget.isEdit ? 'Save Changes' : 'Create Event'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() => GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            image: _image != null
                ? DecorationImage(image: FileImage(File(_image!.path)), fit: BoxFit.cover)
                : (_existingPhotoUrl != null
                    ? DecorationImage(image: NetworkImage(AppConfig.assetUrl(_existingPhotoUrl!)), fit: BoxFit.cover)
                    : null),
          ),
          child: (_image != null || _existingPhotoUrl != null)
              ? null
              : const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppColors.textMuted),
                      SizedBox(height: 6),
                      Text('Add a cover photo', style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
        ),
      );

  /// A form field whose message comes from [validator] (the shared ContentLimits rules), or
  /// from the server for [serverKey] until the field is edited again.
  Widget _field(TextEditingController c, String label,
      {required String serverKey,
      required String? Function(String) validator,
      int maxLines = 1,
      int? maxLength,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      // With a limit, the field shows "12/80" under it and stops at the limit (BUG-071).
      maxLength: maxLength,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label, errorMaxLines: 3),
      onChanged: (_) {
        if (_serverErrors.containsKey(serverKey)) {
          setState(() => _serverErrors = {..._serverErrors}..remove(serverKey));
        }
      },
      validator: (v) => _serverErrors[serverKey] ?? validator(v ?? ''),
    );
  }

  Widget _dateField() => InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: _date ?? now,
            firstDate: now,
            lastDate: now.add(const Duration(days: 365)),
          );
          if (picked != null) {
            setState(() {
              _date = picked;
              _dateError = null;
              if (_timeError == 'Start time must be in the future') _timeError = null;
            });
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: 'Date', errorText: _dateError, errorMaxLines: 2),
          child: Text(_date != null ? DateFormat('EEE, MMM d').format(_date!) : 'Select',
              style: TextStyle(color: _date != null ? AppColors.textPrimary : AppColors.textMuted)),
        ),
      );

  Widget _timeField() => InkWell(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
          if (picked != null) {
            setState(() {
              _time = picked;
              _timeError = null;
            });
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: 'Start time', errorText: _timeError, errorMaxLines: 2),
          child: Text(_time != null ? _time!.format(context) : 'Select',
              style: TextStyle(color: _time != null ? AppColors.textPrimary : AppColors.textMuted)),
        ),
      );

  Widget _modeSelector() => Row(
        children: [
          for (final m in const ['offline', 'online'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(m == 'offline' ? 'In person' : 'Online'),
                  selected: _mode == m,
                  onSelected: (_) => setState(() => _mode = m),
                  selectedColor: AppColors.primarySurface,
                  labelStyle: TextStyle(
                      color: _mode == m ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      );

  Widget _materialRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _materials[i],
                decoration: const InputDecoration(hintText: 'e.g. Yoga mat', isDense: true, errorMaxLines: 2),
                validator: (v) => ContentLimits.materialError(v ?? ''),
              ),
            ),
            if (_materials.length > 1)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: AppColors.textMuted),
                onPressed: () => setState(() {
                  _materials[i].dispose();
                  _materials.removeAt(i);
                }),
              ),
          ],
        ),
      );
}
