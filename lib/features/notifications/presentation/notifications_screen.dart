import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/presentation/order_tracking_screen.dart';
import '../data/notification_models.dart';
import '../data/notifications_repository.dart';

/// The notifications inbox — the "Tutor/Student Notifcation" frames.
/// Booking requests (to an SP) are actionable inline (Accept/Reject).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadCountProvider);
  }

  Future<void> _accept(BuildContext context, WidgetRef ref, int orderId) async {
    try {
      await ref.read(ordersRepositoryProvider).accept(orderId);
      ref.invalidate(incomingOrdersProvider);
      await _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order accepted')));
      }
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException ? ApiException.fromDio(e).message : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, int orderId) async {
    try {
      await ref.read(ordersRepositoryProvider).reject(orderId);
      ref.invalidate(incomingOrdersProvider);
      await _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order rejected')));
      }
    } catch (e) {
      if (!context.mounted) return;
      final message = e is DioException ? ApiException.fromDio(e).message : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markAllRead();
              await _refresh(ref);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, _) => Center(child: OutlinedButton(onPressed: () => _refresh(ref), child: const Text('Retry'))),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet.', style: TextStyle(color: AppColors.textSecondary)));
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _refresh(ref),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NotifCard(
                n: items[i],
                onTap: () async {
                  if (!items[i].isRead) {
                    await ref.read(notificationsRepositoryProvider).markRead(items[i].id);
                    await _refresh(ref);
                  }
                  final id = items[i].entityId;
                  if (context.mounted && items[i].entityType == 'order' && id != null) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: id)));
                  }
                },
                onAccept: () => _accept(context, ref, items[i].entityId!),
                onReject: () => _reject(context, ref, items[i].entityId!),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.n, required this.onTap, required this.onAccept, required this.onReject});
  final AppNotification n;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  IconData get _icon => switch (n.type) {
        'enquiry' => Icons.event_note_outlined,
        'payment' => Icons.payments_outlined,
        'message' => Icons.chat_bubble_outline,
        _ => Icons.notifications_none,
      };

  @override
  Widget build(BuildContext context) {
    final actionable = n.isBookingRequest && n.entityId != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: n.isRead ? AppColors.surface : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: n.isRead ? AppColors.border : AppColors.primaryTint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon, color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      if (n.body != null) ...[
                        const SizedBox(height: 2),
                        Text(n.body!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                      if (n.createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(DateFormat('MMM d, h:mm a').format(n.createdAt!),
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ],
                  ),
                ),
                if (!n.isRead)
                  Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ],
            ),
            if (actionable) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error), minimumSize: const Size.fromHeight(42)),
                    child: const Text('Reject'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
