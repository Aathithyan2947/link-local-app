import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/orders_repository.dart';
import 'my_orders_screen.dart';
import 'order_tracking_screen.dart';

const _historyStatuses = {'completed', 'cancelled', 'rejected'};

/// The SP's own completed/cancelled/declined orders — everything
/// [IncomingOrdersScreen] deliberately leaves out once it's no longer active.
class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomingOrdersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Order History'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(incomingOrdersProvider), child: const Text('Retry'))),
        data: (orders) {
          final history = orders.where((o) => _historyStatuses.contains(o.status)).toList();
          if (history.isEmpty) return const Center(child: Text('No past orders yet.'));
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(incomingOrdersProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => OrderCard(
                order: history[i],
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: history[i].id))),
              ),
            ),
          );
        },
      ),
    );
  }
}
