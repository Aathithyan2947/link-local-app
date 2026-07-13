import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
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
  late bool _eggless = widget.product?.customizationNotes?.contains('Eggless') ?? false;
  late bool _customMessage = widget.product?.customizationNotes?.contains('Custom message') ?? false;
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
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _image = img);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      String? photoUrl = widget.product?.photoUrl;
      if (_image != null) photoUrl = await repo.uploadImage(_image!.path);

      final custom = [
        if (_eggless) 'Eggless available',
        if (_customMessage) 'Custom message available',
      ].join('; ');

      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'category': ?_nullIfEmpty(_category.text),
        if (_price.text.trim().isNotEmpty) 'price': double.tryParse(_price.text.trim()),
        'quantityMetric': ?_nullIfEmpty(_quantity.text),
        'description': ?_nullIfEmpty(_description.text),
        'customizationNotes': ?_nullIfEmpty(custom),
        'photoUrl': ?photoUrl,
      };
      if (_isEdit) {
        await repo.updateProduct(widget.product!.id, data);
      } else {
        await repo.createProduct(data);
      }
      if (!mounted) return;
      ref.invalidate(myProductsProvider);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save product')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

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
            const SizedBox(height: 16),
            _field(_name, 'Product Name', required: true),
            const SizedBox(height: 12),
            _field(_category, 'Category'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _field(_price, 'Price', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field(_quantity, 'Quantity / Unit')),
            ]),
            const SizedBox(height: 12),
            _field(_description, 'Description', maxLines: 3),
            const SizedBox(height: 18),
            const Text('Customization', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Eggless Available'),
              value: _eggless,
              onChanged: (v) => setState(() => _eggless = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Custom Message Available'),
              value: _customMessage,
              onChanged: (v) => setState(() => _customMessage = v ?? false),
            ),
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

  Widget _field(TextEditingController c, String label, {bool required = false, int maxLines = 1, TextInputType? keyboard}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }
}
