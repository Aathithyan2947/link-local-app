import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/core/validation/locality_rules.dart';

void main() {
  test('accepts real building and street names, in any script', () {
    for (final v in [
      'Sudarshan Sky Garden, Tower #2',
      'A-12/B, Shree Krupa (Phase 2)',
      "St. Mary's Residency & Annexe",
      'हीरानंदानी मेडोज़',
      '  Hiranandani    Meadows  ',
    ]) {
      expect(addressFieldError('building', 'Building', v), isNull, reason: v);
    }
  });

  test('rejects the values from BUG-020, with a reason', () {
    expect(addressFieldError('building', 'Building', r'@#$%^'), contains('only letters'));
    expect(addressFieldError('building', 'Building', 'A' * 150), contains('at most 80'));
    expect(addressFieldError('suburb', 'Suburb', 'A' * 101), contains('at most 100'));
    expect(addressFieldError('lane1', 'Lane 1', '-- //'), contains('letter or number'));
    expect(addressFieldError('area', 'Area', 'x'), contains('at least 2'));
  });

  test('pincode is six digits, not starting with 0', () {
    expect(addressFieldError('pincode', 'Pincode', '400601'), isNull);
    expect(addressFieldError('pincode', 'Pincode', '40060'), isNotNull);
    expect(addressFieldError('pincode', 'Pincode', '040601'), isNotNull);
  });

  test('empty is left to the required-field check', () {
    expect(addressFieldError('suburb', 'Suburb', ''), isNull);
  });

  test('stored values are tidied', () => expect(normalizeLocality('  Thane    West '), 'Thane West'));
}
