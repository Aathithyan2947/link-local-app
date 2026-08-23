import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../feed/data/post_models.dart' show relativeTime;
import 'order_tracking_screen.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

const _terminalStatuses = {'completed', 'cancelled', 'rejected'};

/// One payment entry, tagged with which side of the transaction the current member was on.
class _PaymentRow {
  const _PaymentRow({required this.order, required this.payment, required this.outgoing});
  final OrderModel order;
  final OrderPaymentModel payment;
  final bool outgoing; // true: I paid the SP · false: I (as SP) received this

  DateTime get at => payment.paidAt ?? payment.createdAt ?? DateTime(0);
}

String _methodLabel(OrderPaymentModel p) {
  const names = {'upi': 'UPI', 'card': 'Card', 'net_banking': 'Net Banking', 'cash': 'Cash', 'bank_transfer': 'Bank Transfer'};
  final base = names[p.paymentMethod] ?? p.paymentMethod.toUpperCase();
  return p.paymentSubMethod != null && p.paymentSubMethod!.isNotEmpty ? '$base - ${p.paymentSubMethod}' : base;
}

/// Unified transaction history — payments made (as a buyer) and, for SPs, payments
/// received — flattened from the same order data already shown in "Orders / Bookings" and
/// "My Shop → Bookings".
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSp = ref.watch(authControllerProvider).user?.isServiceProvider ?? false;
    final myOrders = ref.watch(myOrdersProvider);
    final incoming = isSp ? ref.watch(incomingOrdersProvider) : const AsyncValue<List<OrderModel>>.data([]);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Transactions'),
      ),
      body: myOrders.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: OutlinedButton(onPressed: () => ref.invalidate(myOrdersProvider), child: const Text('Retry')),
        ),
        data: (mine) => incoming.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
            child: OutlinedButton(onPressed: () => ref.invalidate(incomingOrdersProvider), child: const Text('Retry')),
          ),
          data: (received) {
            final rows = <_PaymentRow>[
              for (final o in mine)
                for (final p in o.payments) _PaymentRow(order: o, payment: p, outgoing: true),
              for (final o in received)
                for (final p in o.payments) _PaymentRow(order: o, payment: p, outgoing: false),
            ]..sort((a, b) => b.at.compareTo(a.at));

            final now = DateTime.now();
            double receivedThisMonth = 0, sentThisMonth = 0;
            for (final r in rows) {
              if (r.payment.paymentStatus != 'paid') continue;
              final at = r.at;
              if (at.year != now.year || at.month != now.month) continue;
              if (r.outgoing) {
                sentThisMonth += r.payment.amount;
              } else {
                receivedThisMonth += r.payment.amount;
              }
            }

            final pending = mine.where((o) => !o.paid && !_terminalStatuses.contains(o.status)).toList();

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => Future.wait([
                ref.refresh(myOrdersProvider.future),
                if (isSp) ref.refresh(incomingOrdersProvider.future),
              ]),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.south_west_rounded,
                          iconColor: AppColors.success,
                          label: 'Money Received',
                          amount: receivedThisMonth,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.north_east_rounded,
                          iconColor: AppColors.error,
                          label: 'Money Sent',
                          amount: sentThisMonth,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text('Transactions History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                  const SizedBox(height: 12),
                  if (rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No transactions yet.')),
                  for (final r in rows) ...[_PaymentTile(row: r), const SizedBox(height: 10)],
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Pending Payments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                    const SizedBox(height: 12),
                    for (final o in pending) ...[_PendingTile(order: o), const SizedBox(height: 10)],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.iconColor, required this.label, required this.amount});
  final IconData icon;
  final Color iconColor;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text('₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'paid' => ('Success', AppColors.success),
      'failed' => ('Failed', AppColors.error),
      'refunded' => ('Refunded', AppColors.warning),
      _ => (status, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.row});
  final _PaymentRow row;

  @override
  Widget build(BuildContext context) {
    final o = row.order;
    final p = row.payment;
    final failed = p.paymentStatus == 'failed';
    final title = row.outgoing ? 'Paid to ${o.spName}' : 'Received from ${o.buyerName}';
    final date = row.at.year > 1 ? DateFormat('EEE, MMM d · h:mm a').format(row.at) : '';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: failed ? AppColors.error.withValues(alpha: 0.12) : AppColors.primarySurface,
                    child: Icon(
                      failed ? Icons.close_rounded : (row.outgoing ? Icons.north_east_rounded : Icons.south_west_rounded),
                      color: failed ? AppColors.error : AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(date, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text('₹${p.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: failed ? AppColors.textMuted : (row.outgoing ? AppColors.ink : AppColors.success),
                      )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatusPill(status: p.paymentStatus),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(6)),
                    child: Text(_methodLabel(p), style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                  ),
                ],
              ),
              if (failed) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Payment failed. Tap to try again.', style: TextStyle(fontSize: 12, color: AppColors.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final slot = order.slot;
    final dateLabel = slot != null ? 'Due before ${slot.date}' : 'Placed ${relativeTime(order.placedAt)}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: AppColors.field, shape: BoxShape.circle),
                child: const Icon(Icons.hourglass_bottom_rounded, color: AppColors.warning, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pay ${order.spName}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(dateLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('₹${order.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
