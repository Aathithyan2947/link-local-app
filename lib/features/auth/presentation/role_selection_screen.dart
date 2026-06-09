import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../application/auth_controller.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  String? _role;
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    if (_role == null) {
      setState(() => _error = 'Please choose how you’ll use Link Local');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_role == 'service_provider') {
        // Set type, then go pick services (which finishes onboarding → home).
        await ref.read(authControllerProvider.notifier).setUserType('service_provider');
        if (mounted) context.go(Routes.serviceCategory);
      } else {
        await ref.read(authControllerProvider.notifier).setUserType('resident');
        if (mounted) context.go(Routes.verificationHold);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How will you use Link Local?', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('You can offer services later from your profile too.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 28),
              _RoleCard(
                icon: Icons.home_outlined,
                title: 'Resident',
                subtitle: 'Discover neighbours, services, events and groups around you.',
                selected: _role == 'resident',
                onTap: () => setState(() => _role = 'resident'),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.work_outline,
                title: 'Service Provider',
                subtitle: 'Offer your services and reach people in your neighbourhood.',
                selected: _role == 'service_provider',
                onTap: () => setState(() => _role = 'service_provider'),
              ),
              const Spacer(),
              if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 12)],
              PrimaryButton(label: 'Continue', loading: _loading, onPressed: _continue),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySurface : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.field,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: selected ? Colors.white : AppColors.textSecondary, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.primary : AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
