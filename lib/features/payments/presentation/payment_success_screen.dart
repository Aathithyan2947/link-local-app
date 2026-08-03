import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Route name tag shared by every screen in the payment flow (amount entry through
/// success/failure) so "Done"/"Cancel" can pop back to the SP profile in one call,
/// regardless of which path was taken (UPI adds an extra screen; card/net-banking doesn't).
const kPaymentFlowRoute = '/payment-flow';

/// The "Success" frame — shown after a payment actually completes. Matches the Figma copy
/// exactly ("Payment Successful!" / "Your payment has been completed successfully").
class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({super.key, required this.amount});
  final double amount;

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
              const Icon(Icons.check_circle, color: AppColors.success, size: 96),
              const SizedBox(height: 24),
              const Text('Payment Successful!',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Your payment has been completed successfully',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Text('₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: AppColors.ink)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.settings.name != kPaymentFlowRoute),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
