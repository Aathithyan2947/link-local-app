import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../business/data/business_repository.dart';
import '../../discovery/discovery_repository.dart';
import '../../home/presentation/widgets/service_icons.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/data/profile_repository.dart';
import '../../reference/reference_models.dart';
import '../../reference/reference_repository.dart';
import '../data/service_profile_repository.dart';
import 'category_fields_form_screen.dart';

/// Picks the services a provider offers: the sign-up step, or My Services ([editing]).
class ServiceCategoryScreen extends ConsumerStatefulWidget {
  const ServiceCategoryScreen({super.key, this.editing = false});

  /// My Services (BUG-096): the current services come ticked, including a typed-in "Other"
  /// still waiting for approval (the list only has approved ones), and Save comes back here
  /// instead of continuing sign-up.
  final bool editing;

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

  /// My Services only: the services saved before this edit, and the pending ones still kept.
  Set<int> _initial = {};
  final List<MyService> _pending = [];
  final Set<int> _droppedPending = {};
  bool _loadingCurrent = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing) _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    setState(() => _loadingCurrent = true);
    try {
      final services = (await ref.read(myProfileProvider.future)).services;
      if (!mounted) return;
      setState(() {
        _initial = services.map((s) => s.subcategoryId).toSet();
        _selected.addAll(services.where((s) => !s.isPending).map((s) => s.subcategoryId));
        _pending.addAll(services.where((s) => s.isPending));
      });
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your services. Go back and try again.");
    } finally {
      if (mounted) setState(() => _loadingCurrent = false);
    }
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool _isOther(ServiceSubcategory s) {
    final n = s.name.toLowerCase().trim();
    return n == 'other' || n == 'others';
  }

  Future<void> _continue() async {
    final ids = [
      ..._selected,
      for (final s in _pending)
        if (!_droppedPending.contains(s.subcategoryId)) s.subcategoryId,
    ];
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
      if (!mounted) return;
      if (!widget.editing) {
        context.go(Routes.verificationHold);
        return;
      }
      await _afterEdit(ids.toSet().difference(_initial));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// My Services saved: refresh what depends on the services, then offer to answer the setup
  /// questions a newly added service brings, or come back.
  Future<void> _afterEdit(Set<int> added) async {
    ref.invalidate(myProfileProvider);
    ref.invalidate(customFieldsProvider);
    ref.invalidate(myProviderFeaturesProvider);
    ref.invalidate(serviceProviderDetailProvider);

    var newFields = const <CustomField>[];
    var hasMenu = false;
    if (added.isNotEmpty) {
      try {
        final fields = await ref.read(customFieldsProvider.future);
        newFields = fields.where((f) => added.contains(f.subcategoryId)).toList();
        if (newFields.isNotEmpty) hasMenu = (await ref.read(myProviderFeaturesProvider.future)).hasMenu;
      } catch (_) {
        // Saved either way; the profile banner still asks for anything required.
      }
    }
    if (!mounted) return;
    final steps = onboardingCategories(newFields, hasMenu: hasMenu);
    if (steps.isNotEmpty) {
      // Saved: Save shouldn't keep spinning behind the question.
      setState(() => _loading = false);
      final setUp = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set up your new services?'),
          content: const Text('Answer a few questions so neighbours know what you offer.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set up now')),
          ],
        ),
      );
      if (!mounted) return;
      // The chain ends on the provider's own page, clearing this screen off the stack.
      if (setUp == true) return pushOnboardingStep(context, ref, steps);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Services updated')));
    Navigator.pop(context);
  }

  int get _keptPending => _pending.where((s) => !_droppedPending.contains(s.subcategoryId)).length;

  int get _selectionCount => _selected.length + _keptPending + (_otherSelected ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(serviceCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(widget.editing ? 'My Services' : 'Your Services')),
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
                  Text(
                      widget.editing
                          ? 'Tick every service you offer. Untick one to take it off your profile.'
                          : 'Browse by category and select all that apply — you can change these anytime.',
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
              child: _loadingCurrent ? const Center(child: CircularProgressIndicator()) : categoriesAsync.when(
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
                    label: widget.editing
                        ? 'Save'
                        : (_selectionCount == 0 ? 'Continue' : 'Continue ($_selectionCount)'),
                    loading: _loading,
                    onPressed: _loadingCurrent ? null : _continue,
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
    // My Services: a typed-in service the admin hasn't approved yet isn't in the list below,
    // so it gets its own rows; unticking one drops it on Save.
    if (_pending.isNotEmpty) {
      sections.add(_heading('WAITING FOR APPROVAL'));
      for (final s in _pending) {
        final kept = !_droppedPending.contains(s.subcategoryId);
        sections.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: Icon(Icons.hourglass_top_rounded, color: kept ? AppColors.primary : AppColors.textSecondary),
            title: Text(s.name,
                style: TextStyle(fontWeight: FontWeight.w500, color: kept ? AppColors.primary : AppColors.textPrimary)),
            subtitle: const Text('Shows on your profile once approved', style: TextStyle(fontSize: 12)),
            trailing: Icon(kept ? Icons.check_circle : Icons.circle_outlined,
                color: kept ? AppColors.primary : AppColors.divider),
            onTap: () => setState(() {
              kept ? _droppedPending.add(s.subcategoryId) : _droppedPending.remove(s.subcategoryId);
            }),
          ),
        ));
        sections.add(const Divider(height: 1, color: AppColors.border, indent: 20, endIndent: 20));
      }
    }
    for (final cat in categories) {
      final subs = cat.subcategories
          .where((s) => !_isOther(s))
          .where((s) => s.name.toLowerCase().contains(_query) || cat.name.toLowerCase().contains(_query))
          .toList();
      if (subs.isEmpty) continue;

      sections.add(_heading(cat.name.toUpperCase()));

      for (final s in subs) {
        final selected = _selected.contains(s.id);
        sections.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            leading: ServiceIcon(
                serviceName: s.name, size: 24, color: selected ? AppColors.primary : AppColors.textSecondary),
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

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6, color: AppColors.textSecondary),
        ),
      );
}
