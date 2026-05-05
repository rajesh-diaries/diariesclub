import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Cart line model — sealed hierarchy with three concrete types.
/// Each line has a stable `id` (used by the UI for stepper actions),
/// a server-priced `unitPricePaise`, and a `quantity`. Aggregations on
/// CartState use `linePaise = unitPricePaise * quantity`.
///
/// Module 2.5/2.6 follow-up: this replaces the prior "items XOR combo"
/// CartState. All three line types coexist in the same `lines[]` list.
sealed class CartLine {
  String get id;
  String get displayName;
  int get unitPricePaise;
  int get quantity;
  int get linePaise => unitPricePaise * quantity;
  CartLine copyWithQuantity(int q);
}

/// Coffee or FIT à-la-carte item from menu_items.
class MenuItemLine extends CartLine {
  @override
  final String id;
  final String menuItemId;
  final String name;
  final String brand; // 'coffee' | 'fit'
  @override
  final int unitPricePaise;
  @override
  final int quantity;
  final String? imageUrl;

  MenuItemLine({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.brand,
    required this.unitPricePaise,
    required this.quantity,
    this.imageUrl,
  });

  factory MenuItemLine.create({
    required String menuItemId,
    required String name,
    required String brand,
    required int unitPricePaise,
    required int quantity,
    String? imageUrl,
  }) =>
      MenuItemLine(
        id: 'menu:$menuItemId',
        menuItemId: menuItemId,
        name: name,
        brand: brand,
        unitPricePaise: unitPricePaise,
        quantity: quantity,
        imageUrl: imageUrl,
      );

  @override
  String get displayName => name;

  @override
  MenuItemLine copyWithQuantity(int q) => MenuItemLine(
        id: id,
        menuItemId: menuItemId,
        name: name,
        brand: brand,
        unitPricePaise: unitPricePaise,
        quantity: q,
        imageUrl: imageUrl,
      );
}

/// Pre-bundled combo (Coffee + FIT items at admin-set price). Combo line's
/// price is the combo.price_paise — server re-validates on order_place.
class ComboLine extends CartLine {
  @override
  final String id;
  final String comboId;
  final String name;
  @override
  final int unitPricePaise;
  @override
  final int quantity;
  final String? imageUrl;
  final List<String> includedItemNames; // for display

  ComboLine({
    required this.id,
    required this.comboId,
    required this.name,
    required this.unitPricePaise,
    required this.quantity,
    this.imageUrl,
    this.includedItemNames = const [],
  });

  factory ComboLine.create({
    required String comboId,
    required String name,
    required int unitPricePaise,
    required int quantity,
    String? imageUrl,
    List<String> includedItemNames = const [],
  }) =>
      ComboLine(
        id: 'combo:$comboId',
        comboId: comboId,
        name: name,
        unitPricePaise: unitPricePaise,
        quantity: quantity,
        imageUrl: imageUrl,
        includedItemNames: includedItemNames,
      );

  @override
  String get displayName => name;

  @override
  ComboLine copyWithQuantity(int q) => ComboLine(
        id: id,
        comboId: comboId,
        name: name,
        unitPricePaise: unitPricePaise,
        quantity: q,
        imageUrl: imageUrl,
        includedItemNames: includedItemNames,
      );
}

/// Customer-built FIT meal. Each FIT line carries the selections JSONB
/// for the order. Different selections create different lines (we DON'T
/// merge by template_id alone). Edit re-opens the builder pre-filled.
class FitMealLine extends CartLine {
  @override
  final String id; // unique per build (uuid v4) so different builds don't merge
  final String templateId;
  final String templateName;
  @override
  final int unitPricePaise; // base + total upcharge from server
  @override
  final int quantity;
  final Map<String, dynamic> selectionsJsonb;
  final List<String> selectionsSummary; // pre-rendered for display
  final String? imageUrl;

  FitMealLine({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.unitPricePaise,
    required this.quantity,
    required this.selectionsJsonb,
    required this.selectionsSummary,
    this.imageUrl,
  });

  factory FitMealLine.create({
    required String templateId,
    required String templateName,
    required int unitPricePaise,
    required int quantity,
    required Map<String, dynamic> selectionsJsonb,
    required List<String> selectionsSummary,
    String? imageUrl,
  }) =>
      FitMealLine(
        id: 'fit:${const Uuid().v4()}',
        templateId: templateId,
        templateName: templateName,
        unitPricePaise: unitPricePaise,
        quantity: quantity,
        selectionsJsonb: selectionsJsonb,
        selectionsSummary: selectionsSummary,
        imageUrl: imageUrl,
      );

  @override
  String get displayName => templateName;

  @override
  FitMealLine copyWithQuantity(int q) => FitMealLine(
        id: id,
        templateId: templateId,
        templateName: templateName,
        unitPricePaise: unitPricePaise,
        quantity: q,
        selectionsJsonb: selectionsJsonb,
        selectionsSummary: selectionsSummary,
        imageUrl: imageUrl,
      );
}

