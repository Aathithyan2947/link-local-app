import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import 'incoming_orders_screen.dart';
import 'my_orders_screen.dart';
import 'order_history_screen.dart';

/// Reached from Profile → Transaction History → Orders / Bookings, and (with
/// [showOtherProviders] off) from My Shop → Orders. Splits "Orders" into
/// what's coming in now (SPs only), what's already happened, and — outside
/// My Shop — what the member has bought from other providers as a resident.
class OrdersHubScreen extends ConsumerWidget {
  const OrdersHubScreen({super.key, this.showOtherProviders = true});
  final bool showOtherProviders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSp = ref.watch(authControllerProvider).user?.isServiceProvider ?? false;

    final rows = [
      if (isSp)
        _RowData(
          icon: Icons.shopping_cart_outlined,
          label: 'Incoming Order',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IncomingOrdersScreen())),
        ),
      if (isSp)
        _RowData(
          icon: Icons.receipt_long_outlined,
          label: 'Order History',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrderHistoryScreen())),
        ),
      if (showOtherProviders)
        _RowData(
          icon: Icons.storefront_outlined,
          label: 'Orders from Other Providers',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyOrdersScreen())),
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Orders / Bookings'),
      ),
      body: Column(
        children: [
          for (int i = 0; i < rows.length; i++)
            _Row(icon: rows[i].icon, label: rows[i].label, onTap: rows[i].onTap, showDivider: i < rows.length - 1),
        ],
      ),
    );
  }
}

class _RowData {
  const _RowData({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.showDivider = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: showDivider ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))) : null,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
