import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../reference/reference_models.dart';
import '../../reference/reference_repository.dart';
import '../data/service_profile_repository.dart';

class ServiceCategoryScreen extends ConsumerStatefulWidget {
  const ServiceCategoryScreen({super.key});

  @override
  ConsumerState<ServiceCategoryScreen> createState() => _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends ConsumerState<ServiceCategoryScreen> {
  final Set<int> _selected = {};
  String _query = '';
  bool _loading = false;
  String? _error;

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('yoga') || n.contains('fitness')) return Icons.self_improvement;
    if (n.contains('tuition') || n.contains('teacher') || n.contains('tutor')) return Icons.menu_book_outlined;
    if (n.contains('music')) return Icons.music_note_outlined;
    if (n.contains('dance')) return Icons.nightlife_outlined;
    if (n.contains('beautic') || n.contains('makeup') || n.contains('hair')) return Icons.spa_outlined;
    if (n.contains('baby')) return Icons.child_care_outlined;
    if (n.contains('pet')) return Icons.pets_outlined;
    if (n.contains('cater') || n.contains('baker') || n.contains('food') || n.contains('chef')) return Icons.restaurant_outlined;
    if (n.contains('candle') || n.contains('craft')) return Icons.local_fire_department_outlined;
    if (n.contains('mehendi') || n.contains('design') || n.contains('tattoo')) return Icons.brush_outlined;
    if (n.contains('account') || n.contains('tax') || n.contains('financ') || n.contains('ca ')) return Icons.calculate_outlined;
    if (n.contains('sew') || n.contains('tailor') || n.contains('embroid') || n.contains('fashion')) return Icons.content_cut_outlined;
    if (n.contains('sport') || n.contains('swim') || n.contains('cricket') || n.contains('football') || n.contains('karate')) return Icons.sports_soccer_outlined;
    if (n.contains('doctor') || n.contains('dentist') || n.contains('physio') || n.contains('health')) return Icons.medical_services_outlined;
    if (n.contains('web') || n.contains('app') || n.contains('ui')) return Icons.devices_outlined;
    if (n.contains('party') || n.contains('event') || n.contains('wedding')) return Icons.celebration_outlined;
    if (n.contains('other')) return Icons.more_horiz;
    return Icons.handyman_outlined;
  }

  Future<void> _continue() async {
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one service you offer');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(serviceProfileRepositoryProvider).saveServiceTypes(_selected.toList());
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (mounted) context.go(Routes.verificationHold);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(serviceCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Your Services')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What services do you offer?', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Select all that apply — you can change these anytime.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Search your service....',
                      prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: categoriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Failed to load services: $e')),
                data: (categories) {
                  final subs = <ServiceSubcategory>[
                    for (final c in categories) ...c.subcategories,
                  ].where((s) => s.name.toLowerCase().contains(_query)).toList();

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: subs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) {
                      final s = subs[i];
                      final selected = _selected.contains(s.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        leading: Icon(_iconFor(s.name),
                            color: selected ? AppColors.primary : AppColors.textSecondary),
                        title: Text(s.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: selected ? AppColors.primary : AppColors.textPrimary)),
                        trailing: Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          color: selected ? AppColors.primary : AppColors.divider,
                        ),
                        onTap: () => setState(() {
                          selected ? _selected.remove(s.id) : _selected.add(s.id);
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 12)],
                  PrimaryButton(
                    label: _selected.isEmpty ? 'Continue' : 'Continue (${_selected.length})',
                    loading: _loading,
                    onPressed: _continue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
