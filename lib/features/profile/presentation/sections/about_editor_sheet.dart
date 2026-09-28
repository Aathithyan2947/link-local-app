import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/profile_models.dart';
import '../../data/profile_repository.dart';

/// Opens the profile's single About editor — About Me, Education and Profession on one
/// sheet, saved together. Resolves true when something was saved.
///
/// [fallbackAboutMe] pre-fills About Me for profiles whose text only lives in the
/// admin-configured Basic Details answers; saving moves it onto the profile itself.
/// [afterSave] runs before the sheet closes (e.g. refetching the screen underneath), so
/// the new values are already on screen when it does.
Future<bool> showAboutEditor(
  BuildContext context, {
  String? fallbackAboutMe,
  Future<void> Function()? afterSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Dragging down would bypass the unsaved-changes check; the close button and the
    // back gesture both go through it.
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AboutEditorSheet(fallbackAboutMe: fallbackAboutMe, afterSave: afterSave),
  );
  return saved ?? false;
}

const _other = 'Other (specify)';

/// A catalog choice: nothing (''), a catalog value, or [_other] with typed text.
class _Pick {
  _Pick.from(String? value, List<String> options) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return;
    final match = options.where((o) => o.toLowerCase() == v.toLowerCase());
    if (match.isNotEmpty) {
      selection = match.first;
    } else {
      // Not (or not yet) in the catalog — e.g. an "Other" still awaiting approval.
      selection = _other;
      custom.text = v;
    }
  }

  String selection = '';
  final custom = TextEditingController();

  String get value => selection == _other ? custom.text.trim() : selection;
  bool get missingCustom => selection == _other && custom.text.trim().isEmpty;
}

class _EducationDraft {
  _EducationDraft(EducationEntry? e, _Catalogs c)
      : degree = _Pick.from(e?.degree, c.degrees),
        school = _Pick.from(e?.schoolName, c.schools),
        college = _Pick.from(e?.collegeName, c.colleges);
  final _Pick degree;
  final _Pick school;
  final _Pick college;

  Map<String, dynamic> toJson() => {
        if (degree.value.isNotEmpty) 'degree': degree.value,
        if (school.value.isNotEmpty) 'schoolName': school.value,
        if (college.value.isNotEmpty) 'collegeName': college.value,
      };

  void dispose() {
    degree.custom.dispose();
    school.custom.dispose();
    college.custom.dispose();
  }
}

/// Sentinel for the profession dropdown's "Other (specify)" entry.
const _otherProfession = IdName(-1, _other);

class _ProfessionDraft {
  _ProfessionDraft(IdName? p, List<IdName> masters) {
    company.text = p?.subtitle ?? '';
    if (p == null) return;
    final match = masters.where((m) => m.id == p.masterId);
    if (match.isNotEmpty) {
      selected = match.first;
    } else {
      // A category still awaiting approval isn't in the active list; keep it as typed text.
      selected = _otherProfession;
      custom.text = p.label;
    }
  }

  IdName? selected;
  final custom = TextEditingController();
  final company = TextEditingController();

  bool get isEmpty => selected == null && company.text.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        if (selected != null && selected!.id != -1) 'professionMasterId': selected!.id,
        if (selected?.id == -1) 'category': custom.text.trim(),
        if (company.text.trim().isNotEmpty) 'companyOrDetail': company.text.trim(),
      };

  void dispose() {
    custom.dispose();
    company.dispose();
  }
}

class _Catalogs {
  const _Catalogs(this.degrees, this.schools, this.colleges, this.professions);
  final List<String> degrees;
  final List<String> schools;
  final List<String> colleges;
  final List<IdName> professions;
}

class _AboutEditorSheet extends ConsumerStatefulWidget {
  const _AboutEditorSheet({this.fallbackAboutMe, this.afterSave});
  final String? fallbackAboutMe;
  final Future<void> Function()? afterSave;

  @override
  ConsumerState<_AboutEditorSheet> createState() => _AboutEditorSheetState();
}

class _AboutEditorSheetState extends ConsumerState<_AboutEditorSheet> {
  final _about = TextEditingController();
  final _educations = <_EducationDraft>[];
  final _professions = <_ProfessionDraft>[];
  _Catalogs? _catalogs;
  String? _loadError;
  String? _error;
  bool _saving = false;

