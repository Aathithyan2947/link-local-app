import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../address/data/address_repository.dart';
import '../../address/presentation/address_proof_screen.dart';
import '../../services/presentation/service_category_screen.dart';
import '../../services/presentation/service_details_screen.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';
import 'sections/basic_sections.dart';
import 'sections/list_sections.dart';
import 'sections/sp_sections.dart';

class _Section {
  const _Section(this.icon, this.title, this.done, this.summary, this.builder);
  final IconData icon;
  final String title;
  final bool done;
  final String summary;
  final Widget Function() builder;
}

class ProfileCompletionScreen extends ConsumerWidget {
  const ProfileCompletionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Complete your profile')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (p) {
          final sections = _sectionsFor(p);
          // Address proof — uploadable here if the user skipped it at sign-up (PRD).
          final proof = ref.watch(myAddressProofProvider).asData?.value;
          sections.insert(
            1,
            _Section(
              Icons.verified_user_outlined,
              'Address Proof',
              proof?.hasDoc ?? false,
              proof?.statusLabel ?? 'Upload address proof',
              () => const AddressProofScreen(),
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ProgressHeader(percent: p.completionPercent),
              const SizedBox(height: 20),
              ...sections.map((s) => _SectionCard(
                    section: s,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => s.builder()));
                      ref.invalidate(myProfileProvider);
                      ref.invalidate(myAddressProofProvider);
                    },
                  )),
            ],
          );
        },
      ),
    );
  }

  List<_Section> _sectionsFor(ProfileDetail p) {
    final base = <_Section>[
      _Section(Icons.person_outline, 'Basic Info', p.photoUrl != null, p.photoUrl != null ? 'Photo added' : 'Add photo, DOB, gender, about', () => const BasicInfoScreen()),
      _Section(Icons.school_outlined, 'Education', p.educations.isNotEmpty, p.educations.isNotEmpty ? '${p.educations.length} added' : 'Add education', () => const EducationScreen()),
      _Section(Icons.work_outline, 'Profession', p.professions.isNotEmpty, p.professions.isNotEmpty ? '${p.professions.length} added' : 'Add profession', () => const ProfessionScreen()),
      _Section(Icons.favorite_border, 'Hobbies', p.hobbies.isNotEmpty, p.hobbies.isNotEmpty ? '${p.hobbies.length} added' : 'Add hobbies', () => const HobbiesScreen()),
      _Section(Icons.family_restroom_outlined, 'Family', p.family.isNotEmpty, p.family.isNotEmpty ? '${p.family.length} added' : 'Optional', () => const FamilyScreen()),
      _Section(Icons.pets_outlined, 'Pets', p.pets.isNotEmpty, p.pets.isNotEmpty ? '${p.pets.length} added' : 'Optional', () => const PetsScreen()),
      _Section(Icons.contact_phone_outlined, 'Contact Details', p.contacts.isNotEmpty, p.contacts.isNotEmpty ? '${p.contacts.length} added' : 'Add contacts', () => const ContactsScreen()),
      _Section(Icons.volunteer_activism_outlined, 'Can offer help with', (p.canOfferHelpWith ?? '').isNotEmpty, (p.canOfferHelpWith ?? '').isNotEmpty ? 'Added' : 'Tell neighbours', () => const OfferHelpScreen()),
    ];
    if (p.isServiceProvider) {
      base.addAll([
        _Section(Icons.handyman_outlined, 'Services', p.serviceTypes.isNotEmpty, p.serviceTypes.isNotEmpty ? '${p.serviceTypes.length} selected' : 'Pick services', () => const ServiceCategoryScreen()),
        _Section(Icons.restaurant_menu_outlined, 'Service Details', false, 'Menu / rate cards & more', () => const ServiceDetailsScreen()),
        _Section(Icons.shopping_bag_outlined, 'Products / Menu', p.products.isNotEmpty, p.products.isNotEmpty ? '${p.products.length} items' : 'Add products', () => const ProductsScreen()),
        _Section(Icons.local_shipping_outlined, 'Delivery', p.hasDelivery, p.hasDelivery ? 'Configured' : 'Set delivery prefs', () => const DeliveryScreen()),
      ]);
    }
    return base;
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.percent});
  final int percent;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
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
                const Text('A complete profile builds trust with neighbours',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.onTap});
  final _Section section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                color: section.done ? AppColors.primarySurface : AppColors.field,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(section.icon, color: section.done ? AppColors.primary : AppColors.textMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(section.summary, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              section.done ? Icons.check_circle : Icons.chevron_right,
              color: section.done ? AppColors.primary : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
