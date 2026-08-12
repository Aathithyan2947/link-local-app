import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import 'my_orders_screen.dart';

/// Confirmation after a successful (mock-paid) order.
///
/// Continues to the seller's profile — where the order was started — rather than leaving the
/// resident on a dead-end screen. [spProfileId] is captured before the cart is cleared.
class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.total,
    this.spProfileId,
    this.spName,
  });
  final int orderId;
  final double total;
  final int? spProfileId;
  final String? spName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 88),
              const SizedBox(height: 20),
              const Text('Order placed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text('Order #$orderId · ₹${total.toStringAsFixed(0)} paid.\nThe seller will confirm shortly.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 32),
              if (spProfileId != null)
                ElevatedButton(
                  // Clears the cart/payment screens behind us, so Back can't return into a
                  // cart that has already been paid for.
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => ServiceProviderDetailScreen(id: spProfileId!)),
                    (r) => r.isFirst,
                  ),
                  child: Text(spName == null ? 'Back to seller' : 'Back to $spName'),
                )
              else
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                  ),
                  child: const Text('View my orders'),
                ),
              const SizedBox(height: 12),
              if (spProfileId != null)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                  ),
                  child: const Text('View my orders'),
                )
              else
                OutlinedButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Back to home'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
