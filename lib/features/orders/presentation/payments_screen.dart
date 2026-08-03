import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import 'order_tracking_screen.dart';
import '../data/order_models.dart';
import '../data/orders_repository.dart';

/// One payment entry, tagged with which side of the transaction the current member was on.
class _PaymentRow {
  const _PaymentRow({required this.order, required this.payment, required this.outgoing});
  final OrderModel order;
  final OrderPaymentModel payment;
  final bool outgoing; // true: I paid the SP · false: I (as SP) received this
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
      appBar: AppBar(title: const Text('Payments')),
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
                for (final p in o.payments)
                  if (p.paymentStatus == 'paid') _PaymentRow(order: o, payment: p, outgoing: true),
              for (final o in received)
                for (final p in o.payments)
                  if (p.paymentStatus == 'paid') _PaymentRow(order: o, payment: p, outgoing: false),
            ]..sort((a, b) => (b.payment.paidAt ?? DateTime(0)).compareTo(a.payment.paidAt ?? DateTime(0)));

            if (rows.isEmpty) return const Center(child: Text('No payments yet.'));
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(myOrdersProvider);
                if (isSp) ref.invalidate(incomingOrdersProvider);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PaymentTile(row: rows[i]),
              ),
            );
          },
        ),
      ),
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
    final title = row.outgoing ? 'Paid to ${o.spName}' : 'Received from ${o.buyerName}';
    final date = p.paidAt != null ? DateFormat('EEE, MMM d · h:mm a').format(p.paidAt!) : '';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: o.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primarySurface,
                child: Icon(
                  row.outgoing ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: AppColors.primary,
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
                    Text('$date · ${p.paymentMethod.toUpperCase()}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('₹${p.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: row.outgoing ? AppColors.ink : AppColors.success,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
