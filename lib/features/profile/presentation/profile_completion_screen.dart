import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/push_guard.dart';
import '../../../core/router/app_router.dart' show appRouteObserver, lastPopWasMenuOrDialog;
import '../../../core/theme/app_colors.dart';
import '../../address/presentation/address_proof_screen.dart';
import '../../business/data/business_repository.dart';
import '../../business/presentation/sp_products_screen.dart';
import '../../business/presentation/sp_rates_screen.dart';
import '../../discovery/presentation/service_provider_detail_screen.dart';
import '../../services/data/service_profile_repository.dart';
import '../../services/presentation/category_fields_form_screen.dart';
import '../../services/presentation/service_category_screen.dart';
import '../data/profile_completion.dart';
import '../data/profile_repository.dart';
import 'sections/about_editor_sheet.dart';

const _titles = {
  'photo': 'Profile photo',
  'address': 'Address',
  'addressProof': 'Address proof',
  'about': 'About you',
  'education': 'Education',
  'profession': 'Profession',
  'services': 'Services',
  'businessDetails': 'Business details',
  'menuItems': 'Menu items',
  'charges': 'Charges',
};

const _hints = {
  'photo': 'Add a profile photo',
  'address': 'Add your address',
  'addressProof': 'Upload your address proof',
  'about': 'Tell neighbours about yourself',
  'education': 'Add your education',
  'profession': 'Add your profession',
  'services': 'Pick the services you offer',
  'businessDetails': 'Answer your business questions',
  'menuItems': 'Add your first menu item',
  'charges': 'Set your charges',
};

const _icons = {
  'photo': Icons.photo_camera_outlined,
  'address': Icons.home_outlined,
  'addressProof': Icons.verified_user_outlined,
  'about': Icons.person_outline,
  'education': Icons.school_outlined,
  'profession': Icons.work_outline,
  'services': Icons.handyman_outlined,
  'businessDetails': Icons.assignment_outlined,
  'menuItems': Icons.restaurant_menu_outlined,
  'charges': Icons.currency_rupee,
};

String _title(CompletionStep s) => _titles[s.key] ?? s.label;

/// What to do for [step], e.g. "Upload your address proof" (also the Profile tab's "Next:").
String completionStepHint(CompletionStep step) => _hints[step.key] ?? 'Add your ${step.label.toLowerCase()}';

/// "Complete your profile": the checklist behind the Profile tab's meter. Each step opens the
/// screen where it's filled in; the list refreshes when that screen closes.
class ProfileCompletionScreen extends ConsumerStatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  ConsumerState<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends ConsumerState<ProfileCompletionScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    if (lastPopWasMenuOrDialog()) return;
    ref.invalidate(profileCompletionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileCompletionProvider);
    final completion = async.value;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Complete your profile')),
      body: completion == null
          ? async.hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Couldn't load your profile"),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(profileCompletionProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProgressHeader(completion: completion),
                const SizedBox(height: 20),
                for (final step in completion.steps)
                  _StepCard(
                    step: step,
                    onTap: () => openCompletionStep(context, ref, step, profileId: completion.profileId),
                  ),
              ],
            ),
    );
  }
}

/// Opens where [step] is filled in. Editors opened here refresh the checklist as they close.
Future<void> openCompletionStep(BuildContext context, WidgetRef ref, CompletionStep step, {int? profileId}) async {
  Future<void> push(Widget page) => context.pushPage(MaterialPageRoute(builder: (_) => page));
  // Photo, address, and charges answered as questions are edited on My Profile.
  Future<void> myProfile() async {
    final id = profileId ?? ref.read(myProfileProvider).asData?.value.id;
    if (id != null) await push(ServiceProviderDetailScreen(id: id));
  }

  switch (step.key) {
    case 'addressProof':
      return push(const AddressProofScreen());
    case 'about':
    case 'education':
    case 'profession':
      await showAboutEditor(context);
      return;
    case 'services':
      return push(const ServiceCategoryScreen(editing: true));
    case 'menuItems':
      return push(const SpProductsScreen());
    case 'businessDetails':
    case 'charges':
      List<CustomField> fields;
      bool hasMenu;
      try {
        fields = await ref.read(customFieldsProvider.future).timeout(const Duration(seconds: 10));
        hasMenu = (await ref.read(myProviderFeaturesProvider.future).timeout(const Duration(seconds: 10))).hasMenu;
      } catch (_) {
        if (context.mounted) await myProfile();
        return;
      }
      if (!context.mounted) return;
      if (step.key == 'businessDetails') {
        // The onboarding questions, step by step, as My Services' "Set up now" runs them.
        return pushOnboardingStep(context, ref, onboardingCategories(fields, hasMenu: hasMenu));
      }
      // Charges asked as Payment questions live on My Profile; otherwise the rates editor.
      return fields.any((f) => f.category == 'payment') ? myProfile() : push(const SpRatesScreen());
    default:
      return myProfile();
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.completion});
  final ProfileCompletion completion;

  @override
  Widget build(BuildContext context) {
    final percent = completion.percent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$percent% complete',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            completion.isComplete
                ? 'Your profile is complete'
                : 'A complete profile builds trust with neighbours',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.onTap});
  final CompletionStep step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = step.done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: done ? AppColors.primarySurface : AppColors.field,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icons[step.key] ?? Icons.check_box_outline_blank,
                    color: done ? AppColors.primary : AppColors.textMuted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title(step), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(done ? 'Done' : completionStepHint(step), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              // The line above already says "Done"; the tick adds nothing for a screen reader.
              ExcludeSemantics(
                child: Icon(
                  done ? Icons.check_circle : Icons.chevron_right,
                  color: done ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
