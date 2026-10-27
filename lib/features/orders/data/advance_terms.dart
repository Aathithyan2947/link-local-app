import '../../services/data/service_profile_repository.dart' show CustomField;

/// A provider's advance-payment terms from their answers (BUG-097): the same reading as the
/// backend's `advanceTermsFromFields` (lib/advancePayment.ts), which decides what checkout
/// charges. Here it only informs, e.g. on Make Payment, where the resident types the amount.
///
/// The questions are matched by name, in three shapes: "Advanced Payment Settings" or "How
/// much advance do you need?" [No Advance | Percentage Based] with an "Advance percentage", or
/// "Advance payment" [10% … 100% advance]. Returns the percentage (0 = no advance), or null
/// when the provider set none, or one that can't be read.
double? advancePercentOf(List<CustomField> fields) {
  String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String? answer(Set<String> names) {
    for (final f in fields) {
      final v = f.value?.trim() ?? '';
      if (names.contains(norm(f.fieldName)) && v.isNotEmpty) return v;
    }
    return null;
  }

  final mode = answer(const {
    'advanced payment settings',
    'advance payment settings',
    'how much advance do you need?',
    'how much advance do you need',
    'advance payment',
  });
  final percent = answer(const {'advance percentage', 'advance percent', 'advance %'});
  if (mode != null) {
    final m = mode.toLowerCase();
    if (m.contains('no advance')) return 0;
    return parseAdvancePercent(m.contains('percentage') ? percent : mode);
  }
  return parseAdvancePercent(percent);
}

/// The percentage in "50", "50%" or "50% advance": 1–100, else null.
double? parseAdvancePercent(String? value) {
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(value ?? '');
  final n = m == null ? null : double.tryParse(m.group(1)!);
  return n != null && n > 0 && n <= 100 ? n : null;
}

/// Whether a question is the advance percentage, which only takes 1–100.
bool isAdvancePercentField(String fieldName) =>
    const {'advance percentage', 'advance percent', 'advance %'}.contains(fieldName.trim().toLowerCase());

/// What's wrong with an advance percentage answer, or null (blank is fine: not answered).
String? advancePercentError(String value) {
  final t = value.trim();
  if (t.isEmpty) return null;
  return RegExp(r'^\d+(\.\d+)?\s*%?$').hasMatch(t) && parseAdvancePercent(t) != null
      ? null
      : 'Advance percentage must be between 1 and 100';
}

/// "50%", or "12.5%".
String percentLabel(double p) => '${p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString()}%';
