import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../messages/presentation/chat_screen.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

const _needsActionStatuses = {'placed', 'requested'};
const _ongoingStatuses = {'accepted', 'confirmed', 'in_progress', 'delivered'};

const _ongoingStatusLabels = <String, String>{
  'in_progress': 'In Preparation',
};

String _orderRef(int id) => '#K${id.toString().padLeft(6, '0')}';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} Mins Ago';
  if (diff.inHours < 24) return '${diff.inHours} ${diff.inHours == 1 ? 'Hour' : 'Hours'} Ago';
  return '${diff.inDays} ${diff.inDays == 1 ? 'Day' : 'Days'} Ago';
}

/// Orders received by the SP — grouped into what needs a decision now
/// ("New Coming Orders") and what's already accepted and in flight
/// ("Ongoing Orders"). Accept/Reject/progress actions unchanged underneath.
class IncomingOrdersScreen extends ConsumerWidget {
  const IncomingOrdersScreen({super.key});

  Future<void> _runAction(BuildContext context, WidgetRef ref, String successMessage, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(incomingOrdersProvider);
      await ref.read(incomingOrdersProvider.future);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException ? ApiException.fromDio(e).message : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _act(BuildContext context, WidgetRef ref, int id, String status, String label) => _runAction(
        context,
        ref,
        label,
        () => ref.read(ordersRepositoryProvider).updateStatus(id, status),
      );

  Future<void> _accept(BuildContext context, WidgetRef ref, int id) => _runAction(
        context,
        ref,
        'Order accepted',
        () => ref.read(ordersRepositoryProvider).accept(id),
      );

  Future<void> _reject(BuildContext context, WidgetRef ref, int id) => _runAction(
        context,
        ref,
        'Order rejected',
        () => ref.read(ordersRepositoryProvider).reject(id),
      );

  /// The progress action shown on an ongoing order's row, if any.
  Widget? _ongoingAction(BuildContext context, WidgetRef ref, OrderModel o) {
    if (o.isBooking) {
      return o.status == 'confirmed'
          ? TextButton(
              onPressed: () => _act(context, ref, o.id, 'completed', 'Marked as completed'),
              child: const Text('Mark completed'))
          : null;
    }
    return switch (o.status) {
      'confirmed' => TextButton(
          onPressed: () => _act(context, ref, o.id, 'in_progress', 'Marked as in preparation'),
          child: const Text('Start preparing')),
      'in_progress' => TextButton(
          onPressed: () => _act(context, ref, o.id, 'delivered', 'Marked as delivered'),
          child: const Text('Mark delivered')),
      'delivered' => TextButton(
          onPressed: () => _act(context, ref, o.id, 'completed', 'Marked as completed'),
          child: const Text('Mark completed')),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incomingOrdersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Your Orders & Bookings'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: OutlinedButton(onPressed: () => ref.invalidate(incomingOrdersProvider), child: const Text('Retry'))),
        data: (orders) {
          final needsAction = orders.where((o) => _needsActionStatuses.contains(o.status)).toList();
          final ongoing = orders.where((o) => _ongoingStatuses.contains(o.status)).toList();
          if (needsAction.isEmpty && ongoing.isEmpty) return const Center(child: Text('No orders yet.'));
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.refresh(incomingOrdersProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (needsAction.isNotEmpty) ...[
                  const _SectionTitle('New Coming Orders'),
                  const SizedBox(height: 10),
                  for (final o in needsAction) ...[
                    _NewOrderCard(
                      order: o,
                      onAccept: () => _accept(context, ref, o.id),
                      onReject: () => _reject(context, ref, o.id),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
                if (ongoing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const _SectionTitle('Ongoing Orders'),
                  const SizedBox(height: 10),
                  for (final o in ongoing) ...[
                    _OngoingOrderRow(order: o, action: _ongoingAction(context, ref, o)),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink));
}

class _NewOrderCard extends StatelessWidget {
  const _NewOrderCard({required this.order, required this.onAccept, required this.onReject});
  final OrderModel order;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: order.buyerName, photoUrl: order.buyerPhoto, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.buyerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                    if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(order.deliveryAddress!,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${order.totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  const SizedBox(height: 4),
                  if (order.items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20)),
                      child: Text('${order.items.length} Items', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order ID: ${_orderRef(order.id)}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if (order.placedAt != null)
                      Text('Order Placed: ${_timeAgo(order.placedAt!)}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    if (order.deliveryTimeWindow != null && order.deliveryTimeWindow!.isNotEmpty)
                      Text('Expected Delivery: ${order.deliveryTimeWindow}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (order.buyerId != null)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(otherUserId: order.buyerId!, otherName: order.buyerName, otherPhoto: order.buyerPhoto),
                  )),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.chat_bubble_rounded, color: AppColors.primary, size: 22),
                  ),
                ),
            ],
          ),
          if (firstItem != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, style: BorderStyle.solid))),
                child: SizedBox(height: 1),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: firstItem.productPhoto != null
                      ? CachedNetworkImage(
                          imageUrl: AppConfig.assetUrl(firstItem.productPhoto!),
                          width: 52, height: 52, fit: BoxFit.cover)
                      : Container(width: 52, height: 52, color: AppColors.field,
                          child: const Icon(Icons.fastfood_outlined, color: AppColors.textMuted)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in order.items) ...[
                        Text(
                          item.quantity > 1
                              ? '${item.productName} × ${item.quantity.toStringAsFixed(0)}'
                              : item.productName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        if (item.customizationNotes != null && item.customizationNotes!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.customizationNotes!,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ],
                        if (item != order.items.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(44)),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error), minimumSize: const Size.fromHeight(44)),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OngoingOrderRow extends StatelessWidget {
  const _OngoingOrderRow({required this.order, this.action});
  final OrderModel order;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final photo = order.items.isNotEmpty ? order.items.first.productPhoto : null;
    final statusLabel = _ongoingStatusLabels[order.status] ?? order.statusLabel;
    final timing = (order.deliveryTimeWindow != null && order.deliveryTimeWindow!.isNotEmpty)
        ? order.deliveryTimeWindow!
        : (order.placedAt != null ? DateFormat('MMM d, h:mm a').format(order.placedAt!) : '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: photo != null
                    ? CachedNetworkImage(imageUrl: AppConfig.assetUrl(photo), width: 44, height: 44, fit: BoxFit.cover)
                    : Container(width: 44, height: 44, color: AppColors.field, child: const Icon(Icons.fastfood_outlined, size: 20, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.buyerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('Order ID: ${_orderRef(order.id)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    if (timing.isNotEmpty) Text(timing, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (order.items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20)),
                      child: Text('${order.items.length} Items', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                    child: Text(statusLabel, style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }
}
