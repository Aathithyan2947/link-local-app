import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../profile/data/profile_repository.dart';
import '../data/service_profile_repository.dart';

/// Lets a service provider fill the dynamic fields configured for their selected subcategories,
/// including uploading files such as menu cards / rate cards.
class ServiceDetailsScreen extends ConsumerStatefulWidget {
  const ServiceDetailsScreen({super.key});

  @override
  ConsumerState<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends ConsumerState<ServiceDetailsScreen> {
  List<CustomField>? _fields;
  final _ctrls = <int, TextEditingController>{};
  final _uploading = <int>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fields = await ref.read(serviceProfileRepositoryProvider).getCustomFields();
      for (final f in fields) {
        _ctrls[f.fieldId] = TextEditingController(text: f.value ?? '');
      }
      if (mounted) setState(() => _fields = fields);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickFile(int fieldId) async {
    try {
      final result = await FilePicker.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      final f = result?.files.single;
      if (f?.bytes == null) return;
      setState(() => _uploading.add(fieldId));
      final url = await ref.read(serviceProfileRepositoryProvider).uploadCustomFieldFile(f!.bytes!, f.name);
      _ctrls[fieldId]!.text = url;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading.remove(fieldId));
    }
  }

  Future<void> _save() async {
    for (final f in _fields ?? const <CustomField>[]) {
      if (f.isRequired && _ctrls[f.fieldId]!.text.trim().isEmpty) {
        setState(() => _error = '${f.fieldName} is required');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = _fields!
          .map((f) => {'fieldId': f.fieldId, 'value': _ctrls[f.fieldId]!.text})
          .toList();
      await ref.read(serviceProfileRepositoryProvider).saveCustomFields(values);
      ref.invalidate(customFieldsProvider);
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service details saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Service Details')),
      body: fields == null
          ? (_error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: _error!)))
              : const Center(child: CircularProgressIndicator()))
          : fields.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No extra details are needed for your selected services. Pick your services first, then come back here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    for (int i = 0; i < fields.length; i++) ...[
                      if (i == 0 || fields[i].subcategoryName != fields[i - 1].subcategoryName) ...[
                        if (i != 0) const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(fields[i].subcategoryName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ],
                      _fieldWidget(fields[i]),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 16)],
                    PrimaryButton(label: 'Save', loading: _saving, onPressed: _save),
                  ],
                ),
    );
  }

  Widget _label(CustomField f) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            text: f.fieldName,
            style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
            children: f.isRequired ? [const TextSpan(text: ' *', style: TextStyle(color: AppColors.error))] : null,
          ),
        ),
      );

  Widget _fieldWidget(CustomField f) {
    final ctrl = _ctrls[f.fieldId]!;
    switch (f.fieldType) {
      case 'file':
        final has = ctrl.text.isNotEmpty;
        final uploading = _uploading.contains(f.fieldId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            OutlinedButton.icon(
              onPressed: uploading ? null : () => _pickFile(f.fieldId),
              icon: uploading
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(has ? Icons.check_circle : Icons.upload_file, color: has ? AppColors.primary : null),
              label: Text(has ? 'Uploaded — tap to replace' : 'Upload ${f.fieldName}'),
            ),
            if (has)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(ctrl.text.split('/').last,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
          ],
        );
      case 'boolean':
        return Row(
          children: [
            Expanded(child: _label(f)),
            Switch(
              value: ctrl.text == 'true',
              onChanged: (v) => setState(() => ctrl.text = v ? 'true' : 'false'),
            ),
          ],
        );
      case 'dropdown':
        final opts = _options(f.fieldOptions);
        final current = opts.contains(ctrl.text) ? ctrl.text : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            DropdownButtonFormField<String>(
              initialValue: current,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Select'),
              items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) => setState(() => ctrl.text = v ?? ''),
            ),
          ],
        );
      case 'date':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: DateTime(now.year - 80),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) {
                  setState(() => ctrl.text = picked.toIso8601String().split('T').first);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(hintText: 'Select date'),
                child: Text(ctrl.text.isEmpty ? 'Select date' : ctrl.text,
                    style: TextStyle(color: ctrl.text.isEmpty ? AppColors.textMuted : AppColors.ink)),
              ),
            ),
          ],
        );
      case 'number':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: f.fieldName)),
          ],
        );
      default: // text
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            TextField(controller: ctrl, decoration: InputDecoration(hintText: f.fieldName)),
          ],
        );
    }
  }

  List<String> _options(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
