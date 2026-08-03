import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../business/data/business_repository.dart';
import '../../business/presentation/sp_products_screen.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import '../../profile/data/profile_repository.dart';
import '../data/service_profile_repository.dart';
import 'area_picker_screen.dart';

/// Fixed category order/labels matching the Figma "Tutor Flow" onboarding screens.
const kCategoryOrder = ['basic_details', 'travel', 'payment', 'service_type', 'delivery'];
const kCategoryLabels = {
  'basic_details': 'Basic Details',
  'travel': 'Travel',
  'payment': 'Payment & Fee',
  'service_type': 'Service Type',
  'delivery': 'Delivery',
};

/// The categories (in display order) that actually have configured fields.
List<String> availableCategories(List<CustomField> fields) {
  final present = fields.map((f) => f.category).toSet();
  return kCategoryOrder.where(present.contains).toList();
}

/// Same as [availableCategories], but for menu-type SPs always includes 'service_type' —
/// Products/menu setup can never have admin-configured fields (it's per-item catalogue data,
/// not a per-profile answer), so it's a native step in the chain rather than field-driven.
/// 'delivery' needs no such forcing: once an admin configures its fields it appears here
/// exactly like Basic Details/Travel do.
List<String> onboardingCategories(List<CustomField> fields, {required bool hasMenu}) {
  final present = fields.map((f) => f.category).toSet();
  if (hasMenu) present.add('service_type');
  return kCategoryOrder.where(present.contains).toList();
}

/// Advances the SP onboarding/edit chain to its next step. `service_type` on a menu-type SP
/// goes to the native Products screen; everything else (including `delivery`, once it has
/// admin fields) is the generic [CategoryFieldsFormScreen]. An empty [remaining] lands on the
/// SP's own profile view. Pass `replace: true` when called from inside the chain (so the
/// current step isn't left on the back stack); `false` for the very first push.
Future<void> pushOnboardingStep(
  BuildContext context,
  WidgetRef ref,
  List<String> remaining, {
  required bool replace,
}) async {
  if (remaining.isEmpty) {
    final myId = ref.read(myProfileProvider).asData?.value.id;
    if (myId == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: myId)),
      (route) => route.isFirst,
    );
    return;
  }

  final cat = remaining.first;
  final rest = remaining.sublist(1);
  var hasMenu = false;
  try {
    hasMenu = (await ref.read(businessRepositoryProvider).myProviderFeatures()).hasMenu;
  } catch (_) {
    // Don't let a transient feature-check failure block the chain.
  }
  if (!context.mounted) return;

  final Widget screen = (hasMenu && cat == 'service_type')
      ? SpProductsScreen(fromOnboarding: true, nextCategories: rest)
      : CategoryFieldsFormScreen(category: cat, categoryLabel: kCategoryLabels[cat] ?? cat, nextCategories: rest);
  final route = MaterialPageRoute(builder: (_) => screen);
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// Lets a service provider fill in the admin-configured fields for one category (Basic
/// Details / Travel / Payment / Service Type / Delivery).
///
/// Matches the Figma flow exactly: when [nextCategories] is non-null, this screen is one
/// step in the initial onboarding chain — the button reads "Next" and, on save, replaces
/// itself with the next category's form; on the last category it reads "Confirm" and lands
/// directly on the SP's own profile view. When [nextCategories] is null (reached via an
/// edit-pencil on the profile view), it's a standalone edit — a single "Save" pops back.
class CategoryFieldsFormScreen extends ConsumerStatefulWidget {
  const CategoryFieldsFormScreen({
    super.key,
    required this.category,
    required this.categoryLabel,
    this.nextCategories,
  });

  final String category;
  final String categoryLabel;
  final List<String>? nextCategories;

  @override
  ConsumerState<CategoryFieldsFormScreen> createState() => _CategoryFieldsFormScreenState();
}

