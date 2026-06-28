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

const _otherOption = 'Other (specify)';

/// A curated-master picker: a dropdown of approved [options] plus an "Other (specify)" choice
/// that reveals a free-text field (queued for admin approval). Resolve the entered value with
/// [pickedValue]. Pass [options] WITHOUT the "Other" entry — it's appended here.
List<Widget> _masterPicker(
  String hint,
  List<String> options,
  String selected,
  TextEditingController custom,
  ValueChanged<String> onChanged,
) {
  final all = [...options, _otherOption];
  return [
    DropdownButtonFormField<String>(
      initialValue: all.contains(selected) ? selected : _otherOption,
      isExpanded: true,
      decoration: InputDecoration(hintText: hint),
      items: all.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: (v) => onChanged(v ?? _otherOption),
    ),
    if (selected == _otherOption) ...[
      const SizedBox(height: 8),
      _field(custom, 'Enter $hint'),
      const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Sent for approval before others can pick it.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
    ],
  ];
}

/// Resolves a picker's value: the typed custom text when "Other" is chosen, else the selection.
String _pickedValue(String selected, TextEditingController custom) =>
    selected == _otherOption ? custom.text.trim() : selected;

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
          // Degree, School and College are independent curated catalogs, each pickable on its own.
          final degrees = await ref.read(educationDegreesProvider.future);
          final schools = await ref.read(schoolMasterProvider.future);
          final colleges = await ref.read(collegeMasterProvider.future);
          if (!ctx.mounted) return;
          String degreeSel = degrees.isNotEmpty ? degrees.first : _otherOption;
          String schoolSel = schools.isNotEmpty ? schools.first : _otherOption;
          String collegeSel = colleges.isNotEmpty ? colleges.first : _otherOption;
          final degreeCustom = TextEditingController();
          final schoolCustom = TextEditingController();
          final collegeCustom = TextEditingController();
          await showFormSheet(ctx,
              title: 'Add Education',
              fields: (setSheet) => [
                    ..._masterPicker('Degree', degrees, degreeSel, degreeCustom,
                        (v) => setSheet(() => degreeSel = v)),
                    const SizedBox(height: 12),
                    ..._masterPicker('School', schools, schoolSel, schoolCustom,
                        (v) => setSheet(() => schoolSel = v)),
                    const SizedBox(height: 12),
                    ..._masterPicker('College', colleges, collegeSel, collegeCustom,
                        (v) => setSheet(() => collegeSel = v)),
                  ],
              onSave: () {
                final degree = _pickedValue(degreeSel, degreeCustom);
                final school = _pickedValue(schoolSel, schoolCustom);
                final college = _pickedValue(collegeSel, collegeCustom);
                if (degree.isEmpty && school.isEmpty && college.isEmpty) {
                  throw 'Add at least a degree, school or college';
                }
                return ref.read(profileRepositoryProvider).addEducation({
                  'degree': degree,
                  'schoolName': school,
                  'collegeName': college,
                });
              });
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
          final customCategory = TextEditingController();
          // A sentinel "Other" option lets members suggest a profession that isn't listed;
          // it's queued for admin approval before appearing for everyone.
          const other = IdName(-1, 'Other (specify)');
          final options = [...masters, other];
          IdName selected = options.first;
          await showFormSheet(ctx,
              title: 'Add Profession',
              fields: (setSheet) => [
                    DropdownButtonFormField<IdName>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(hintText: 'Category'),
                      items: options
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                          .toList(),
                      onChanged: (v) => setSheet(() => selected = v ?? other),
                    ),
                    if (selected.id == -1) ...[
                      const SizedBox(height: 12),
                      _field(customCategory, 'Your profession'),
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Sent for approval before it appears for others.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _field(company, 'Company / details'),
                  ],
              onSave: () {
                final isOther = selected.id == -1;
                final custom = customCategory.text.trim();
                if (isOther && custom.isEmpty) throw 'Please enter your profession';
                return ref.read(profileRepositoryProvider).addProfession({
                  if (!isOther) 'professionMasterId': selected.id,
                  if (isOther) 'category': custom,
                  'companyOrDetail': company.text.trim(),
                });
              });
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