/// Snapshot of the bag. Heterogeneous list — all line types coexist.
class CartState {
  final List<CartLine> lines;
  const CartState({this.lines = const []});

  static const empty = CartState();

  bool get isEmpty => lines.isEmpty;
  int get totalItemCount => lines.fold(0, (s, l) => s + l.quantity);
  int get totalPaise => lines.fold(0, (s, l) => s + l.linePaise);
  int get menuItemLineCount => lines.whereType<MenuItemLine>().length;
  int get comboLineCount => lines.whereType<ComboLine>().length;
  int get fitMealLineCount => lines.whereType<FitMealLine>().length;
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState.empty);

  // ── Add helpers ──────────────────────────────────────────────────────────

  /// Add or merge a menu item by menu_item_id.
  void addMenuItem(MenuItemLine line) {
    final next = [...state.lines];
    final idx = next.indexWhere(
      (l) => l is MenuItemLine && l.menuItemId == line.menuItemId,
    );
    if (idx >= 0) {
      final existing = next[idx] as MenuItemLine;
      next[idx] = existing.copyWithQuantity(existing.quantity + line.quantity);
    } else {
      next.add(line);
    }
    state = CartState(lines: next);
  }

  /// Add or merge a combo by combo_id.
  void addCombo(ComboLine line) {
    final next = [...state.lines];
    final idx = next.indexWhere(
      (l) => l is ComboLine && l.comboId == line.comboId,
    );
    if (idx >= 0) {
      final existing = next[idx] as ComboLine;
      next[idx] = existing.copyWithQuantity(existing.quantity + line.quantity);
    } else {
      next.add(line);
    }
    state = CartState(lines: next);
  }

  /// Append a FIT meal line — does NOT merge (different selections live as
  /// distinct lines). To increment, use changeQuantityById.
  void addFitMeal(FitMealLine line) {
    state = CartState(lines: [...state.lines, line]);
  }

  // ── Quantity / removal ───────────────────────────────────────────────────

  /// Change quantity of any line by its line.id. Removes the line at qty=0.
  void changeQuantityById(String lineId, int delta) {
    final next = <CartLine>[];
    for (final l in state.lines) {
      if (l.id != lineId) {
        next.add(l);
        continue;
      }
      final newQty = l.quantity + delta;
      if (newQty > 0) next.add(l.copyWithQuantity(newQty));
    }
    state = CartState(lines: next);
  }

  /// Backward-compat helper: change quantity by menu_item_id (used by
  /// QuantityStepper on menu cards). Falls through to changeQuantityById
  /// once the line.id is resolved.
  void changeQuantity(String menuItemId, int delta) {
    final line = state.lines.whereType<MenuItemLine>().where(
      (l) => l.menuItemId == menuItemId,
    );
    if (line.isEmpty) return;
    changeQuantityById(line.first.id, delta);
  }

  void removeLineById(String lineId) {
    state = CartState(
      lines: state.lines.where((l) => l.id != lineId).toList(),
    );
  }

  void clear() {
    state = CartState.empty;
  }

  // ── Backward-compat shims ────────────────────────────────────────────────
  // Old callers used addItem(CartItem). Bridge to the new API so the
  // refactor doesn't fan out to every menu_item_card.dart in one PR.

  void addItem(CartItem legacy) {
    addMenuItem(MenuItemLine.create(
      menuItemId: legacy.menuItemId,
      name: legacy.name,
      brand: legacy.brand,
      unitPricePaise: legacy.unitPricePaise,
      quantity: legacy.quantity,
      imageUrl: legacy.imageUrl,
    ));
  }

  /// Old callers used applyCombo() to replace the cart with a combo. New
  /// behaviour: add the combo as a line alongside any existing lines.
  void applyCombo({
    required String comboId,
    required String comboName,
    required int comboPricePaise,
    required List<String> includedItemNames,
    String? imageUrl,
  }) {
    addCombo(ComboLine.create(
      comboId: comboId,
      name: comboName,
      unitPricePaise: comboPricePaise,
      quantity: 1,
      imageUrl: imageUrl,
      includedItemNames: includedItemNames,
    ));
  }

  /// Old callers used removeCombo() (the combo XOR mode). New behaviour:
  /// remove any combo lines from the cart.
  void removeCombo() {
    state = CartState(
      lines: state.lines.where((l) => l is! ComboLine).toList(),
    );
  }
}

/// Legacy CartItem shim — kept so the older menu cards keep compiling.
/// New code should construct MenuItemLine directly.
class CartItem {
  final String menuItemId;
  final String name;
  final String brand;
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

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);

final cartItemCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).totalItemCount,
);

final cartTotalPaiseProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).totalPaise,
);

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
