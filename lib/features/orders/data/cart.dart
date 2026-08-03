import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/data/product_models.dart';

class CartLine {
  const CartLine({required this.product, required this.qty, this.customizationSelection});
  final SpProduct product;
  final int qty;
  /// The resident's own customization choice for this order (e.g. "Eggless; Custom
  /// message: less sugar please"), set via the Product Details screen. Falls back to the
  /// product's default `customizationNotes` when the resident never opened that screen.
  final String? customizationSelection;
  double get total => (product.price ?? 0) * qty;
  CartLine copyWith({int? qty, String? customizationSelection}) => CartLine(
        product: product,
        qty: qty ?? this.qty,
        customizationSelection: customizationSelection ?? this.customizationSelection,
      );
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

  /// Sets this product's quantity and the resident's chosen customization in one shot —
  /// used by the Product Details screen's "Confirm".
  void addWithCustomization(int spProfileId, String spName, SpProduct product, int qty, String? customization) {
    final base = state.spProfileId == spProfileId ? {...state.lines} : <int, CartLine>{};
    if (qty <= 0) {
      base.remove(product.id);
    } else {
      base[product.id] = CartLine(product: product, qty: qty, customizationSelection: customization);
    }
    _setLines(base, spProfileId: spProfileId, spName: spName);
  }

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
