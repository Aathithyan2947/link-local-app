import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../orders/presentation/orders_hub_screen.dart';
import '../data/business_repository.dart';
import 'sp_products_screen.dart';
import 'sp_rates_screen.dart';

/// The SP's business hub — trimmed to just the two things they do day-to-day:
/// manage what they sell (Catalogue) and manage what comes in (Orders).
/// Availability, Off days and Delivery settings live under Profile instead.
class SpDashboardScreen extends ConsumerWidget {
  const SpDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMenu = ref.watch(myProviderFeaturesProvider).asData?.value.hasMenu ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('My Shop'),
      ),
      body: Column(
        children: [
          _Row(
            icon: Icons.shopping_cart_outlined,
            label: 'Catalogue',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => hasMenu ? const SpProductsScreen() : const SpRatesScreen(),
            )),
          ),
          _Row(
            icon: Icons.receipt_long_outlined,
            label: 'Orders',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const OrdersHubScreen(showOtherProviders: false))),
            showDivider: false,
          ),
        ],
      ),
    );
  }
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
