import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_scope.dart';
import '../../business/data/product_models.dart';
import 'cart_storage.dart';

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
  /// Unlike every other user-scoped provider (which calls `ref.bindToAccount()` to be *reset*
  /// on an account change), the cart is *reloaded*: items an account added are theirs to keep.
  /// Signing out and back in restores them; a different account on the same device sees only
  /// its own cart, because each is stored under its own user id.
  @override
  Cart build() {
    final userId = ref.watch(authScopeProvider);
    if (userId != null) _restore(userId);
    return const Cart();
  }

  CartStorage get _storage => ref.read(cartStorageProvider);

  Future<void> _restore(int userId) async {
    final saved = await _storage.load(userId);
    // The account can change while this read is in flight — writing then would drop one
    // user's cart into another's session, the exact bug this whole change exists to stop.
    if (!ref.mounted || ref.read(authScopeProvider) != userId) return;
    if (saved.lines.isEmpty) return;
    // Anything added while the read was in flight wins — never overwrite a live edit.
    if (state.lines.isNotEmpty) return;
    state = Cart(
      spProfileId: saved.spProfileId,
      spName: saved.spName,
      lines: {
        for (final l in saved.lines)
          l.productId: CartLine(
            product: SpProduct(id: l.productId, name: l.name ?? '', price: l.price, photoUrl: l.photoUrl),
            qty: l.qty,
            customizationSelection: l.customization,
          ),
      },
    );
  }

  /// Replaces the display snapshot with live catalogue data once an SP's products load, and
  /// drops lines whose product the SP has since removed or marked unavailable — better than
  /// silently checking out something no longer on sale. Returns the dropped names, if any.
  List<String> reconcileWith(List<SpProduct> products) {
    if (state.isEmpty) return const [];
    final byId = {for (final p in products) p.id: p};
    final kept = <int, CartLine>{};
    final dropped = <String>[];
    for (final line in state.lines.values) {
      final live = byId[line.product.id];
      if (live == null || !live.isAvailable) {
        dropped.add(line.product.name.isEmpty ? 'An item' : line.product.name);
        continue;
      }
      kept[line.product.id] = CartLine(
        product: live,
        qty: line.qty,
        customizationSelection: line.customizationSelection,
      );
    }
    // Always re-set: even with nothing dropped, this swaps the saved snapshot for live
    // prices and names.
    _setLines(kept);
    return dropped;
  }

  int qtyOf(int productId) => state.lines[productId]?.qty ?? 0;

  void _setLines(Map<int, CartLine> lines, {int? spProfileId, String? spName}) {
    state = Cart(
      spProfileId: lines.isEmpty ? null : (spProfileId ?? state.spProfileId),
      spName: lines.isEmpty ? null : (spName ?? state.spName),
      lines: lines,
    );
    _persist();
  }

  /// Written on every mutation so a crash or force-quit can't lose items.
  void _persist() {
    final userId = ref.read(authScopeProvider);
    if (userId == null) return;
    _storage.save(
      userId,
      StoredCart(
        spProfileId: state.spProfileId,
        spName: state.spName,
        lines: [
          for (final l in state.lines.values)
            StoredCartLine(
              productId: l.product.id,
              qty: l.qty,
              customization: l.customizationSelection,
              name: l.product.name,
              price: l.product.price,
              photoUrl: l.product.photoUrl,
            ),
        ],
      ),
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

  /// Empties the cart AND its saved copy — for after an order is placed, not for logout.
  void clear() {
    state = const Cart();
    _persist();
  }
}

final cartStorageProvider = Provider<CartStorage>((ref) => const CartStorage());

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
