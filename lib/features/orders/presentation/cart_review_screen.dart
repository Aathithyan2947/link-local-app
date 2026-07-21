import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../business/data/availability_models.dart';
import '../../discovery/discovery_repository.dart';
import '../../payments/presentation/payment_method_screen.dart';
import '../data/cart.dart';
import '../data/order_models.dart';
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
  OpenSlot? _selectedSlot;
  bool _placing = false;

  final _coupon = TextEditingController();
  String? _appliedCoupon;
  OrderQuote? _quote;
  bool _quoting = false;
  String? _couponError;
  String _sig = '';

  @override
  void initState() {
    super.initState();
    // Initial fee breakdown once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshQuote(ref.read(cartProvider));
    });
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  /// Re-fetch the fee breakdown whenever the cart, delivery method, or coupon changes.
  Future<void> _refreshQuote(Cart cart) async {
    if (cart.isEmpty) return;
    final sig = '${cart.count}-${cart.subtotal}-$_delivery-$_appliedCoupon';
    if (sig == _sig) return;
    _sig = sig;
    setState(() => _quoting = true);
    try {
      final q = await ref.read(ordersRepositoryProvider).quote({
        'spProfileId': cart.spProfileId,
        'orderKind': 'product',
        'items': cart.items.map((l) => {'productId': l.product.id, 'quantity': l.qty}).toList(),
        'deliveryType': _delivery,
        if (_appliedCoupon != null) 'couponCode': _appliedCoupon,
      });
      if (mounted) {
        setState(() {
          _quote = q;
          if (_appliedCoupon != null && q.discount == 0) _couponError = 'Coupon not applied';
        });
      }
    } catch (_) {
      // Keep the last quote on transient errors.
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _confirm(Cart cart, {required bool hasSlots}) async {
    if (hasSlots && _selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pick a time slot')));
      return;
    }
    setState(() => _placing = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final slot = _selectedSlot;
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
        if (_appliedCoupon != null) 'couponCode': _appliedCoupon,
        if (slot != null) 'specialInstructions': 'Preferred slot: ${slot.dayLabel}, ${slot.timeLabel}',
        if (slot != null) 'scheduledSlot': slot.toJson(),
      });
      if (!mounted) return;
      // Route through the Payment method + UPI pages (mock gateway).
      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PaymentMethodScreen(orderId: order.id, total: order.totalAmount)),
      );
      if (!mounted) return;
      if (paid == true) {
        ref.read(cartProvider.notifier).clear();
        ref.invalidate(myOrdersProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => OrderSuccessScreen(orderId: order.id, total: order.totalAmount)),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      // The slot was booked by someone else between viewing and confirming.
      if (e.response?.statusCode == 409) {
        setState(() => _selectedSlot = null);
        ref.invalidate(spSlotsProvider(cart.spProfileId!));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That slot was just taken. Please pick another.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not place order')));
      }
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
    final slotsAsync = cart.isEmpty ? null : ref.watch(spSlotsProvider(cart.spProfileId!));
    final hasSlots = slotsAsync?.asData?.value.isNotEmpty ?? false;
    final total = _quote?.total ?? cart.subtotal;

    // Re-price when the cart changes (qty edits, item removal) — outside of build.
    ref.listen<Cart>(cartProvider, (_, next) => _refreshQuote(next));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cart Review')),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _placing ? null : () => _confirm(cart, hasSlots: hasSlots),
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
                const SizedBox(height: 16),
                const Text('Delivery method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Row(children: [
                  Expanded(child: _choice('Home delivery', 'home_delivery')),
                  const SizedBox(width: 10),
                  Expanded(child: _choice('Pickup', 'pickup')),
                ]),
                const SizedBox(height: 16),
                _couponField(),
                const Divider(height: 28),
                _feeBreakdown(cart),
                const SizedBox(height: 20),
                const Text('Choose a time slot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                if (slotsAsync != null) _slotPicker(slotsAsync),
              ],
            ),
    );
  }

  Widget _feeBreakdown(Cart cart) {
    final q = _quote;
    return Column(
      children: [
        _row('Subtotal (${cart.count} items)', '₹${(q?.subtotal ?? cart.subtotal).toStringAsFixed(0)}'),
        if (_delivery == 'home_delivery')
          _row('Delivery fee', (q != null && q.deliveryCharge == 0) ? 'FREE' : '₹${(q?.deliveryCharge ?? 0).toStringAsFixed(0)}'),
        if ((q?.packagingCharge ?? 0) > 0) _row('Packaging charges', '₹${q!.packagingCharge.toStringAsFixed(0)}'),
        if ((q?.platformFee ?? 0) > 0) _row('Platform fee', '₹${q!.platformFee.toStringAsFixed(0)}'),
        if ((q?.discount ?? 0) > 0) _row('Coupon discount', '− ₹${q!.discount.toStringAsFixed(0)}'),
        if (q != null && q.freeDeliveryRemaining > 0 && _delivery == 'home_delivery')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Add ₹${q.freeDeliveryRemaining.toStringAsFixed(0)} more for FREE delivery',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        const SizedBox(height: 6),
        _row('Total', _quoting ? '…' : '₹${(q?.total ?? cart.subtotal).toStringAsFixed(0)}', bold: true),
      ],
    );
  }

  Widget _couponField() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Discount coupon',
                prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
                errorText: _couponError,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Bounded width: the global button theme is full-width (Size.fromHeight),
          // which forces infinite width for an inflexible child inside a Row.
          _appliedCoupon == null
              ? OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(84, 48)),
                  onPressed: () {
                    final code = _coupon.text.trim();
                    if (code.isEmpty) return;
                    setState(() {
                      _appliedCoupon = code;
                      _couponError = null;
                      _sig = ''; // force re-quote
                    });
                    _refreshQuote(ref.read(cartProvider));
                  },
                  child: const Text('Apply'),
                )
              : TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(84, 48)),
                  onPressed: () {
                    setState(() {
                      _appliedCoupon = null;
                      _coupon.clear();
                      _couponError = null;
                      _sig = '';
                    });
                    _refreshQuote(ref.read(cartProvider));
                  },
                  child: const Text('Remove'),
                ),
        ],
      );

  Widget _slotPicker(AsyncValue<List<OpenSlot>> slotsAsync) => slotsAsync.when(
        loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
        error: (_, _) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Could not load time slots', style: TextStyle(color: AppColors.textMuted))),
        data: (slots) {
          if (slots.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('This provider hasn’t published time slots — your order will be scheduled after they confirm.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            );
          }
          final byDay = <String, List<OpenSlot>>{};
          for (final s in slots) {
            byDay.putIfAbsent(s.dayLabel, () => []).add(s);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: byDay.entries.map((e) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: e.value.map((s) {
                      final on = _selectedSlot?.date == s.date && _selectedSlot?.startTime == s.startTime;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSlot = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: on ? AppColors.primarySurface : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: on ? AppColors.primary : AppColors.border),
                          ),
                          child: Text(s.timeLabel,
                              style: TextStyle(
                                  color: on ? AppColors.primary : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            }).toList(),
          );
        },
      );

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
        onTap: () {
          setState(() => _delivery = value);
          _refreshQuote(ref.read(cartProvider));
        },
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
