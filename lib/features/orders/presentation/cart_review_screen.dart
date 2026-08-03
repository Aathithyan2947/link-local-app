import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../business/data/product_models.dart';
import '../../discovery/data/sp_detail_models.dart';
import '../../discovery/discovery_repository.dart';
import '../../payments/presentation/payment_method_screen.dart';
import '../data/cart.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';
import 'order_success_screen.dart';
import 'product_details_screen.dart';

/// Reviews the cart and places the order — the "Cart Review" frame.
class CartReviewScreen extends ConsumerStatefulWidget {
  const CartReviewScreen({super.key});

  @override
  ConsumerState<CartReviewScreen> createState() => _CartReviewScreenState();
}

class _CartReviewScreenState extends ConsumerState<CartReviewScreen> {
  String _delivery = 'home_delivery';
  String? _selectedWindow;
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

  Future<void> _confirm(Cart cart) async {
    if (_selectedWindow == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please choose a delivery time')));
      return;
    }
    setState(() => _placing = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final order = await repo.placeOrder({
        'spProfileId': cart.spProfileId,
        'items': cart.items
            .map((l) => {
                  'productId': l.product.id,
                  'quantity': l.qty,
                  if ((l.customizationSelection ?? l.product.customizationNotes)?.isNotEmpty == true)
                    'customizationNotes': l.customizationSelection ?? l.product.customizationNotes,
                })
            .toList(),
        'deliveryType': _delivery,
        if (_appliedCoupon != null) 'couponCode': _appliedCoupon,
        'deliveryTimeWindow': _selectedWindow,
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not place order')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  /// Fixed delivery windows for the earliest orderable day, derived from the SP's
  /// admin-configured "Order placement timing" delivery setting — no SP-side setup needed.
  static const _windowTimes = ['10:00 AM – 12:00 PM', '1:00 PM – 3:00 PM', '4:00 PM – 6:00 PM'];

  List<String> _deliveryWindows(String? timing) {
    final now = DateTime.now();
    final tomorrow = timing == null
        ? false
        : timing.toLowerCase().contains('12 hours')
            ? now.hour >= 12
            : true;
    final dayLabel = tomorrow ? 'Tomorrow' : 'Today';
    return _windowTimes.map((t) => '$dayLabel, $t').toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final spAsync = cart.isEmpty ? null : ref.watch(serviceProviderDetailProvider(cart.spProfileId!));
    final sp = spAsync?.asData?.value;
    final total = _quote?.total ?? cart.subtotal;

    // Re-price when the cart changes (qty edits, item removal) — outside of build.
    ref.listen<Cart>(cartProvider, (_, next) => _refreshQuote(next));

    final timing = sp == null ? null : _orderTimingValue(sp);
    final windows = _deliveryWindows(timing);
    final crossSell = sp == null ? const <SpProduct>[] : sp.products.where((p) => !cart.lines.containsKey(p.id)).toList();

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
                if (crossSell.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Products you can buy from this seller', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  _crossSell(crossSell, cart, notifier),
                ],
                const SizedBox(height: 20),
                const Text('Choose delivery time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const Text('All orders are made fresh. Earliest delivery time is shown below.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                _windowPicker(windows),
              ],
            ),
    );
  }

  String? _orderTimingValue(ServiceProviderDetail sp) {
    for (final f in sp.customFields) {
      if (f.category == 'delivery' && f.fieldName.trim().toLowerCase() == 'order placement timing') {
        final v = f.value?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  Widget _windowPicker(List<String> windows) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: windows.map((w) {
          final on = _selectedWindow == w;
          return GestureDetector(
            onTap: () => setState(() => _selectedWindow = w),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: on ? AppColors.primarySurface : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? AppColors.primary : AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 16, color: on ? AppColors.primary : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text(w,
                      style: TextStyle(
                          color: on ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          );
        }).toList(),
      );

  Widget _crossSell(List<SpProduct> products, Cart cart, CartNotifier notifier) => SizedBox(
        height: 136,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = products[i];
            final hasCustomization = p.customizationNotes?.trim().isNotEmpty == true;
            return Container(
              width: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                            ? CachedNetworkImage(imageUrl: AppConfig.assetUrl(p.photoUrl!), width: 104, height: 70, fit: BoxFit.cover, errorWidget: (_, _, _) => _ph())
                            : _ph(),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Material(
                          color: AppColors.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => hasCustomization
                                ? Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => ProductDetailsScreen(product: p, spId: cart.spProfileId!, spName: cart.spName ?? ''),
                                  ))
                                : notifier.add(cart.spProfileId!, cart.spName ?? '', p),
                            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, color: Colors.white, size: 16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  if (p.price != null) Text('₹${p.price!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            );
          },
        ),
      );

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
