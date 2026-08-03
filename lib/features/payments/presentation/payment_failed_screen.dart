import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/data/orders_repository.dart';
import 'payment_success_screen.dart';

/// The "Failed" frame — matches the Figma copy exactly ("Payment Failed" / "Your payment has
/// failed to transfer" / "Retry Payment"). Retry re-attempts the same charge in place, per
/// Figma, rather than navigating back to method selection.
class PaymentFailedScreen extends ConsumerStatefulWidget {
  const PaymentFailedScreen({super.key, required this.orderId, required this.amount, this.paymentMethod = 'upi'});
  final int orderId;
  final double amount;
  final String paymentMethod;

  @override
  ConsumerState<PaymentFailedScreen> createState() => _PaymentFailedScreenState();
}

class _PaymentFailedScreenState extends ConsumerState<PaymentFailedScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(ordersRepositoryProvider).pay(widget.orderId, paymentMethod: widget.paymentMethod);
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          settings: const RouteSettings(name: kPaymentFlowRoute),
          builder: (_) => PaymentSuccessScreen(amount: widget.amount),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Still couldn't complete the payment.")));
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel, color: AppColors.error, size: 96),
              const SizedBox(height: 24),
              const Text('Payment Failed',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Your payment has failed to transfer',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Text('₹${widget.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: AppColors.ink)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _retrying ? null : _retry,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _retrying
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Retry Payment'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.settings.name != kPaymentFlowRoute),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