class _CategoryFieldsFormScreenState extends ConsumerState<CategoryFieldsFormScreen> {
  List<CustomField>? _fields;
  final _ctrls = <int, TextEditingController>{};
  final _pincodeSelections = <int, List<SelectedArea>>{};
  final _uploading = <int>{};
  final _pendingImages = <int, XFile>{};
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
      final all = await ref.read(serviceProfileRepositoryProvider).getCustomFields();
      final fields = all.where((f) => f.category == widget.category).toList();
      for (final f in fields) {
        _ctrls[f.fieldId] = TextEditingController(text: f.value ?? '');
        if (f.fieldType == 'pincode') {
          _pincodeSelections[f.fieldId] = f.resolvedAreas ?? [];
        }
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

  Future<void> _pickImage(int fieldId) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img == null) return;
    setState(() {
      _pendingImages[fieldId] = img;
      _uploading.add(fieldId);
    });
    try {
      final bytes = await img.readAsBytes();
      final url = await ref.read(serviceProfileRepositoryProvider).uploadCustomFieldFile(bytes, img.name);
      _ctrls[fieldId]!.text = url;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading.remove(fieldId));
    }
  }

  Future<void> _pickAreas(CustomField f) async {
    final myProfile = ref.read(myProfileProvider).asData?.value;
    final result = await Navigator.of(context).push<List<SelectedArea>>(MaterialPageRoute(
      builder: (_) => AreaPickerScreen(
        initialSelection: _pincodeSelections[f.fieldId] ?? [],
        cityId: myProfile?.cityId,
      ),
    ));
    if (result == null) return;
    setState(() {
      _pincodeSelections[f.fieldId] = result;
      _ctrls[f.fieldId]!.text = jsonEncode(result.map((a) => a.id).toList());
    });
  }

  /// Whether [f] should currently be shown/saved — false for a dependent field whose
  /// controlling field doesn't hold the required value.
  bool _isVisible(CustomField f) {
    if (f.dependsOnFieldId == null) return true;
    return _ctrls[f.dependsOnFieldId]?.text == f.dependsOnValue;
  }

  List<CustomField> get _visibleFields => (_fields ?? const <CustomField>[]).where(_isVisible).toList();

  Future<void> _save() async {
    for (final f in _visibleFields) {
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
      final values = _visibleFields
          .map((f) => {'fieldId': f.fieldId, 'value': _ctrls[f.fieldId]!.text})
          .toList();
      await ref.read(serviceProfileRepositoryProvider).saveCustomFields(values);
      ref.invalidate(customFieldsProvider);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      final next = widget.nextCategories;
      if (next == null) {
        // Standalone edit (opened via a profile-view edit-pencil) — save and return.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.categoryLabel} saved')));
        Navigator.pop(context);
      } else {
        await pushOnboardingStep(context, ref, next, replace: true);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _buttonLabel {
    final next = widget.nextCategories;
    if (next == null) return 'Save';
    return next.isEmpty ? 'Confirm' : 'Next';
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields == null ? null : _visibleFields;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.categoryLabel)),
      body: fields == null
          ? (_error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: ErrorBanner(message: _error!)))
              : const Center(child: CircularProgressIndicator()))
          : fields.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No fields configured for ${widget.categoryLabel} yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    for (final f in fields) ...[
                      _fieldWidget(f),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 16)],
                    PrimaryButton(label: _buttonLabel, loading: _saving, onPressed: _save),
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
      case 'pincode':
        final selected = _pincodeSelections[f.fieldId] ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in selected)
                  Chip(
                    label: Text(a.label),
                    onDeleted: () => setState(() {
                      selected.removeWhere((x) => x.id == a.id);
                      _pincodeSelections[f.fieldId] = List.of(selected);
                      ctrl.text = jsonEncode(selected.map((x) => x.id).toList());
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add area'),
                  onPressed: () => _pickAreas(f),
                ),
              ],
            ),
          ],
        );
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
      case 'image':
        final pending = _pendingImages[f.fieldId];
        final existing = ctrl.text;
        final busy = _uploading.contains(f.fieldId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            GestureDetector(
              onTap: busy ? null : () => _pickImage(f.fieldId),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: AppColors.field,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (pending != null)
                      Image.file(File(pending.path), fit: BoxFit.cover)
                    else if (existing.isNotEmpty)
                      CachedNetworkImage(imageUrl: AppConfig.assetUrl(existing), fit: BoxFit.cover)
                    else
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppColors.textMuted),
                            SizedBox(height: 6),
                            Text('Upload photo', style: TextStyle(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    if (busy)
                      Container(
                        color: Colors.black26,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
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
