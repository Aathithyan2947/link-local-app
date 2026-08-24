import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/input_formatters.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/data/availability_models.dart';
import '../../business/data/business_repository.dart';
import '../../business/presentation/setup/sp_setup_wizard_screen.dart';
import '../../business/presentation/sp_products_screen.dart';
import '../../discovery/discovery_repository.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/data/profile_repository.dart';
import '../data/basic_details_fields.dart';
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

/// A `menu` / `date` field marks a feature the SP sets up elsewhere (their item catalogue,
/// their availability) rather than a question with a typed answer. It renders as a link into
/// that editor, is never "unanswered", and its value is never saved.
/// `date` is deliberately NOT one of these — it's an ordinary date question that renders a
/// picker. It used to double as the booking marker, so any date question an admin added
/// switched slot booking on for the whole subcategory.
bool isFeatureMarker(CustomField f) => f.fieldType == 'menu' || f.fieldType == 'booking';

/// The categories that make up this SP's onboarding chain, in display order.
///
/// Every step is now field-driven, including Service Type: a menu subcategory carries a
/// `menu` marker field there, so nothing has to be forced in. `hasMenu` used to be ORed in
/// here because the Products step had no fields to detect — see lib/providerKind.ts.
List<String> onboardingCategories(List<CustomField> fields, {bool hasMenu = false}) {
  final present = fields.map((f) => f.category).toSet();
  return kCategoryOrder.where(present.contains).toList();
}

/// The admin-configured fields an onboarding-completion prompt should judge: everything in the
/// SP's onboarding chain, minus [excluding] (the home banner drops `payment`).
List<CustomField> onboardingRelevantFields(
  List<CustomField> fields, {
  required bool hasMenu,
  Set<String> excluding = const {},
}) {
  final cats = onboardingCategories(fields, hasMenu: hasMenu).where((c) => !excluding.contains(c)).toSet();
  return fields.where((f) => cats.contains(f.category)).toList();
}

/// Whether any required field among [relevant] is still blank.
///
/// This is only half the picture: whether onboarding was *finished* is recorded on the profile
/// when the SP confirms the last step ([ProfileDetail.hasFinishedOnboarding]), never inferred
/// from answers. Inference used to decide it, and got it wrong two ways — a subcategory that
/// marks nothing required (the whole Tutor set) read as done on day one, and the Products step
/// has no admin fields at all, so a menu SP who never added an item read as done too. This
/// remains useful for the case recording can't cover: an admin adding a required field after
/// the SP already finished.
bool hasUnansweredRequiredField(List<CustomField> relevant) => relevant
    .any((f) => f.isRequired && !isFeatureMarker(f) && (f.value?.trim().isEmpty ?? true));

/// Advances the SP onboarding/edit chain to its next step. `service_type` on a menu-type SP
/// goes to the native Products screen; everything else (including `delivery`, once it has
/// admin fields) is the generic [CategoryFieldsFormScreen]. An empty [remaining] lands on the
/// SP's own profile view.
///
/// Each step is pushed, so back returns to the previous one and it reloads what was saved
/// there. Back pops that route, so pressing Next again re-pushes rather than stacking a
/// second copy. The final step clears the whole chain off the stack.
Future<void> pushOnboardingStep(
  BuildContext context,
  WidgetRef ref,
  List<String> remaining,
) async {
  if (remaining.isEmpty) {
    // Read the id before invalidating below, or the refetch leaves it null and we'd pop
    // instead of landing on the profile.
    final myId = ref.read(myProfileProvider).asData?.value.id;
    // The chain is finished — this is the only point that means "they went through every step
    // and filled in what they could", so it's recorded here rather than inferred from which
    // fields happen to be answered (the Products step has no fields to inspect at all).
    try {
      await ref.read(profileRepositoryProvider).markOnboardingComplete();
      ref.invalidate(myProfileProvider);
      // This hop pushes a fresh profile route rather than returning to one, so didPopNext
      // won't fire — the cached detail must be dropped explicitly.
      ref.invalidate(serviceProviderDetailProvider);
    } catch (_) {
      // Never block the SP from reaching their profile over a bookkeeping call.
    }
    if (!context.mounted) return;
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
  // Service Type is an ordinary step now. It used to be replaced wholesale by the products
  // screen for menu SPs, which meant any other field an admin configured there was never
  // shown; the menu marker renders inside the step instead.
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CategoryFieldsFormScreen(
      category: cat,
      categoryLabel: kCategoryLabels[cat] ?? cat,
      nextCategories: rest,
    ),
  ));
}