  /// The payload as loaded, to tell whether anything changed.
  String _initial = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _about.dispose();
    for (final e in _educations) {
      e.dispose();
    }
    for (final p in _professions) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      // Straight from the server rather than the cached provider, so the editor never
      // opens on stale data.
      final results = await Future.wait([
        repo.getMyProfile(),
        ref.read(educationDegreesProvider.future),
        ref.read(schoolMasterProvider.future),
        ref.read(collegeMasterProvider.future),
        ref.read(professionMasterProvider.future),
      ]);
      final profile = results[0] as ProfileDetail;
      final catalogs = _Catalogs(
        results[1] as List<String>,
        results[2] as List<String>,
        results[3] as List<String>,
        results[4] as List<IdName>,
      );
      if (!mounted) return;
      setState(() {
        _catalogs = catalogs;
        _about.text = (profile.aboutMe?.trim().isNotEmpty ?? false) ? profile.aboutMe! : (widget.fallbackAboutMe ?? '');
        _educations.addAll(profile.educationEntries.map((e) => _EducationDraft(e, catalogs)));
        _professions.addAll(profile.professions.map((p) => _ProfessionDraft(p, catalogs.professions)));
        _initial = _payloadKey();
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Map<String, dynamic> _payload() => {
        'aboutMe': _about.text.trim(),
        'educations': _educations.map((e) => e.toJson()).where((j) => j.isNotEmpty).toList(),
        'professions': _professions.where((p) => !p.isEmpty).map((p) => p.toJson()).toList(),
      };

  String _payloadKey() => jsonEncode(_payload());

  bool get _dirty => _catalogs != null && _payloadKey() != _initial;

  String? _validate() {
    for (final e in _educations) {
      for (final (label, pick) in [('degree', e.degree), ('school', e.school), ('college', e.college)]) {
        if (pick.missingCustom) return 'Enter the $label, or pick one from the list';
      }
    }
    for (final p in _professions) {
      if (p.isEmpty) continue;
      if (p.selected == null) return 'Choose a profession for "${p.company.text.trim()}"';
      if (p.selected!.id == -1 && p.custom.text.trim().isEmpty) return 'Enter your profession';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = _payload();
      await ref.read(profileRepositoryProvider).setAbout(
            aboutMe: body['aboutMe'] as String,
            educations: (body['educations'] as List).cast<Map<String, dynamic>>(),
            professions: (body['professions'] as List).cast<Map<String, dynamic>>(),
          );
      ref.invalidate(myProfileProvider);
      // Refetch the screen underneath before closing, so the sheet lifts off fresh data.
      try {
        await widget.afterSave?.call();
      } catch (_) {
        // Saved regardless; the screen still refreshes itself on its next load.
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("Your edits to About, Education and Profession haven't been saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Always intercepted and decided here: a canPop that flips from true to false after
      // the first build (as it does once the data loads and gets edited) doesn't reach
      // this sheet's route, so the back gesture would close it and lose the edits.
      // Programmatic pops (after Save, or Discard) aren't blocked by this.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        if (_dirty) {
          _confirmDiscard();
        } else {
          Navigator.of(context).pop(false);
        }
      },
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Edit About', style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
              if (_catalogs != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!, style: const TextStyle(color: AppColors.error)),
                        ),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(
                onPressed: () {
                  setState(() => _loadError = null);
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final catalogs = _catalogs;
    if (catalogs == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        const _Heading('About Me'),
        TextField(
          controller: _about,
          maxLines: 5,
          minLines: 3,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Tell neighbours a little about yourself'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        const _Heading('Education'),
        for (final (i, e) in _educations.indexed)
          _EntryCard(
            // Keyed by the draft so removing a row doesn't hand its dropdowns' state to the next.
            key: ObjectKey(e),
            title: 'Education ${i + 1}',
            onRemove: () => setState(() => _educations.removeAt(i).dispose()),
            children: [
              ..._picker('Degree', catalogs.degrees, e.degree),
              const SizedBox(height: 10),
              ..._picker('School', catalogs.schools, e.school),
              const SizedBox(height: 10),
              ..._picker('College', catalogs.colleges, e.college),
            ],
          ),
        _AddButton(
          label: 'Add education',
          onTap: () => setState(() => _educations.add(_EducationDraft(null, catalogs))),
        ),
        const SizedBox(height: 16),
        const _Heading('Profession'),
        for (final (i, p) in _professions.indexed)
          _EntryCard(
            key: ObjectKey(p),
            title: 'Profession ${i + 1}',
            onRemove: () => setState(() => _professions.removeAt(i).dispose()),
            children: [
              DropdownButtonFormField<IdName>(
                initialValue: p.selected,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Profession'),
                items: [...catalogs.professions, _otherProfession]
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: (v) => setState(() => p.selected = v),
              ),
              if (p.selected?.id == -1) ...[
                const SizedBox(height: 10),
                _text(p.custom, 'Your profession'),
                const _PendingNote(),
              ],
              const SizedBox(height: 10),
              _text(p.company, 'Company / details (optional)'),
            ],
          ),
        _AddButton(
          label: 'Add profession',
          onTap: () => setState(() => _professions.add(_ProfessionDraft(null, catalogs.professions))),
        ),
      ],
    );
  }

  Widget _text(TextEditingController c, String hint) => TextField(
        controller: c,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint),
        onChanged: (_) => setState(() {}),
      );

  /// A catalog dropdown with "Other (specify)" revealing a free-text field.
  List<Widget> _picker(String label, List<String> options, _Pick pick) => [
        DropdownButtonFormField<String>(
          initialValue: pick.selection.isEmpty ? null : pick.selection,
          isExpanded: true,
          decoration: InputDecoration(hintText: '$label (optional)'),
          items: [
            // Lets a chosen value be taken back out without deleting the whole entry.
            const DropdownMenuItem(value: '', child: Text('None', style: TextStyle(color: AppColors.textMuted))),
            ...[...options, _other].map((o) => DropdownMenuItem(value: o, child: Text(o))),
          ],
          onChanged: (v) => setState(() => pick.selection = v ?? ''),
        ),
        if (pick.selection == _other) ...[
          const SizedBox(height: 8),
          _text(pick.custom, 'Enter $label'),
          const _PendingNote(),
        ],
      ];
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({super.key, required this.title, required this.onRemove, required this.children});
  final String title;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                  onPressed: onRemove,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: Text(label)),
      );
}

class _PendingNote extends StatelessWidget {
  const _PendingNote();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Sent for approval before others can pick it.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
}
