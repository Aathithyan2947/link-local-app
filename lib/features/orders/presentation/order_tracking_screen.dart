import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../payments/presentation/payment_method_screen.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

/// Order/booking status timeline — the "Accepted (Buyer)" frame.
/// Opened by the buyer from their orders list; an accepted booking can be confirmed & paid here.
class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({super.key, required this.orderId});
  final int orderId;

  Future<void> _confirmAndPay(BuildContext context, WidgetRef ref, OrderModel o) async {
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PaymentMethodScreen(orderId: o.id, total: o.totalAmount)),
    );
    if (paid == true) {
      ref.invalidate(orderByIdProvider(orderId));
      ref.invalidate(myOrdersProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderByIdProvider(orderId));
    final o = async.asData?.value;
    final canPay = o != null && o.isBooking && o.status == 'accepted' && !o.paid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Order #$orderId')),
      bottomNavigationBar: !canPay
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => _confirmAndPay(context, ref, o),
                  child: Text('Confirm & pay  ·  ₹${o.totalAmount.toStringAsFixed(0)}'),
                ),
              ),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(orderByIdProvider(orderId)), child: const Text('Retry'))),
        data: (o) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _header(o),
            const SizedBox(height: 22),
            _timeline(o),
          ],
        ),
      ),
    );
  }

  Widget _header(OrderModel o) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(o.spName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
                Text('₹${o.totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(o.isBooking ? '${o.rateTypeLabel ?? 'Session'} booking' : '${o.items.length} item(s)',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            if (o.slot != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.event_outlined, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('${o.slot!.date} · ${o.slot!.startTime}–${o.slot!.endTime}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ]),
            ],
            if (o.paid) ...[
              const SizedBox(height: 8),
              Row(children: const [
                Icon(Icons.verified, size: 16, color: AppColors.primary),
                SizedBox(width: 4),
                Text('Paid', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ]),
            ],
          ],
        ),
      );

  Widget _timeline(OrderModel o) {
    // Steps per flow; the current status determines how far the progress has reached.
    final steps = o.isBooking
        ? const [
            ('requested', 'Requested', 'Booking request sent'),
            ('accepted', 'Accepted', 'Provider accepted your request'),
            ('confirmed', 'Confirmed', 'Payment done — booking confirmed'),
            ('completed', 'Completed', 'Session completed'),
          ]
        : const [
            ('placed', 'Order Placed', 'Your order has been placed'),
            ('confirmed', 'Accepted by seller', 'Seller confirmed your order'),
            ('in_progress', 'Being prepared', 'Your order is being prepared'),
            ('delivered', 'Out for delivery', 'On the way to you'),
            ('completed', 'Delivered', 'Order delivered'),
          ];
    final order = steps.map((s) => s.$1).toList();
    final rejected = o.status == 'rejected' || o.status == 'cancelled';
    final currentIdx = order.indexOf(o.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rejected)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.cancel, color: AppColors.error),
              const SizedBox(width: 10),
              Text(o.status == 'rejected' ? 'This request was declined' : 'This order was cancelled',
                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ]),
          ),
        ...List.generate(steps.length, (i) {
          final done = !rejected && currentIdx >= i && currentIdx >= 0;
          final isLast = i == steps.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: done ? AppColors.primary : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: done ? AppColors.primary : AppColors.border, width: 2),
                      ),
                      child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                    ),
                    if (!isLast)
                      Expanded(child: Container(width: 2, color: done ? AppColors.primary : AppColors.border)),
                  ],
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(steps[i].$2, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: done ? AppColors.ink : AppColors.textMuted)),
                      const SizedBox(height: 2),
                      Text(steps[i].$3, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