/// Lets a service provider fill in the admin-configured fields for one category (Basic
/// Details / Travel / Payment / Service Type / Delivery).
///
/// Matches the Figma flow exactly: when [nextCategories] is non-null, this screen is one
/// step in the initial onboarding chain — the button reads "Next" and, on save, opens the
/// next category's form; on the last category it reads "Confirm" and lands directly on the
/// SP's own profile view. When [nextCategories] is null (reached via an edit-pencil on the
/// profile view), it's a standalone edit — a single "Save" pops back.
///
/// Answers are written on every Next, so backing out mid-chain keeps what was filled in and
/// returning to a step reloads it (see [_load]).
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

  /// fieldId → the value we seeded from the SP's account (see [prefillForBasicDetailsField]).
  /// Drives the "From your account" caption, which drops away once the SP edits the value.
  final _prefilled = <int, String>{};

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
      final profile = widget.category == 'basic_details' ? await _profileForPrefill() : null;
      final user = ref.read(authControllerProvider).user;
      for (final f in fields) {
        var text = f.value ?? '';
        // Only ever seed a blank field — a saved answer is authoritative.
        if (text.trim().isEmpty && widget.category == 'basic_details') {
          final suggested = prefillForBasicDetailsField(f.fieldName, user: user, profile: profile);
          if (suggested != null) {
            text = suggested;
            _prefilled[f.fieldId] = suggested;
          }
        }
        _ctrls[f.fieldId] = TextEditingController(text: text);
        if (f.fieldType == 'pincode') {
          _pincodeSelections[f.fieldId] = f.resolvedAreas ?? [];
        }
      }
      if (mounted) setState(() => _fields = fields);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// The SP's profile, for prefill only — a failure here must not block the form, so it
  /// degrades to "nothing to suggest" rather than surfacing an error.
  Future<ProfileDetail?> _profileForPrefill() async {
    try {
      return await ref.read(myProfileProvider.future);
    } catch (_) {
      return null;
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
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    if (!mounted) return;
    final rawBytes = await picked.readAsBytes();
    if (!mounted) return;
    final edited = await editPickedImageBytes(context, rawBytes);
    if (edited == null) return;
    final path = await writeEditedImageToTempFile(edited);
    final editedImage = XFile(path);
    setState(() {
      _pendingImages[fieldId] = editedImage;
      _uploading.add(fieldId);
    });
    try {
      final bytes = await editedImage.readAsBytes();
      final url = await ref.read(serviceProfileRepositoryProvider).uploadCustomFieldFile(bytes, editedImage.name);
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
      // A marker has no typed answer to require.
      if (f.isRequired && !isFeatureMarker(f) && _ctrls[f.fieldId]!.text.trim().isEmpty) {
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
          .where((f) => !isFeatureMarker(f))
          .map((f) => {'fieldId': f.fieldId, 'value': _ctrls[f.fieldId]!.text})
          .toList();
      await ref.read(serviceProfileRepositoryProvider).saveCustomFields(values);
      // The Service Phone/Email answers also live on the profile, which is what the Contact
      // Info block shows and edits — keep the two in step.
      final updates = serviceContactUpdates({
        for (final f in _visibleFields) f.fieldName: _ctrls[f.fieldId]!.text,
      });
      if (updates.isNotEmpty) {
        try {
          await ref.read(profileRepositoryProvider).updateBasic(updates);
        } catch (_) {
          // The answers are saved; a failed mirror must not fail the step.
        }
      }
      ref.invalidate(customFieldsProvider);
      ref.invalidate(myProfileProvider);
      // Covers entry points that don't live under a ServiceProviderDetailScreen instance
      // (e.g. the Profile tab's "Delivery settings" menu item), where didPopNext never fires.
      ref.invalidate(serviceProviderDetailProvider);
      if (!mounted) return;
      final next = widget.nextCategories;
      if (next == null) {
        // Standalone edit (opened via a profile-view edit-pencil) — save and return.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.categoryLabel} saved')));
        Navigator.pop(context);
      } else {
        await pushOnboardingStep(context, ref, next);
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

  /// Opens the native editor a marker field points at. Availability needs the SP's current
  /// template and feature flags, so they're fetched first; a failure just opens it empty.
  Future<void> _openMarkerEditor(bool isMenu) async {
    if (isMenu) {
      final proceed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SpProductsScreen(fromOnboarding: widget.nextCategories != null),
      ));
      if (proceed == true && mounted) await _save();
      return;
    }
    AvailabilityData? availability;
    ({bool hasMenu, bool hasDateBooking})? features;
    try {
      final repo = ref.read(businessRepositoryProvider);
      availability = await repo.availability();
      features = await repo.myProviderFeatures();
    } catch (_) {
      // Fall through with what we have.
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SpSetupWizardScreen(
        initialAvailability: availability?.availability,
        hasMenu: features?.hasMenu ?? false,
        hasDateBooking: features?.hasDateBooking ?? true,
      ),
    ));
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

  /// Caption marking a value we filled in from the SP's account rather than one they typed.
  /// Vanishes as soon as they edit it away, so it never mislabels their own input.
  Widget _prefillNote(CustomField f) {
    final seeded = _prefilled[f.fieldId];
    if (seeded == null) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _ctrls[f.fieldId]!,
      builder: (_, value, _) => value.text != seeded
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('From your account', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
    );
  }

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
      case 'menu':
      case 'booking':
        // Configuration, not a question: the SP sets these up in their own editor and this
        // just points there. Rendering it as a text box (the old default-case behaviour)
        // asked the SP to type their catalogue into a single line.
        final isMenu = f.fieldType == 'menu';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMenu
                        ? 'Add the items residents can order from you.'
                        : 'Set the days and times residents can book.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openMarkerEditor(isMenu),
                    icon: Icon(isMenu ? Icons.storefront_outlined : Icons.event_available_outlined, size: 18),
                    label: Text(isMenu ? 'Manage items' : 'Set availability'),
                  ),
                ],
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
            TextField(
                controller: ctrl,
                keyboardType: kDecimalKeyboard,
                inputFormatters: kDecimalInput,
                decoration: InputDecoration(hintText: f.fieldName)),
            _prefillNote(f),
          ],
        );
      default: // text
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(f),
            TextField(controller: ctrl, decoration: InputDecoration(hintText: f.fieldName)),
            _prefillNote(f),
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
