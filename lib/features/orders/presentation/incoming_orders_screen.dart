import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';
import 'my_orders_screen.dart';

/// Orders received by the SP — the "Incoming Orders" frame. Accept/Reject then
/// progress the order through fulfilment.
class IncomingOrdersScreen extends ConsumerWidget {
  const IncomingOrdersScreen({super.key});

  Future<void> _act(WidgetRef ref, int id, String status) async {
    await ref.read(ordersRepositoryProvider).updateStatus(id, status);
    ref.invalidate(incomingOrdersProvider);
  }

  Future<void> _accept(WidgetRef ref, int id) async {
    await ref.read(ordersRepositoryProvider).accept(id);
    ref.invalidate(incomingOrdersProvider);
  }

  Future<void> _reject(WidgetRef ref, int id) async {
    await ref.read(ordersRepositoryProvider).reject(id);
    ref.invalidate(incomingOrdersProvider);
  }

  Widget? _actions(WidgetRef ref, OrderModel o) {
    // Booking flow: requested → accept/reject; the buyer then pays to confirm.
    if (o.isBooking) {
      switch (o.status) {
        case 'requested':
          return Row(children: [
            Expanded(child: _btn('Accept', AppColors.primary, () => _accept(ref, o.id), filled: true)),
            const SizedBox(width: 12),
            Expanded(child: _btn('Reject', AppColors.error, () => _reject(ref, o.id))),
          ]);
        case 'accepted':
          return _btn('Awaiting payment', AppColors.textMuted, () {}, full: true);
        case 'confirmed':
          return _btn('Mark completed', AppColors.primary, () => _act(ref, o.id, 'completed'), filled: true, full: true);
        default:
          return null;
      }
    }
    // Product flow: placed → accept/reject → prepare → deliver → complete.
    switch (o.status) {
      case 'placed':
        return Row(children: [
          Expanded(child: _btn('Accept', AppColors.primary, () => _accept(ref, o.id), filled: true)),
          const SizedBox(width: 12),
          Expanded(child: _btn('Reject', AppColors.error, () => _reject(ref, o.id))),
        ]);
      case 'confirmed':
        return _btn('Start preparing', AppColors.primary, () => _act(ref, o.id, 'in_progress'), filled: true, full: true);
      case 'in_progress':
        return _btn('Mark delivered', AppColors.primary, () => _act(ref, o.id, 'delivered'), filled: true, full: true);
      case 'delivered':
        return _btn('Mark completed', AppColors.primary, () => _act(ref, o.id, 'completed'), filled: true, full: true);
      default:
        return null;
    }
  }

  Widget _btn(String label, Color color, VoidCallback onTap, {bool filled = false, bool full = false}) {
    final child = filled
        ? ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(44)),
            child: Text(label))
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), minimumSize: const Size.fromHeight(44)),
            child: Text(label));
    return full ? SizedBox(width: double.infinity, child: child) : child;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomingOrdersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Incoming Orders')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(incomingOrdersProvider), child: const Text('Retry'))),
        data: (orders) {
          if (orders.isEmpty) return const Center(child: Text('No orders yet.'));
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(incomingOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => OrderCard(order: orders[i], trailing: _actions(ref, orders[i])),
            ),
          );
        },
      ),
    );
  }
}
