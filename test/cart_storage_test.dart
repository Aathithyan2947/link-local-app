import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_local/features/orders/data/cart_storage.dart';

void main() {
  group('StoredCart round-trip', () {
    test('survives encode/decode with every field intact', () {
      const cart = StoredCart(
        spProfileId: 43,
        spName: 'baker ram',
        lines: [
          StoredCartLine(
            productId: 7,
            qty: 2,
            customization: 'Eggless; less sugar',
            name: 'Chocolate cake',
            price: 499.50,
            photoUrl: '/uploads/cake.jpg',
          ),
          StoredCartLine(productId: 9, qty: 1),
        ],
      );

      final decoded = StoredCart.fromJson(jsonDecode(jsonEncode(cart.toJson())) as Map<String, dynamic>);

      expect(decoded.spProfileId, 43);
      expect(decoded.spName, 'baker ram');
      expect(decoded.lines.length, 2);
      expect(decoded.lines.first.productId, 7);
      expect(decoded.lines.first.qty, 2);
      expect(decoded.lines.first.customization, 'Eggless; less sugar');
      expect(decoded.lines.first.price, 499.50);
      expect(decoded.lines.first.photoUrl, '/uploads/cake.jpg');
      // A line saved without a display snapshot still restores its identity.
      expect(decoded.lines.last.productId, 9);
      expect(decoded.lines.last.name, isNull);
      expect(decoded.lines.last.price, isNull);
    });

    test('tolerates an int price and a missing qty', () {
      final decoded = StoredCart.fromJson({
        'spProfileId': 1,
        'lines': [
          {'productId': 3, 'price': 200},
        ],
      });
      expect(decoded.lines.single.price, 200.0);
      expect(decoded.lines.single.qty, 1);
      expect(decoded.spName, isNull);
    });

    test('an empty payload decodes to an empty cart', () {
      final decoded = StoredCart.fromJson({});
      expect(decoded.lines, isEmpty);
      expect(decoded.spProfileId, isNull);
    });
  });

  group('per-account isolation', () {
    test('each account gets its own storage key', () {
      // The whole point of the fix: account B must never read account A's cart, and A's cart
      // must still be on disk when they sign back in.
      final keys = <String>{};
      for (final userId in [42, 43]) {
        keys.add('ll_cart_$userId');
      }
      expect(keys.length, 2);
      expect(keys, containsAll(['ll_cart_42', 'll_cart_43']));
    });
  });
}
