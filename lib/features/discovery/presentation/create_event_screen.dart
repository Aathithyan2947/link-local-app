import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/input_formatters.dart';
import '../data/event_detail_models.dart';
import '../discovery_repository.dart';
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
  final List<TextEditingController> _materials = [TextEditingController()];

  DateTime? _date;
  TimeOfDay? _time;
  String _mode = 'offline';
  bool _isPaid = false;
  XFile? _image;
  String? _existingPhotoUrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    if (e == null) return;
    _title.text = e.title;
    _description.text = e.description ?? '';
    _location.text = e.location ?? '';
    _onlineLink.text = e.onlineLink ?? '';
    _price.text = e.price != null ? e.price!.toStringAsFixed(0) : '';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a date')));
      return;
    }
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
        if (_time != null) 'startTime': '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
        if (_duration.text.trim().isNotEmpty) 'durationMinutes': int.tryParse(_duration.text.trim()),
        'mode': _mode,
        if (_mode == 'offline' && _location.text.trim().isNotEmpty) 'location': _location.text.trim(),
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
        ref.invalidate(eventsProvider);
        ref.invalidate(myEventsProvider);
        ref.invalidate(eventDetailProvider(id));
        await ref.read(eventDetailProvider(id).future);
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        final id = await repo.createEvent(data);
        if (!mounted) return;
        ref.invalidate(eventsProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => EventDetailScreen(id: id)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.isEdit ? 'Could not save event' : 'Could not create event')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit Event' : 'Host an Event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _imagePicker(),
            const SizedBox(height: 16),
            _field(_title, 'Event title', required: true),
            const SizedBox(height: 12),
            _field(_description, 'Description', maxLines: 3),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _dateField()),
              const SizedBox(width: 12),
              Expanded(child: _timeField()),
            ]),
            const SizedBox(height: 12),
            _field(_duration, 'Duration (minutes)', keyboard: TextInputType.number, formatters: kIntegerInput),
            const SizedBox(height: 16),
            _modeSelector(),
            const SizedBox(height: 12),
            if (_mode == 'offline')
              _field(_location, 'Location')
            else
              _field(_onlineLink, 'Online link'),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.primary,
              title: const Text('Paid event', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _isPaid,
              onChanged: (v) => setState(() => _isPaid = v),
            ),
            if (_isPaid) _field(_price, 'Price (₹)', keyboard: kDecimalKeyboard, formatters: kDecimalInput),
            const SizedBox(height: 12),
            _field(_maxAttendees, 'Max attendees (optional)', keyboard: TextInputType.number, formatters: kIntegerInput),
            const SizedBox(height: 20),
            const Text('What to bring / Guidelines', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            ..._materials.asMap().entries.map((e) => _materialRow(e.key)),
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

  Widget _field(TextEditingController c, String label,
      {bool required = false, int maxLines = 1, TextInputType? keyboard, List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
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
          if (picked != null) setState(() => _date = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Date'),
          child: Text(_date != null ? DateFormat('EEE, MMM d').format(_date!) : 'Select',
              style: TextStyle(color: _date != null ? AppColors.textPrimary : AppColors.textMuted)),
        ),
      );

  Widget _timeField() => InkWell(
        onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
          if (picked != null) setState(() => _time = picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Start time'),
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
              child: TextField(
                controller: _materials[i],
                decoration: const InputDecoration(hintText: 'e.g. Yoga mat', isDense: true),
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
