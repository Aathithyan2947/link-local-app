import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_controller.dart';
import '../../home/presentation/widgets/home_widgets.dart';
import '../../orders/presentation/incoming_orders_screen.dart';
import '../data/business_repository.dart';
import '../data/rate_models.dart';
import 'add_product_screen.dart';
import 'blackout_dates_screen.dart';
import 'delivery_settings_screen.dart';
import 'setup/sp_setup_wizard_screen.dart';
import 'sp_products_screen.dart';
import 'sp_rates_screen.dart';

/// The SP's business hub — the "Bakery menu" frame. Branches by provider kind:
/// product SPs manage products + delivery; service SPs manage charges (no cart).
class SpDashboardScreen extends ConsumerWidget {
  const SpDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final kind = ref.watch(myProviderKindProvider).asData?.value ?? 'product';
    final isService = kind == 'service';
    final productCount = ref.watch(myProductsProvider).asData?.value.length;
    final rates = ref.watch(myRatesProvider).asData?.value ?? const <SpRate>[];
    final availability = ref.watch(myAvailabilityProvider).asData?.value.availability;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My Shop')),
      bottomNavigationBar: isService
          ? null
          : SafeArea(
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
                    Text(isService ? 'Manage your charges, availability and bookings' : 'Manage your products, delivery and orders',
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (isService)
            _card(
              icon: Icons.payments_outlined,
              title: 'Charges & rates',
              subtitle: rates.isNotEmpty
                  ? rates.map((r) => '${r.typeLabel} ₹${r.amount.toStringAsFixed(0)}').join(' · ')
                  : 'Set your per-session / monthly / hourly charges',
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpRatesScreen()));
                ref.invalidate(myRatesProvider);
              },
            )
          else
            _card(
              icon: Icons.grid_view_rounded,
              title: 'Products',
              subtitle: productCount != null ? '$productCount Items' : '…',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpProductsScreen())),
            ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.event_available_outlined,
            title: 'Availability & schedule',
            subtitle: availability != null
                ? '${availability.daysLabel} · ${availability.timeLabel}'
                : 'Set your working days & timings',
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SpSetupWizardScreen(
                  initialAvailability: availability,
                  initialName: user?.name,
                  isService: isService,
                ),
              ));
              ref.invalidate(myAvailabilityProvider);
            },
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.event_busy_outlined,
            title: 'Off days',
            subtitle: 'Mark holidays and days you’re unavailable',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlackoutDatesScreen())),
          ),
          if (!isService) ...[
            const SizedBox(height: 12),
            _card(
              icon: Icons.delivery_dining_rounded,
              title: 'Delivery settings',
              subtitle: 'Manage delivery availability, charges, and service area.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliverySettingsScreen())),
            ),
          ],
          const SizedBox(height: 12),
          _card(
            icon: Icons.assignment_outlined,
            title: isService ? 'Bookings' : 'Active orders',
            subtitle: isService ? 'View and manage booking requests' : 'View and manage incoming orders',
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
