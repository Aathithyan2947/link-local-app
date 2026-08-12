import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One saved cart line. Only the order-relevant identifiers are authoritative — `name`,
/// `price` and `photoUrl` are a display snapshot so the cart renders instantly on open,
/// and are replaced by live product data as soon as the SP's catalogue loads.
class StoredCartLine {
  const StoredCartLine({
    required this.productId,
    required this.qty,
    this.customization,
    this.name,
    this.price,
    this.photoUrl,
  });

  final int productId;
  final int qty;
  final String? customization;
  final String? name;
  final double? price;
  final String? photoUrl;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'qty': qty,
        if (customization != null) 'customization': customization,
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (photoUrl != null) 'photoUrl': photoUrl,
      };

  factory StoredCartLine.fromJson(Map<String, dynamic> j) => StoredCartLine(
        productId: (j['productId'] as num).toInt(),
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        customization: j['customization'] as String?,
        name: j['name'] as String?,
        price: (j['price'] as num?)?.toDouble(),
        photoUrl: j['photoUrl'] as String?,
      );
}

class StoredCart {
  const StoredCart({this.spProfileId, this.spName, this.lines = const []});
  final int? spProfileId;
  final String? spName;
  final List<StoredCartLine> lines;

  Map<String, dynamic> toJson() => {
        'spProfileId': spProfileId,
        'spName': spName,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory StoredCart.fromJson(Map<String, dynamic> j) => StoredCart(
        spProfileId: (j['spProfileId'] as num?)?.toInt(),
        spName: j['spName'] as String?,
        lines: ((j['lines'] as List?) ?? [])
            .map((e) => StoredCartLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Per-account cart persistence.
///
/// Keyed by user id so two accounts on one device keep separate carts: signing out leaves the
/// cart on disk untouched and signing back in restores it, while a different account sees only
/// its own. There is no server-side cart, so this is device-local — the same account on
/// another device starts empty.
class CartStorage {
  const CartStorage([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  String _key(int userId) => 'll_cart_$userId';

  Future<StoredCart> load(int userId) async {
    try {
      final raw = await _storage.read(key: _key(userId));
      if (raw == null || raw.isEmpty) return const StoredCart();
      return StoredCart.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A cart that can't be parsed (older format, corrupt write) must not break the app.
      return const StoredCart();
    }
  }

  Future<void> save(int userId, StoredCart cart) async {
    try {
      if (cart.lines.isEmpty) {
        await _storage.delete(key: _key(userId));
      } else {
        await _storage.write(key: _key(userId), value: jsonEncode(cart.toJson()));
      }
    } catch (_) {
      // Persistence is best-effort; losing a write must not fail the add-to-cart action.
    }
  }
}
