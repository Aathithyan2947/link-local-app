import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/data/orders_repository.dart';
import 'payment_failed_screen.dart';
import 'payment_success_screen.dart';

/// UPI payment detail — the "Payment - 2" frame. MOCK: any app/QR tap "pays".
class PaymentUpiScreen extends ConsumerStatefulWidget {
  const PaymentUpiScreen({super.key, required this.orderId, required this.total});
  final int orderId;
  final double total;

  @override
  ConsumerState<PaymentUpiScreen> createState() => _PaymentUpiScreenState();
}

class _PaymentUpiScreenState extends ConsumerState<PaymentUpiScreen> {
  static const _upiId = 'linklocal@okaxis';
  bool _paying = false;

  static const _apps = ['GPay', 'PhonePe', 'PayTM', 'BHIM UPI', 'Others'];

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      await ref.read(ordersRepositoryProvider).pay(widget.orderId, paymentMethod: 'upi');
      if (!mounted) return;
      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PaymentSuccessScreen(amount: widget.total)),
      );
      if (mounted) Navigator.of(context).pop(done ?? true);
    } catch (_) {
      if (!mounted) return;
      // The failed screen can still end in success via Retry, so forward whatever it reports.
      final retried = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => PaymentFailedScreen(orderId: widget.orderId, amount: widget.total)),
      );
      if (mounted && retried == true) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Select your payment method'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('₹${widget.total.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _paying ? null : _pay,
            child: _paying
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Pay ₹${widget.total.toStringAsFixed(0)}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text('Scan and Pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Scan this QR code or choose an app',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                const SizedBox(height: 14),
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_2, size: 140, color: AppColors.ink),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('UPI ID: $_upiId', style: const TextStyle(fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(text: _upiId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UPI ID copied')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text('Select UPI Apps', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _apps
                .map((a) => ActionChip(
                      label: Text(a),
                      onPressed: _paying ? null : _pay,
                      backgroundColor: AppColors.surface,
                      side: const BorderSide(color: AppColors.border),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
