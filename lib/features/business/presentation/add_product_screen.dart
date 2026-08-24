import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/media/image_editor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/input_formatters.dart';
import '../../discovery/discovery_repository.dart';
import '../data/business_repository.dart';
import '../data/product_models.dart';

/// Create or edit a product (the "Product" frame).
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key, this.product});
  final SpProduct? product;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _category = TextEditingController(text: widget.product?.category);
  late final _price = TextEditingController(text: widget.product?.price?.toStringAsFixed(0));
  late final _quantity = TextEditingController(text: widget.product?.quantityMetric);
  late final _description = TextEditingController(text: widget.product?.description);
  /// The SP's own customization menu for this product. Editable — the old build offered only
  /// a fixed "Eggless" / "Custom message" pair, which suited a bakery and nobody else.
  late final List<ProductCustomization> _customizations =
      List.of(widget.product?.customizations ?? const <ProductCustomization>[]);
  XFile? _image;
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  @override
  void dispose() {
    for (final c in [_name, _category, _price, _quantity, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      String? photoUrl = widget.product?.photoUrl;
      if (_image != null) photoUrl = await repo.uploadImage(_image!.path, type: 'product');

      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'category': ?_nullIfEmpty(_category.text),
        if (_price.text.trim().isNotEmpty) 'price': double.tryParse(_price.text.trim()),
        'quantityMetric': ?_nullIfEmpty(_quantity.text),
        'description': ?_nullIfEmpty(_description.text),
        'photoUrl': ?photoUrl,
        'customizations': _customizations.map((c) => c.toJson()).toList(),
      };
      if (_isEdit) {
        await repo.updateProduct(widget.product!.id, data);
      } else {
        await repo.createProduct(data);
      }
      if (!mounted) return;
      ref.invalidate(myProductsProvider);
      ref.invalidate(serviceProviderDetailProvider);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final message = e is DioException ? ApiException.fromDio(e).message : 'Could not save product';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  static const _maxCustomizations = 10; // matches the server-side cap

  /// Adds an option, or edits the one at [index]. Returns without changes if the SP cancels
  /// or enters a label they already use on this product.
  Future<void> _editCustomization({int? index}) async {
    final existing = index == null ? null : _customizations[index];
    final suggestions = ref.read(myCustomizationLabelsProvider).asData?.value ?? const <ProductCustomization>[];
    final taken = {
      for (var i = 0; i < _customizations.length; i++)
        if (i != index) _customizations[i].label.toLowerCase(),
    };

    final result = await showModalBottomSheet<ProductCustomization>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CustomizationSheet(
        initial: existing,
        // Only offer labels not already on this product.
        suggestions: suggestions.where((s) => !taken.contains(s.label.toLowerCase())).toList(),
        isTaken: (label) => taken.contains(label.trim().toLowerCase()),
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _customizations.add(result);
      } else {
        _customizations[index] = result;
      }
    });
  }

  Widget _customizationEditor() {
    final full = _customizations.length >= _maxCustomizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Customization', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 2),
        const Text(
          'Choices you offer on this item. Residents pick from these when ordering.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        for (final (i, c) in _customizations.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ListTile(
              dense: true,
              title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              subtitle: Text(
                [
                  c.wantsText ? 'Resident types a note' : 'Yes / no choice',
                  if (c.isRequired) 'required',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary),
                    onPressed: () => _editCustomization(index: i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    onPressed: () => setState(() => _customizations.removeAt(i)),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: full ? null : () => _editCustomization(),
          icon: const Icon(Icons.add, size: 18),
          label: Text(full ? 'Limit of $_maxCustomizations reached' : 'Add a customization'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Product')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _imagePicker(),
            const SizedBox(height: 6),
            const Text('JPG, PNG or WEBP · up to 10MB',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            _field(_name, 'Product Name', required: true),
            const SizedBox(height: 12),
            _field(_category, 'Category'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_price, 'Price', keyboard: kDecimalKeyboard, formatters: kDecimalInput)),
              const SizedBox(width: 12),
              Expanded(child: _field(_quantity, 'Quantity / Unit')),
            ]),
            const SizedBox(height: 12),
            _field(_description, 'Description', maxLines: 3),
            const SizedBox(height: 18),
            _customizationEditor(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() {
    final existing = widget.product?.photoUrl;
    return GestureDetector(
      onTap: _pick,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _image != null
            ? Image.file(File(_image!.path), fit: BoxFit.cover)
            : (existing != null && existing.isNotEmpty)
                ? CachedNetworkImage(imageUrl: AppConfig.assetUrl(existing), fit: BoxFit.cover)
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 34, color: AppColors.textMuted),
                        SizedBox(height: 6),
                        Text('Add image of your item', style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool required = false, int maxLines = 1, TextInputType? keyboard, List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }
}

/// Add/edit one customization. Kept in a sheet so the product form stays short, and so the
/// label field can offer what the SP already uses elsewhere.
class _CustomizationSheet extends StatefulWidget {
  const _CustomizationSheet({required this.initial, required this.suggestions, required this.isTaken});
  final ProductCustomization? initial;
  final List<ProductCustomization> suggestions;
  final bool Function(String label) isTaken;

  @override
  State<_CustomizationSheet> createState() => _CustomizationSheetState();
}

class _CustomizationSheetState extends State<_CustomizationSheet> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late String _inputType = widget.initial?.inputType ?? 'toggle';
  late bool _isRequired = widget.initial?.isRequired ?? false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim();
    if (label.isEmpty) return setState(() => _error = 'Give this option a name');
    if (label.length > 60) return setState(() => _error = 'Keep it under 60 characters');
    if (widget.isTaken(label)) return setState(() => _error = 'This item already has that option');
    Navigator.of(context).pop(
      ProductCustomization(label: label, inputType: _inputType, isRequired: _isRequired),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.initial == null ? 'Add a customization' : 'Edit customization',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 14),
          TextField(
            controller: _label,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Option name', hintText: 'e.g. Eggless, Extra spicy'),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Used on your other items', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in widget.suggestions)
                  ActionChip(
                    label: Text(s.label),
                    onPressed: () => setState(() {
                      _label.text = s.label;
                      _inputType = s.inputType;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text('How would you like your customers to respond?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'toggle', label: Text('Yes / no')),
              ButtonSegment(value: 'text', label: Text('They type a note')),
            ],
            selected: {_inputType},
            onSelectionChanged: (v) => setState(() => _inputType = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primary,
            title: const Text('Must be answered', style: TextStyle(fontSize: 14.5)),
            value: _isRequired,
            onChanged: (v) => setState(() => _isRequired = v),
          ),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _submit, child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}
