import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One menu item in the cart. Hand-rolled (no `freezed`) — keeps the
/// build pipeline codegen-free. `unitPricePaise` is the GST-INCLUSIVE
/// displayed price; the server always re-derives the breakdown via
/// `compute_pricing` on order_place.
class CartItem {
  final String menuItemId;
  final String name;
  final String brand; // 'coffee' | 'fit'
  final int unitPricePaise;
  final int quantity;
  final String? imageUrl;

  const CartItem({
    required this.menuItemId,
    required this.name,
    required this.brand,
    required this.unitPricePaise,
    required this.quantity,
    this.imageUrl,
  });

  CartItem copyWith({int? quantity}) => CartItem(
        menuItemId: menuItemId,
        name: name,
        brand: brand,
        unitPricePaise: unitPricePaise,
        quantity: quantity ?? this.quantity,
        imageUrl: imageUrl,
      );

  int get linePaise => unitPricePaise * quantity;
}

/// Snapshot of the current bag. Always either an item-list cart OR a combo
/// cart — combos are mutually exclusive with à-la-carte items because the
/// combo price overrides the line-item sum (matches the order_place RPC).
class CartState {
  final List<CartItem> items;
  final String? comboId;
  final String? comboName;
  final int? comboPricePaise;
  final List<CartItem> comboItems;

  const CartState({
    this.items = const [],
    this.comboId,
    this.comboName,
    this.comboPricePaise,
    this.comboItems = const [],
  });

  static const empty = CartState();

  bool get isEmpty => items.isEmpty && comboId == null;
  bool get isCombo => comboId != null;
  int get totalItemCount =>
      isCombo ? comboItems.fold(0, (s, i) => s + i.quantity) : items.fold(0, (s, i) => s + i.quantity);

  /// Customer-facing total (GST-inclusive). Server re-derives from RPC.
  int get totalPaise =>
      comboPricePaise ?? items.fold(0, (s, i) => s + i.linePaise);
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState.empty);

  /// Adds an à-la-carte item. If the bag already holds a combo, the caller
  /// should explicitly removeCombo first (the cart sheet shows a confirm).
  void addItem(CartItem item) {
    if (state.isCombo) return;
    final existingIndex =
        state.items.indexWhere((i) => i.menuItemId == item.menuItemId);
    final next = [...state.items];
    if (existingIndex >= 0) {
      final merged = next[existingIndex];
      next[existingIndex] = merged.copyWith(quantity: merged.quantity + item.quantity);
    } else {
      next.add(item);
    }
    state = CartState(items: next);
  }

  /// Increment / decrement; removes the line if qty drops to 0.
  void changeQuantity(String menuItemId, int delta) {
    final next = <CartItem>[];
    for (final i in state.items) {
      if (i.menuItemId != menuItemId) {
        next.add(i);
        continue;
      }
      final newQty = i.quantity + delta;
      if (newQty > 0) next.add(i.copyWith(quantity: newQty));
    }
    state = CartState(items: next);
  }

  void removeItem(String menuItemId) {
    state = CartState(
      items: state.items.where((i) => i.menuItemId != menuItemId).toList(),
    );
  }

  void applyCombo({
    required String comboId,
    required String comboName,
    required int comboPricePaise,
    required List<CartItem> comboItems,
  }) {
    state = CartState(
      comboId: comboId,
      comboName: comboName,
      comboPricePaise: comboPricePaise,
      comboItems: comboItems,
    );
  }

  void removeCombo() {
    state = CartState.empty;
  }

  void clear() {
    state = CartState.empty;
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);

/// Convenience selectors used by the bag badge + sticky checkout button.
final cartItemCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).totalItemCount;
});

final cartTotalPaiseProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).totalPaise;
});

/// Currently-selected fulfillment + payment for the cart sheet. Local UI
/// state (resets when the cart is cleared via clear()).
enum FulfillmentMode { dineIn, takeaway, tableService }

extension FulfillmentModeX on FulfillmentMode {
  String get rpcValue => switch (this) {
        FulfillmentMode.dineIn => 'dine_in',
        FulfillmentMode.takeaway => 'takeaway',
        FulfillmentMode.tableService => 'table_service',
      };

  String get label => switch (this) {
        FulfillmentMode.dineIn => 'Dine in',
        FulfillmentMode.takeaway => 'Takeaway',
        FulfillmentMode.tableService => 'Table service',
      };
}

final cartFulfillmentProvider =
    StateProvider<FulfillmentMode>((_) => FulfillmentMode.dineIn);

enum CartPaymentMethod { wallet, cash }

extension CartPaymentMethodX on CartPaymentMethod {
  String get rpcValue => switch (this) {
        CartPaymentMethod.wallet => 'wallet',
        CartPaymentMethod.cash => 'cash',
      };

  String get label => switch (this) {
        CartPaymentMethod.wallet => 'Wallet',
        CartPaymentMethod.cash => 'Pay at counter',
      };
}

final cartPaymentMethodProvider =
    StateProvider<CartPaymentMethod>((_) => CartPaymentMethod.wallet);
