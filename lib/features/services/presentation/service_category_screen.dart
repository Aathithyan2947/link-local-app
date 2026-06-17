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
  // A single shared "Other" option shown at the bottom of the whole list.
  bool _otherSelected = false;
  final _otherCtrl = TextEditingController();
  String _query = '';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool _isOther(ServiceSubcategory s) {
    final n = s.name.toLowerCase().trim();
    return n == 'other' || n == 'others';
  }

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
    return Icons.handyman_outlined;
  }

  Future<void> _continue() async {
    final ids = _selected.toList();
    final customServices = <Map<String, dynamic>>[];

    if (_otherSelected) {
      final name = _otherCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'Please enter the name of your service');
        return;
      }
      // No categoryId — the backend files it under a shared "Other" category for approval.
      customServices.add({'name': name});
    }

    if (ids.isEmpty && customServices.isEmpty) {
      setState(() => _error = 'Select at least one service you offer');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(serviceProfileRepositoryProvider).saveServiceTypes(ids, customServices: customServices);
      await ref.read(authControllerProvider.notifier).refreshUser();
      if (mounted) context.go(Routes.verificationHold);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _selectionCount => _selected.length + (_otherSelected ? 1 : 0);

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
                  Text('Browse by category and select all that apply — you can change these anytime.',
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
                data: (categories) => _buildGroupedList(categories),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 12)],
                  PrimaryButton(
                    label: _selectionCount == 0 ? 'Continue' : 'Continue ($_selectionCount)',
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

  Widget _buildGroupedList(List<ServiceCategory> categories) {
    // Category → matching-subcategory sections, with per-category "Other" options removed —
    // a single shared "Other" lives at the bottom of the whole list instead.
    final sections = <Widget>[];
    for (final cat in categories) {
      final subs = cat.subcategories
          .where((s) => !_isOther(s))
          .where((s) => s.name.toLowerCase().contains(_query) || cat.name.toLowerCase().contains(_query))
          .toList();
      if (subs.isEmpty) continue;

      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          cat.name.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6, color: AppColors.textSecondary),
        ),
      ));

      for (final s in subs) {
        final selected = _selected.contains(s.id);
        sections.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: Icon(_iconFor(s.name), color: selected ? AppColors.primary : AppColors.textSecondary),
            title: Text(s.name,
                style: TextStyle(fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textPrimary)),
            trailing: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.divider,
            ),
            onTap: () => setState(() {
              selected ? _selected.remove(s.id) : _selected.add(s.id);
            }),
          ),
        ));
        sections.add(const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20));
      }
    }

    if (sections.isEmpty && _query.isNotEmpty) {
      sections.add(const Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
        child: Text("No matching services — add yours under “Other” below.",
            style: TextStyle(color: AppColors.textSecondary)),
      ));
    }

    // ── Single shared "Other" at the bottom ──
    sections.add(const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text('CAN’T FIND YOURS?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6, color: AppColors.textSecondary)),
    ));
    sections.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: Icon(Icons.more_horiz, color: _otherSelected ? AppColors.primary : AppColors.textSecondary),
            title: Text('Other (enter your service)',
                style: TextStyle(fontWeight: FontWeight.w500, color: _otherSelected ? AppColors.primary : AppColors.textPrimary)),
            trailing: Icon(
              _otherSelected ? Icons.check_circle : Icons.circle_outlined,
              color: _otherSelected ? AppColors.primary : AppColors.divider,
            ),
            onTap: () => setState(() => _otherSelected = !_otherSelected),
          ),
          if (_otherSelected)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: TextField(
                controller: _otherCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Name your service',
                  prefixIcon: Icon(Icons.edit_outlined, color: AppColors.textMuted),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
        ],
      ),
    ));

    return ListView(padding: const EdgeInsets.only(bottom: 12), children: sections);
  }
}
