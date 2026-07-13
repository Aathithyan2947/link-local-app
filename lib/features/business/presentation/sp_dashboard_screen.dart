import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../orders/presentation/incoming_orders_screen.dart';
import '../data/business_repository.dart';
import 'add_product_screen.dart';
import 'sp_products_screen.dart';

/// The SP's business hub — the "Bakery menu" frame. Products, delivery, orders.
class SpDashboardScreen extends ConsumerWidget {
  const SpDashboardScreen({super.key});

  void _soon(BuildContext context, String label) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label coming soon')));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final productCount = ref.watch(myProductsProvider).asData?.value.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Shop')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddProductScreen()));
              ref.invalidate(myProductsProvider);
            },
            child: const Text('+ Add Item(s)'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Avatar(name: user?.name ?? 'My Shop', photoUrl: user?.photoUrl, radius: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? 'My Shop',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22)),
                    const SizedBox(height: 4),
                    Text('Manage your products, delivery and orders',
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _card(
            icon: Icons.grid_view_rounded,
            title: 'Products',
            subtitle: productCount != null ? '$productCount Items' : '…',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpProductsScreen())),
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.delivery_dining_rounded,
            title: 'Delivery settings',
            subtitle: 'Manage delivery availability, charges, and service area.',
            onTap: () => _soon(context, 'Delivery settings'),
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.assignment_outlined,
            title: 'Active orders',
            subtitle: 'View and manage incoming orders',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IncomingOrdersScreen())),
          ),
        ],
      ),
    );
  }

  Widget _card({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
