import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/business/data/product_models.dart';

void main() {
  group('ProductCustomization', () {
    test('round-trips through JSON', () {
      const c = ProductCustomization(label: 'Extra spicy', inputType: 'text', isRequired: true);
      final back = ProductCustomization.fromJson(c.toJson());
      expect(back.label, 'Extra spicy');
      expect(back.inputType, 'text');
      expect(back.isRequired, isTrue);
      expect(back.wantsText, isTrue);
    });

    test('defaults to an optional yes/no option', () {
      final c = ProductCustomization.fromJson({'label': 'Eggless'});
      expect(c.inputType, 'toggle');
      expect(c.isRequired, isFalse);
      expect(c.wantsText, isFalse);
    });
  });

  group('SpProduct', () {
    test('parses the customization list', () {
      final p = SpProduct.fromJson({
        'id': 1,
        'name': 'Chocolate cake',
        'customizations': [
          {'label': 'Eggless', 'inputType': 'toggle'},
          {'label': 'Custom message', 'inputType': 'text'},
        ],
      });
      expect(p.hasCustomizations, isTrue);
      expect(p.customizations.map((c) => c.label), ['Eggless', 'Custom message']);
      expect(p.customizations.last.wantsText, isTrue);
    });

    test('a product with no options is not customizable', () {
      final p = SpProduct.fromJson({'id': 2, 'name': 'Plain bread'});
      expect(p.hasCustomizations, isFalse);
      expect(p.customizations, isEmpty);
    });

    test('legacy customizationNotes text alone no longer marks a product customizable', () {
      // The old build inferred options by substring-matching this field, so a product whose
      // notes merely mentioned "Eggless" offered it. Options are explicit now.
      final p = SpProduct.fromJson({
        'id': 3,
        'name': 'Sourdough',
        'customizationNotes': 'Eggless available; Custom message available',
      });
      expect(p.hasCustomizations, isFalse);
      expect(p.customizationNotes, isNotNull);
    });
  });
}
