import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/order_models.dart';

/// Where an order's payment stands (BUG-097), for the buyer and the seller alike: "Paid",
/// "Advance ₹500 paid · ₹500 due", or "To be paid later · ₹1,000". Nothing for an order that
/// hasn't been paid and isn't due later, or one that was cancelled or declined unpaid.
class OrderPaymentStatus extends StatelessWidget {
  const OrderPaymentStatus({super.key, required this.order, this.fontSize = 12.5});
  final OrderModel order;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final closed = order.status == 'cancelled' || order.status == 'rejected';
    final (IconData icon, String text, Color color)? line = order.fullyPaid
        ? (Icons.verified, 'Paid', AppColors.primary)
        : order.hasBalance && !closed
            ? (
                Icons.timelapse_rounded,
                'Advance ${inr(order.amountPaid)} paid · ${inr(order.balanceDue)} due',
                AppColors.warning,
              )
            : !order.paid && order.payLater && !closed
                ? (Icons.schedule_rounded, 'To be paid later · ${inr(order.balanceDue)}', AppColors.textSecondary)
                : null;
    if (line == null) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(line.$1, size: fontSize + 2.5, color: line.$3),
        const SizedBox(width: 4),
        Flexible(
          child: Text(line.$2,
              style: TextStyle(fontSize: fontSize, color: line.$3, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
