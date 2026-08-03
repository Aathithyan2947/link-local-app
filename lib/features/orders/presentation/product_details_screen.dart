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
  bool _eggless = false;
  bool _customMessage = false;
  final _messageCtrl = TextEditingController();

  bool get _offersEggless => widget.product.customizationNotes?.contains('Eggless') == true;
  bool get _offersCustomMessage => widget.product.customizationNotes?.contains('Custom message') == true;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    final existing = cart.spProfileId == widget.spId ? cart.lines[widget.product.id] : null;
    _qty = existing != null && existing.qty > 0 ? existing.qty : 1;
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final parts = <String>[
      if (_eggless) 'Eggless',
      if (_customMessage) 'Custom message: ${_messageCtrl.text.trim()}',
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
    final showCustomization = _offersEggless || _offersCustomMessage;
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
                  if (_offersEggless)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      title: const Text('Eggless'),
                      value: _eggless,
                      onChanged: (v) => setState(() => _eggless = v ?? false),
                    ),
                  if (_offersCustomMessage) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      title: const Text('Custom message'),
                      value: _customMessage,
                      onChanged: (v) => setState(() => _customMessage = v ?? false),
                    ),
                    if (_customMessage)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextField(
                          controller: _messageCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Explain your request here…',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                  ],
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
