import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/profile_models.dart';
import '../../data/profile_repository.dart';
import '../widgets/section_widgets.dart';

/// Shared list view of items with swipe-free delete + a FAB to add.
class _SectionList extends ConsumerWidget {
  const _SectionList({
    required this.title,
    required this.section,
    required this.select,
    required this.emptyMessage,
    required this.onAdd,
    this.icon,
  });

  final String title;
  final String section; // delete path segment
  final List<IdName> Function(ProfileDetail) select;
  final String emptyMessage;
  final IconData? icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return SectionScaffold(
      title: title,
      onAdd: () async {
        await onAdd(context, ref);
        ref.invalidate(myProfileProvider);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptySection(message: '$e'),
        data: (p) {
          final items = select(p);
          if (items.isEmpty) return EmptySection(message: emptyMessage);
          return ListView(
            padding: const EdgeInsets.only(top: 16, bottom: 90),
            children: items
                .map((it) => ItemTile(
                      title: it.label,
                      subtitle: it.subtitle,
                      icon: icon,
                      onDelete: () async {
                        await ref.read(profileRepositoryProvider).deleteItem(section, it.id);
                        ref.invalidate(myProfileProvider);
                      },
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

TextField _field(TextEditingController c, String hint, {TextInputType? type}) =>
    TextField(controller: c, keyboardType: type, decoration: InputDecoration(hintText: hint));

// ── Education ────────────────────────────────────────────────
class EducationScreen extends StatelessWidget {
  const EducationScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Education',
        section: 'education',
        icon: Icons.school_outlined,
        emptyMessage: 'Add your school, college or degree.',
        select: (p) => p.educations,
        onAdd: (ctx, ref) async {
          final degree = TextEditingController();
          final school = TextEditingController();
          final college = TextEditingController();
          await showFormSheet(ctx,
              title: 'Add Education',
              fields: (_) => [
                    _field(degree, 'Degree (e.g. B.Tech)'),
                    const SizedBox(height: 12),
                    _field(school, 'School name'),
                    const SizedBox(height: 12),
                    _field(college, 'College name'),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addEducation({
                    'degree': degree.text.trim(),
                    'schoolName': school.text.trim(),
                    'collegeName': college.text.trim(),
                  }));
        },
      );
}

// ── Profession ───────────────────────────────────────────────
class ProfessionScreen extends StatelessWidget {
  const ProfessionScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Profession',
        section: 'professions',
        icon: Icons.work_outline,
        emptyMessage: 'Add your profession and company.',
        select: (p) => p.professions,
        onAdd: (ctx, ref) async {
          final masters = await ref.read(professionMasterProvider.future);
          if (!ctx.mounted) return;
          final company = TextEditingController();
          IdName? selected = masters.isNotEmpty ? masters.first : null;
          await showFormSheet(ctx,
              title: 'Add Profession',
              fields: (setSheet) => [
                    DropdownButtonFormField<IdName>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Category'),
                      items: masters
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                          .toList(),
                      onChanged: (v) => setSheet(() => selected = v),
                    ),
                    const SizedBox(height: 12),
                    _field(company, 'Company / details'),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addProfession({
                    if (selected != null) 'professionMasterId': selected!.id,
                    'companyOrDetail': company.text.trim(),
                  }));
        },
      );
}

// ── Hobbies ──────────────────────────────────────────────────
class HobbiesScreen extends StatelessWidget {
  const HobbiesScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Hobbies',
        section: 'hobbies',
        icon: Icons.favorite_border,
        emptyMessage: 'Add hobbies and interests.',
        select: (p) => p.hobbies,
        onAdd: (ctx, ref) async {
          final masters = await ref.read(hobbyMasterProvider.future);
          if (!ctx.mounted) return;
          final custom = TextEditingController();
          IdName? selected = masters.isNotEmpty ? masters.first : null;
          await showFormSheet(ctx,
              title: 'Add Hobby',
              fields: (setSheet) => [
                    DropdownButtonFormField<IdName>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Pick a hobby'),
                      items: masters
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                          .toList(),
                      onChanged: (v) => setSheet(() => selected = v),
                    ),
                    const SizedBox(height: 12),
                    const Text('or suggest a new one', style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    _field(custom, 'Custom hobby'),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addHobby(
                    custom.text.trim().isNotEmpty
                        ? {'customHobby': custom.text.trim()}
                        : {'hobbyMasterId': selected?.id},
                  ));
        },
      );
}

// ── Family ───────────────────────────────────────────────────
const _relations = [
  'grandfather', 'grandmother', 'great_grandfather', 'great_grandmother',
  'father', 'mother', 'father_in_law', 'mother_in_law', 'spouse',
  'child_1', 'child_2', 'child_3',
];

class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Family',
        section: 'family',
        icon: Icons.family_restroom_outlined,
        emptyMessage: 'Add family members.',
        select: (p) => p.family,
        onAdd: (ctx, ref) async {
          final name = TextEditingController();
          String relation = _relations.first;
          await showFormSheet(ctx,
              title: 'Add Family Member',
              fields: (setSheet) => [
                    DropdownButtonFormField<String>(
                      initialValue: relation,
                      isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Relation'),
                      items: _relations
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (v) => setSheet(() => relation = v ?? relation),
                    ),
                    const SizedBox(height: 12),
                    _field(name, 'Name'),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addFamily({
                    'relation': relation,
                    'name': name.text.trim(),
                  }));
        },
      );
}

// ── Pets ─────────────────────────────────────────────────────
class PetsScreen extends StatelessWidget {
  const PetsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Pets',
        section: 'pets',
        icon: Icons.pets_outlined,
        emptyMessage: 'Add your pets.',
        select: (p) => p.pets,
        onAdd: (ctx, ref) async {
          final name = TextEditingController();
          final type = TextEditingController();
          final breed = TextEditingController();
          final age = TextEditingController();
          await showFormSheet(ctx,
              title: 'Add Pet',
              fields: (_) => [
                    _field(name, 'Name'),
                    const SizedBox(height: 12),
                    _field(type, 'Type (Dog, Cat...)'),
                    const SizedBox(height: 12),
                    _field(breed, 'Breed'),
                    const SizedBox(height: 12),
                    _field(age, 'Age (years)', type: TextInputType.number),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addPet({
                    'name': name.text.trim(),
                    'type': type.text.trim(),
                    'breed': breed.text.trim(),
                    if (age.text.trim().isNotEmpty) 'age': age.text.trim(),
                  }));
        },
      );
}

// ── Contacts ─────────────────────────────────────────────────
const _contactTypes = ['phone', 'whatsapp', 'email', 'other'];

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SectionList(
        title: 'Contact Details',
        section: 'contacts',
        icon: Icons.contact_phone_outlined,
        emptyMessage: 'Add phone, WhatsApp or email.',
        select: (p) => p.contacts,
        onAdd: (ctx, ref) async {
          final value = TextEditingController();
          String type = _contactTypes.first;
          await showFormSheet(ctx,
              title: 'Add Contact',
              fields: (setSheet) => [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Type'),
                      items: _contactTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setSheet(() => type = v ?? type),
                    ),
                    const SizedBox(height: 12),
                    _field(value, 'Value'),
                  ],
              onSave: () => ref.read(profileRepositoryProvider).addContact({
                    'contactType': type,
                    'value': value.text.trim(),
                  }));
        },
      );
}
