import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/data/orders_repository.dart';

/// UPI payment detail — the "Payment - 2" frame. MOCK: any app/QR tap "pays".
/// Pops `true` when the (mock) payment succeeds.
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
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment failed. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('UPI Payment')),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Payment', style: TextStyle(color: AppColors.textSecondary)),
              Text('₹ ${widget.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
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
          ),
          const SizedBox(height: 22),
          const Text('Select UPI App', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
          const SizedBox(height: 26),
          const Center(child: Text('Scan and Pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          const SizedBox(height: 4),
          const Center(child: Text('Scan this QR code or choose an app', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.qr_code_2, size: 140, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
