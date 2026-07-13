import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/data/product_models.dart';

class CartLine {
  const CartLine({required this.product, required this.qty});
  final SpProduct product;
  final int qty;
  double get total => (product.price ?? 0) * qty;
  CartLine copyWith({int? qty}) => CartLine(product: product, qty: qty ?? this.qty);
}

/// A cart is scoped to a single service provider. Adding an item from a
/// different provider replaces the cart.
class Cart {
  const Cart({this.spProfileId, this.spName, this.lines = const {}});
  final int? spProfileId;
  final String? spName;
  final Map<int, CartLine> lines; // keyed by product id

  int get count => lines.values.fold(0, (s, l) => s + l.qty);
  double get subtotal => lines.values.fold(0, (s, l) => s + l.total);
  bool get isEmpty => lines.isEmpty;
  List<CartLine> get items => lines.values.toList();
}

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  int qtyOf(int productId) => state.lines[productId]?.qty ?? 0;

  void _setLines(Map<int, CartLine> lines, {int? spProfileId, String? spName}) {
    state = Cart(
      spProfileId: lines.isEmpty ? null : (spProfileId ?? state.spProfileId),
      spName: lines.isEmpty ? null : (spName ?? state.spName),
      lines: lines,
    );
  }

  void add(int spProfileId, String spName, SpProduct product) {
    // Switching sellers starts a fresh cart.
    final base = state.spProfileId == spProfileId ? {...state.lines} : <int, CartLine>{};
    final existing = base[product.id];
    base[product.id] = existing == null ? CartLine(product: product, qty: 1) : existing.copyWith(qty: existing.qty + 1);
    _setLines(base, spProfileId: spProfileId, spName: spName);
  }

  void setQty(int productId, int qty) {
    final base = {...state.lines};
    if (qty <= 0) {
      base.remove(productId);
    } else if (base[productId] != null) {
      base[productId] = base[productId]!.copyWith(qty: qty);
    }
    _setLines(base);
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
