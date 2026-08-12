import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../business/data/product_models.dart';
import '../data/cart.dart';

/// Lets the resident pick quantity + their own customization (parsed from what the SP
/// offers on this product) before it goes into the cart — the "Product details" frame.
class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({super.key, required this.product, required this.spId, required this.spName});
  final SpProduct product;
  final int spId;
  final String spName;

  @override
  ConsumerState<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  late int _qty;

  /// Selections keyed by the option's label — the product defines the options, so nothing
  /// here is hard-coded to a particular trade.
  final _selected = <String, bool>{};
  final _notes = <String, TextEditingController>{};
  String? _error;

  List<ProductCustomization> get _options => widget.product.customizations;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    final existing = cart.spProfileId == widget.spId ? cart.lines[widget.product.id] : null;
    _qty = existing != null && existing.qty > 0 ? existing.qty : 1;
    for (final o in _options) {
      _selected[o.label] = false;
      if (o.wantsText) _notes[o.label] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    // A required option has to be answered — and one that takes a note needs the note.
    for (final o in _options.where((o) => o.isRequired)) {
      final on = _selected[o.label] ?? false;
      if (!on || (o.wantsText && _notes[o.label]!.text.trim().isEmpty)) {
        setState(() => _error = '${o.label} is required');
        return;
      }
    }
    // Rendered into one string: it's what the SP reads on the order, and what
    // OrderItem.customizationNotes has always stored.
    final parts = <String>[
      for (final o in _options)
        if (_selected[o.label] ?? false)
          if (o.wantsText && _notes[o.label]!.text.trim().isNotEmpty)
            '${o.label}: ${_notes[o.label]!.text.trim()}'
          else
            o.label,
    ];
    ref.read(cartProvider.notifier).addWithCustomization(
          widget.spId,
          widget.spName,
          widget.product,
          _qty,
          parts.isEmpty ? null : parts.join('; '),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final showCustomization = _options.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Product details')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(onPressed: _confirm, child: const Text('Confirm')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: AppConfig.assetUrl(p.photoUrl!),
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _ph(),
                      )
                    : _ph(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                    if (p.category != null && p.category!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.category!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                    const SizedBox(height: 4),
                    if (p.price != null)
                      Text('₹${(p.price! * _qty).toStringAsFixed(0)}${p.quantityLabel.isNotEmpty ? '  ·  ${p.quantityLabel}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              _stepper(),
            ],
          ),
          if (p.description != null && p.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(p.description!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
          ],
          if (showCustomization) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Customization options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  const Text('Make it truly yours!', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  for (final o in _options) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      title: Text(o.isRequired ? '${o.label} *' : o.label),
                      value: _selected[o.label] ?? false,
                      onChanged: (v) => setState(() {
                        _selected[o.label] = v ?? false;
                        _error = null;
                      }),
                    ),
                    if (o.wantsText && (_selected[o.label] ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: TextField(
                          controller: _notes[o.label],
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Explain your request here…',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                  ],
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepper() => Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            InkWell(
              onTap: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.remove, size: 18, color: AppColors.primary)),
            ),
            SizedBox(width: 28, child: Text('$_qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            InkWell(
              onTap: () => setState(() => _qty += 1),
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add, size: 18, color: AppColors.primary)),
            ),
          ],
        ),
      );

  Widget _ph() => Container(
        width: 90,
        height: 90,
        color: AppColors.primarySurface,
        child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary),
      );
}
