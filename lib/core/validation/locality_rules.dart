/// Mirrors the backend's locality rules (link-local-backend/src/lib/localityText.ts) so the
/// address form flags a bad value before saving; the backend still enforces them.
library;

final _allowed = RegExp(r"^[\p{L}\p{M}\p{N} .,'&()/#-]+$", unicode: true);
final _hasLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

const kComplexMaxLength = 80;
const kLocalityMaxLength = 100;
const kFlatWingMaxLength = 40;

/// Trims and collapses runs of spaces — what the backend stores.
String normalizeLocality(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The problem with a locality text value, or null when it's fine. Empty is left to the
/// caller's own required-field check.
String? localityError(String label, String value, int max) {
  final v = normalizeLocality(value);
  if (v.isEmpty) return null;
  if (v.length < 2) return '$label must be at least 2 characters';
  if (v.length > max) return '$label must be at most $max characters';
  if (!_allowed.hasMatch(v)) return "$label: only letters, numbers, spaces and . , ' & ( ) / - # are allowed";
  if (!_hasLetterOrDigit.hasMatch(v)) return '$label must include a letter or number';
  return null;
}

/// An Indian PIN code: six digits, not starting with 0. Empty is left to the caller.
String? pincodeError(String value) {
  final v = value.replaceAll(RegExp(r'\s'), '');
  if (v.isEmpty) return null;
  return RegExp(r'^[1-9]\d{5}$').hasMatch(v) ? null : "Pincode must be 6 digits and can't start with 0";
}

/// The rule for one address-form field, by its configured key.
String? addressFieldError(String fieldKey, String label, String value) => switch (fieldKey) {
      'pincode' => pincodeError(value),
      'building' => localityError(label, value, kComplexMaxLength),
      'lane1' || 'lane2' || 'area' || 'suburb' => localityError(label, value, kLocalityMaxLength),
      'flat_wing' => value.trim().length > kFlatWingMaxLength
          ? '$label must be at most $kFlatWingMaxLength characters'
          : null,
      _ => null,
    };

/// The input length cap for one address-form field, or null for no cap.
int? addressFieldMaxLength(String fieldKey) => switch (fieldKey) {
      'pincode' => 6,
      'building' => kComplexMaxLength,
      'lane1' || 'lane2' || 'area' || 'suburb' => kLocalityMaxLength,
      'flat_wing' => kFlatWingMaxLength,
      _ => null,
    };
