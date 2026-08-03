import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/data/orders_repository.dart';
import 'payment_failed_screen.dart';
import 'payment_success_screen.dart';
import 'payment_upi_screen.dart';

/// Payment method selection — the "Payment - 1" frame. MOCK gateway: no real charge.
class PaymentMethodScreen extends ConsumerStatefulWidget {
  const PaymentMethodScreen({super.key, required this.orderId, required this.total});
  final int orderId;
  final double total;

  @override
  ConsumerState<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen> {
  String _method = 'upi';
  bool _paying = false;

  static const _methods = [
    ('upi', 'UPI', 'Pay using any UPI app', Icons.account_balance_wallet_outlined),
    ('card', 'Credit/Debit Card', 'Visa, Master Card, RuPay', Icons.credit_card),
    ('net_banking', 'Net Banking', 'All major banks supported', Icons.account_balance_outlined),
  ];

  Future<void> _next() async {
    if (_method == 'upi') {
      Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: kPaymentFlowRoute),
        builder: (_) => PaymentUpiScreen(orderId: widget.orderId, total: widget.total),
      ));
      return;
    }
    // Card / net-banking → mock charge directly.
    setState(() => _paying = true);
    try {
      await ref.read(ordersRepositoryProvider).pay(widget.orderId, paymentMethod: _method);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: kPaymentFlowRoute),
          builder: (_) => PaymentSuccessScreen(amount: widget.total),
        ));
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          settings: const RouteSettings(name: kPaymentFlowRoute),
          builder: (_) => PaymentFailedScreen(orderId: widget.orderId, amount: widget.total, paymentMethod: _method),
        ));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Payment Method')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _paying ? null : _next,
            child: _paying
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Next'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Payment', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('₹ ${widget.total.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Choose a Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          ..._methods.map((m) {
            final on = _method == m.$1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _method = m.$1),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: on ? AppColors.primarySurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? AppColors.primary : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(m.$4, color: AppColors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(m.$3, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: on ? AppColors.primary : AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
