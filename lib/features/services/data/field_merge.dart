import 'service_profile_repository.dart';

/// Field categories that describe the provider rather than one service: asked once, however
/// many services they pick. Questions are configured per service, so a provider with two
/// services used to get "Name", "Phone", "Experience"… twice in Basic Details, with nothing
/// saying which service each copy was for (BUG-099). Payment and Service Type stay per
/// service (a fee differs from service to service), shown under each service's name.
const kSharedFieldCategories = {'basic_details', 'travel', 'delivery'};

/// Shared-category questions, merged: one field per distinct question, plus which saved
/// fields each one answers.
class MergedFields {
  MergedFields._(this.fields, this._members);

  /// What to show: a merged question keeps its first copy's id, type and options; it's
  /// required when any copy is, and holds the first saved answer among them.
  final List<CustomField> fields;
  final Map<int, List<int>> _members;

  /// Every saved field [fieldId] answers: itself, plus the copies merged into it.
  List<int> membersOf(int fieldId) => _members[fieldId] ?? [fieldId];

  /// The shown field that answers [fieldId] (itself when it wasn't merged away).
  int shownIdOf(int fieldId) => _shownId(_members, fieldId);
}

int _shownId(Map<int, List<int>> members, int fieldId) {
  for (final entry in members.entries) {
    if (entry.value.contains(fieldId)) return entry.key;
  }
  return fieldId;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s:*]+'), ' ').trim();

/// Merges copies of the same question across services. Two fields are the same question when
/// they're in the same shared category with the same name (ignoring case and spacing), type
/// and options, and depend on the same answer of the same question, if on any. Order follows
/// each question's first copy.
MergedFields mergeSharedFields(List<CustomField> fields) {
  final byId = {for (final f in fields) f.fieldId: f};
  String? keyOf(CustomField f) {
    if (!kSharedFieldCategories.contains(f.category)) return null;
    final parent = f.dependsOnFieldId == null ? null : byId[f.dependsOnFieldId];
    final dependency = f.dependsOnFieldId == null
        ? ''
        : '${_norm(parent?.fieldName ?? '#${f.dependsOnFieldId}')}=${f.dependsOnValue}';
    return [f.category, _norm(f.fieldName), f.fieldType, (f.fieldOptions ?? '').trim(), dependency].join('|');
  }

  final groups = <String, List<CustomField>>{};
  final order = <List<CustomField>>[];
  for (final f in fields) {
    final key = keyOf(f);
    if (key == null) {
      order.add([f]);
      continue;
    }
    final group = groups[key];
    if (group == null) {
      order.add(groups[key] = [f]);
    } else {
      group.add(f);
    }
  }

  final members = <int, List<int>>{};
  for (final group in order) {
    if (group.length > 1) members[group.first.fieldId] = [for (final f in group) f.fieldId];
  }
  int shownId(int id) => _shownId(members, id);

  final shown = [
    for (final group in order)
      if (group.length == 1 &&
          (group.first.dependsOnFieldId == null ||
              shownId(group.first.dependsOnFieldId!) == group.first.dependsOnFieldId))
        group.first
      else
        _merge(group, group.first.dependsOnFieldId == null ? null : shownId(group.first.dependsOnFieldId!)),
  ];
  return MergedFields._(shown, members);
}

CustomField _merge(List<CustomField> group, int? dependsOnFieldId) {
  final first = group.first;
  final answered = group.where((f) => f.value?.trim().isNotEmpty ?? false).firstOrNull;
  return CustomField(
    fieldId: first.fieldId,
    subcategoryId: first.subcategoryId,
    subcategoryName: first.subcategoryName,
    category: first.category,
    fieldName: first.fieldName,
    fieldType: first.fieldType,
    isRequired: group.any((f) => f.isRequired),
    fieldOptions: first.fieldOptions,
    value: (answered ?? first).value,
    resolvedAreas: (answered ?? first).resolvedAreas,
    dependsOnFieldId: dependsOnFieldId,
    dependsOnValue: first.dependsOnValue,
  );
}

/// Whether [fields] belong to more than one service, so each service's share needs a heading.
bool spansSeveralServices(Iterable<CustomField> fields) => fields.map((f) => f.subcategoryName).toSet().length > 1;
