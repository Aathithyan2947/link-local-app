import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

/// The buyer's orders — status, items and totals.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOrdersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Orders')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(myOrdersProvider), child: const Text('Retry'))),
        data: (orders) {
          if (orders.isEmpty) return const Center(child: Text('No orders yet.'));
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(myOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => OrderCard(order: orders[i], showSeller: true),
            ),
          );
        },
      ),
    );
  }
}

/// Shared order card used by buyer + SP order lists.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.showSeller = false, this.trailing});
  final OrderModel order;
  final bool showSeller;
  final Widget? trailing;

  static Color statusColor(String s) => switch (s) {
        'placed' => AppColors.warning,
        'cancelled' => AppColors.error,
        'completed' || 'delivered' => AppColors.primary,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final who = showSeller ? order.spName : order.buyerName;
    final photo = showSeller ? order.spPhoto : order.buyerPhoto;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Order #${order.id}',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: statusColor(order.status).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(order.statusLabel, style: TextStyle(color: statusColor(order.status), fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Avatar(name: who, photoUrl: photo, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(who, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (order.placedAt != null)
                      Text(DateFormat('MMM d, h:mm a').format(order.placedAt!),
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Text('₹${order.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          ...order.items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(it.productName, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary))),
                    Text('x${it.quantity.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
                  ],
                ),
              )),
          Row(
            children: [
              Icon(order.isHomeDelivery ? Icons.delivery_dining : Icons.storefront,
                  size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(order.isHomeDelivery ? 'Home delivery' : 'Pickup',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              if (order.paid) ...[
                const SizedBox(width: 12),
                const Icon(Icons.verified, size: 15, color: AppColors.primary),
                const SizedBox(width: 4),
                const Text('Paid', style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
              ],
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 12), trailing!],
        ],
      ),
    );
  }
}
