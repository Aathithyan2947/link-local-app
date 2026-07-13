import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../data/cart.dart';
import '../data/orders_repository.dart';
import 'order_success_screen.dart';

/// Reviews the cart and places the order — the "Cart Review" frame.
class CartReviewScreen extends ConsumerStatefulWidget {
  const CartReviewScreen({super.key});

  @override
  ConsumerState<CartReviewScreen> createState() => _CartReviewScreenState();
}

class _CartReviewScreenState extends ConsumerState<CartReviewScreen> {
  String _delivery = 'home_delivery';
  int _slot = 0;
  bool _placing = false;

  static const _slots = ['Tomorrow, 10:00 AM – 12:00 PM', 'Tomorrow, 1:00 PM – 3:00 PM', 'Tomorrow, 4:00 PM – 6:00 PM'];

  Future<void> _confirm(Cart cart) async {
    setState(() => _placing = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final order = await repo.placeOrder({
        'spProfileId': cart.spProfileId,
        'items': cart.items
            .map((l) => {
                  'productId': l.product.id,
                  'quantity': l.qty,
                  if (l.product.customizationNotes?.isNotEmpty == true)
                    'customizationNotes': l.product.customizationNotes,
                })
            .toList(),
        'deliveryType': _delivery,
        'specialInstructions': 'Preferred slot: ${_slots[_slot]}',
      });
      await repo.pay(order.id); // MOCK payment
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myOrdersProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderSuccessScreen(orderId: order.id, total: order.totalAmount)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not place order')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final deliveryFee = _delivery == 'home_delivery' ? 0.0 : 0.0; // computed server-side; shown as included
    final total = cart.subtotal + deliveryFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cart Review')),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _placing ? null : () => _confirm(cart),
                  child: _placing
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Confirm  ·  ₹${total.toStringAsFixed(0)}'),
                ),
              ),
            ),
      body: cart.isEmpty
          ? const Center(child: Text('Your cart is empty'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Products in your cart', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                ...cart.items.map((l) => _line(l.product.id, l.product.name, l.product.photoUrl, l.product.price ?? 0, l.qty, notifier)),
                const Divider(height: 28),
                _row('Subtotal (${cart.count} items)', '₹${cart.subtotal.toStringAsFixed(0)}'),
                _row('Delivery fee', _delivery == 'pickup' ? 'Pickup' : 'Calculated at checkout'),
                const SizedBox(height: 6),
                _row('Total', '₹${total.toStringAsFixed(0)}', bold: true),
                const SizedBox(height: 20),
                const Text('Delivery method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Row(children: [
                  Expanded(child: _choice('Home delivery', 'home_delivery')),
                  const SizedBox(width: 10),
                  Expanded(child: _choice('Pickup', 'pickup')),
                ]),
                const SizedBox(height: 16),
                const Text('Choose delivery time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ..._slots.asMap().entries.map((e) => InkWell(
                      onTap: () => setState(() => _slot = e.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(_slot == e.key ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: _slot == e.key ? AppColors.primary : AppColors.textMuted, size: 22),
                            const SizedBox(width: 12),
                            Text(e.value, style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    )),
              ],
            ),
    );
  }

  Widget _line(int id, String name, String? photo, double price, int qty, CartNotifier n) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (photo != null && photo.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: AppConfig.assetUrl(photo), width: 52, height: 52, fit: BoxFit.cover, errorWidget: (_, _, _) => _ph())
                  : _ph(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('₹${price.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            _stepper(qty, () => n.setQty(id, qty - 1), () => n.setQty(id, qty + 1)),
          ],
        ),
      );

  Widget _stepper(int qty, VoidCallback minus, VoidCallback plus) => Container(
        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            _stepBtn(Icons.remove, minus),
            SizedBox(width: 24, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
            _stepBtn(Icons.add, plus),
          ],
        ),
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 16, color: AppColors.primary)),
      );

  Widget _ph() => Container(width: 52, height: 52, color: AppColors.primarySurface, child: const Icon(Icons.bakery_dining_outlined, color: AppColors.primary));

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: bold ? AppColors.ink : AppColors.textSecondary)),
            Text(value, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: bold ? AppColors.primary : AppColors.textPrimary)),
          ],
        ),
      );

  Widget _choice(String label, String value) => InkWell(
        onTap: () => setState(() => _delivery = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _delivery == value ? AppColors.primarySurface : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _delivery == value ? AppColors.primary : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: _delivery == value ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
      );
}
