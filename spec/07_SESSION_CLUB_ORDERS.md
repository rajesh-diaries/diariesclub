# Session 7 — Club Tab (Coffee + FIT + Combos + Workshops)

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-6 + 5b complete.

---

## Session Header

```
I am building Diaries Club. Database, RPCs, foundation, auth, home, profile,
and gamification all done. This session: build the Club tab — Coffee Diaries
menu, FIT Diaries menu, Combos, Workshops, cart, checkout flow, and order tracking.

Estimated time: 5-6 hours
What to build:
  - Club tab with 4 sub-tabs (Coffee / FIT / Combos / Workshops)
  - Menu list per brand (Coffee + FIT)
  - Combo browse + add to cart
  - Single-bag cart with visual brand grouping
  - Real-time availability (sold-out items show disabled)
  - Checkout flow with payment + GST + coins preview
  - "While you wait" food prompt during active session (2nd visit onwards)
  - Order tracking screen (preparing → ready → served)
  - Workshop browse + register flow
  - Workshop detail screen with capacity/waitlist
  - Workshop cancellation flow

What NOT to build:
  - Kitchen Display System (Session 10 - Staff)
  - Order receipt PDF generation (Session 13 - Edge Functions)
  - Birthday packages (Session 9)

Output expected:
  - Functional Club tab in lib/features/club/
  - Cart persists across tab switches
  - Order placement working end-to-end via order_place RPC
  - Workshop register working via workshop_register RPC

Acceptance:
  - Browse Coffee menu, add 2 items → bag shows 2 items grouped under "Coffee"
  - Switch to FIT tab, add 1 item → bag shows 3 items, FIT items in separate group
  - Apply combo → bag replaces with combo, shows discount
  - Sold-out item disabled in UI, attempting to order returns error
  - Place order via wallet → status: preparing → ready → served (status updates via Realtime)
  - Register for workshop with valid balance → spot decrements atomically
  - Concurrent register on last spot → one succeeds, other gets workshop_full error
```

---

## 1. Club Tab Architecture

### 1.1 Top tabs

Per locked decision, four tabs at the top: **Coffee | FIT | Combos | Workshops**

```
┌─────────────────────────────────────┐
│ APP BAR (Club)              [bag]   │
├─────────────────────────────────────┤
│ Coffee | FIT | Combos | Workshops   │ ← TabBar with indicator
├─────────────────────────────────────┤
│                                     │
│   Tab content (scrolls)             │
│                                     │
├─────────────────────────────────────┤
│ Bottom nav (Club active)            │
└─────────────────────────────────────┘
```

The bag icon top-right shows badge count of items in cart. Tap → opens cart bottom sheet (or navigates to /club/cart on small screens).

### 1.2 Tab structure

```dart
class ClubScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext c) {
    final cartCount = ref.watch(cartItemCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Club"),
        actions: [
          if (cartCount > 0)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: PhosphorIcon(PhosphorIcons.shoppingBag()),
                  onPressed: () => _showCart(c),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.gold, shape: BoxShape.circle,
                    ),
                    child: Text("$cartCount",
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Coffee"),
            Tab(text: "FIT"),
            Tab(text: "Combos"),
            Tab(text: "Workshops"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          CoffeeMenuTab(),
          FitMenuTab(),
          CombosTab(),
          WorkshopsTab(),
        ],
      ),
    );
  }

  void _showCart(BuildContext c) =>
    showModalBottomSheet(
      context: c, isScrollControlled: true, useSafeArea: true,
      builder: (_) => const CartSheet(),
    );
}
```

---

## 2. Cart State Management

### 2.1 Cart provider — single source of truth

```dart
@riverpod
class Cart extends _$Cart {
  @override
  CartState build() => const CartState.empty();

  /// Add menu item; if already in cart, increments quantity
  void addItem(MenuItem item) {
    state = state.copyWith(items: [
      ...state.items,
      CartItem.fromMenuItem(item),
    ]).consolidated();
  }

  void removeItem(String menuItemId) {
    state = state.copyWith(
      items: state.items.where((i) => i.menuItemId != menuItemId).toList(),
    );
  }

  void updateQuantity(String menuItemId, int delta) {
    final updated = state.items.map((i) {
      if (i.menuItemId != menuItemId) return i;
      final newQty = i.quantity + delta;
      return i.copyWith(quantity: newQty);
    }).where((i) => i.quantity > 0).toList();
    state = state.copyWith(items: updated);
  }

  void applyCombo(Combo combo) {
    // Combo replaces existing cart items per spec — combo defines its own bundle
    state = state.copyWith(
      items: combo.includedMenuItemIds.map((id) {
        // Look up actual items from cache; this is illustrative
        return CartItem(menuItemId: id, quantity: 1, /*...*/ );
      }).toList(),
      comboId: combo.id,
      comboPrice: combo.pricePaise,
    );
  }

  void removeCombo() {
    state = state.copyWith(comboId: null, comboPrice: null);
  }

  void clear() => state = const CartState.empty();
}

@freezed
class CartState with _$CartState {
  const factory CartState({
    @Default([]) List<CartItem> items,
    String? comboId,
    int? comboPrice,
  }) = _CartState;

  const CartState._();

  factory CartState.empty() => const CartState();

  int get totalItemCount => items.fold(0, (sum, i) => sum + i.quantity);
  int get subtotalPaise => comboPrice ?? items.fold(0, (sum, i) => sum + i.unitPricePaise * i.quantity);
}

@freezed
class CartItem with _$CartItem {
  const factory CartItem({
    required String menuItemId,
    required String name,
    required String brand,         // 'coffee' | 'fit'
    required int unitPricePaise,
    required int quantity,
  }) = _CartItem;
}

@riverpod
int cartItemCount(CartItemCountRef ref) =>
  ref.watch(cartProvider).totalItemCount;
```

### 2.2 Persistence

Cart is NOT persisted across app kills. Rationale: order context (where you are, who you're ordering for) is moment-dependent. If app is killed, fresh cart is fine.

If a user wants longer persistence later, can add SharedPreferences serialization.

---

## 3. Coffee Menu Tab — `lib/features/club/coffee_menu_tab.dart`

### 3.1 Layout

```
┌─────────────────────────────────────┐
│ HERO IMAGE STRIP (~140 high)        │
│ "Coffee Diaries" branding           │
├─────────────────────────────────────┤
│ CATEGORY PILLS (horizontal scroll)  │
│ All | Espresso | Tea | Cold | Bites │
├─────────────────────────────────────┤
│ MENU ITEM LIST (vertical)           │
│ ┌──────┬──────────────────────────┐ │
│ │image │ Cappuccino       ₹180   │ │
│ │      │ Single shot espresso... │ │
│ │      │              [Add +]    │ │
│ └──────┴──────────────────────────┘ │
│ ┌──────┬──────────────────────────┐ │
│ │      │ Croissant       ₹160    │ │
│ │      │ Buttery, flaky   SOLD   │ │
│ │      │                  OUT    │ │
│ └──────┴──────────────────────────┘ │
│ ...                                 │
└─────────────────────────────────────┘
```

### 3.2 Menu item provider with realtime availability

```dart
@riverpod
Stream<List<MenuItem>> coffeeMenuItems(CoffeeMenuItemsRef ref) async* {
  final venueId = await ref.watch(currentVenueIdProvider.future);

  await for (final rows in Supabase.instance.client
      .from('menu_items')
      .stream(primaryKey: ['id'])
      .order('sort_order')) {

    // Filter to coffee menu items
    final coffeeItems = rows.where((r) async {
      final menu = await Supabase.instance.client
        .from('menus')
        .select('brand')
        .eq('id', r['menu_id'])
        .single();
      return menu['brand'] == 'coffee';
    });

    yield rows
      .map((r) => MenuItem.fromJson(r))
      .where((i) => i.brand == 'coffee')
      .toList();
  }
}
```

**Better approach:** create a view in DB:

```sql
CREATE OR REPLACE VIEW menu_items_with_brand AS
SELECT mi.*, m.brand
FROM menu_items mi
JOIN menus m ON m.id = mi.menu_id;
```

Then stream from view:
```dart
.from('menu_items_with_brand')
.stream(primaryKey: ['id'])
.eq('brand', 'coffee')
```

### 3.3 Menu item card

```dart
class MenuItemCard extends ConsumerWidget {
  final MenuItem item;
  const MenuItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final inCart = cart.items.firstWhereOrNull((i) => i.menuItemId == item.id);
    final disabled = !item.isAvailable;

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(c).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80, height: 80,
                  child: CachedNetworkImage(
                    imageUrl: item.imageUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppColors.lightBorder),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.coffeeBrown.withOpacity(0.2),
                      child: PhosphorIcon(PhosphorIcons.coffee(), color: AppColors.coffeeBrown),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: AppTextStyles.bodyLarge(c)),
                    if (item.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description!,
                        style: AppTextStyles.caption(c),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          Money.fromPaise(item.pricePaise),
                          style: AppTextStyles.bodyLarge(c, color: AppColors.navy),
                        ),
                        const Spacer(),
                        if (disabled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.adminRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text("Sold out",
                              style: AppTextStyles.caption(c, color: AppColors.adminRed)),
                          )
                        else if (inCart != null)
                          _QuantityStepper(item: item, currentQty: inCart.quantity)
                        else
                          OutlinedButton(
                            onPressed: () {
                              ref.read(cartProvider.notifier).addItem(item);
                              HapticFeedback.lightImpact();
                            },
                            child: const Text("Add"),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 3.4 Sold-out behavior

When admin marks `menu_items.is_available = false`:
- Realtime stream pushes update → all client UIs update within ~2s
- "Sold out" badge appears, opacity reduced, "Add" button disabled
- If item already in someone's cart at moment of sold-out flip:
  - Cart shows yellow warning banner: "Croissant just sold out — tap to remove"
  - Tapping removes it; checkout button is blocked until removed
  - Server-side `order_place` will also reject with `menu_item_unavailable` if not removed

---

## 4. FIT Menu Tab — `lib/features/club/fit_menu_tab.dart`

Identical structure to Coffee tab, with:
- Brand color: AppColors.fitGreen
- Filter category pills: All | Bowls | Wraps | Sides | Drinks
- Hero strip says "FIT Diaries — Healthy + Tasty"
- Menu items filtered by `brand = 'fit'`

The component pattern is identical — extract a `_BrandMenuTab` parameterised by brand:

```dart
class _BrandMenuTab extends ConsumerWidget {
  final String brand;       // 'coffee' | 'fit'
  final List<String> categories;

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final items = ref.watch(brand == 'coffee'
      ? coffeeMenuItemsProvider
      : fitMenuItemsProvider);
    // ...
  }
}
```

---

## 5. Combos Tab — `lib/features/club/combos_tab.dart`

### 5.1 Layout

```
┌─────────────────────────────────────┐
│ HEADER                              │
│ "Better together"                   │
│ "Bundle deals across Coffee + FIT"  │
├─────────────────────────────────────┤
│ COMBO CARD 1                        │
│ ┌─────────────────────────────────┐ │
│ │ [hero image]                    │ │
│ │ Play + Café  ₹650               │ │
│ │ ₹820 if bought separately       │ │
│ │ Save ₹170                       │ │
│ │ Includes:                       │ │
│ │  • 1hr play session             │ │
│ │  • Cappuccino                   │ │
│ │  • Croissant                    │ │
│ │ [Add combo] PRIMARY             │ │
│ └─────────────────────────────────┘ │
│ COMBO CARD 2 (Family Saturday)      │
│ ...                                 │
└─────────────────────────────────────┘
```

### 5.2 Combo card

```dart
class ComboCard extends ConsumerWidget {
  final Combo combo;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final isInCart = cart.comboId == combo.id;
    final separatePrice = _calculateSeparatePrice(combo);
    final saving = separatePrice - combo.pricePaise;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [Color(0xFFFFF6E5), Color(0xFFFEFCF8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 16/9,
              child: CachedNetworkImage(
                imageUrl: combo.coverImageUrl ?? '',
                fit: BoxFit.cover,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(combo.name, style: AppTextStyles.h3(c))),
                    Text(Money.fromPaise(combo.pricePaise),
                      style: AppTextStyles.h2(c, color: AppColors.navy)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      Money.fromPaise(separatePrice),
                      style: AppTextStyles.caption(c).copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.activeGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        "Save ${Money.fromPaise(saving)}",
                        style: AppTextStyles.caption(c, color: AppColors.activeGreen),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...combo.inclusions.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      PhosphorIcon(PhosphorIcons.check(), size: 16, color: AppColors.activeGreen),
                      const SizedBox(width: 8),
                      Text(_formatInclusion(e), style: AppTextStyles.caption(c)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),

                if (isInCart)
                  OutlinedButton(
                    onPressed: () => ref.read(cartProvider.notifier).removeCombo(),
                    child: const Text("Remove from bag"),
                  )
                else
                  PrimaryButton(
                    label: "Add combo to bag",
                    onPressed: () => _addCombo(c, ref),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addCombo(BuildContext c, WidgetRef ref) {
    final cart = ref.read(cartProvider);
    if (cart.items.isNotEmpty) {
      // Confirm replacement
      showDialog(context: c, builder: (_) => AlertDialog(
        title: const Text("Replace bag?"),
        content: const Text("Adding a combo will replace your current items. Continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              ref.read(cartProvider.notifier).applyCombo(combo);
              HapticFeedback.mediumImpact();
            },
            child: const Text("Replace"),
          ),
        ],
      ));
    } else {
      ref.read(cartProvider.notifier).applyCombo(combo);
      HapticFeedback.mediumImpact();
    }
  }
}
```

---

## 6. Cart Bottom Sheet — `lib/features/club/widgets/cart_sheet.dart`

### 6.1 Layout

```
┌─────────────────────────────────────┐
│         ▔▔                          │
│ Your bag                       [✕]  │
│ 3 items                             │
├─────────────────────────────────────┤
│ COFFEE                              │
│   Cappuccino  x2          ₹360 [-+] │
│   Croissant   x1          ₹160 [-+] │
├─────────────────────────────────────┤
│ FIT                                 │
│   Quinoa Bowl x1          ₹280 [-+] │
├─────────────────────────────────────┤
│ Subtotal                    ₹800    │
│ GST (5%)                     ₹40    │
│ Total                       ₹840    │
│ +56 Diaries Coins back              │
├─────────────────────────────────────┤
│ FULFILLMENT                         │
│ ○ Dine in (table service)           │
│ ○ Takeaway counter                  │
├─────────────────────────────────────┤
│ PAYMENT                             │
│ ○ Wallet (₹1,250 available)         │
│ ○ Pay at counter                    │
├─────────────────────────────────────┤
│ STICKY BOTTOM                       │
│ [Place order ₹840]   PRIMARY         │
└─────────────────────────────────────┘
```

### 6.2 Brand grouping logic

```dart
class CartSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.items.isEmpty && cart.comboId == null) {
      return _EmptyCart();
    }

    if (cart.comboId != null) {
      return _ComboCart(combo: ref.watch(comboByIdProvider(cart.comboId!)).value!);
    }

    // Group items by brand
    final byBrand = groupBy(cart.items, (i) => i.brand);
    final coffeeItems = byBrand['coffee'] ?? [];
    final fitItems = byBrand['fit'] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(c).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _DragHandle(),
          _CartHeader(itemCount: cart.totalItemCount),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (coffeeItems.isNotEmpty)
                    _BrandSection(brand: 'coffee', items: coffeeItems),
                  if (fitItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _BrandSection(brand: 'fit', items: fitItems),
                  ],
                  const SizedBox(height: 24),
                  _OrderSummary(),
                  const SizedBox(height: 16),
                  _FulfillmentSelector(),
                  const SizedBox(height: 16),
                  _PaymentSelector(),
                  const SizedBox(height: 100), // bottom padding
                ],
              ),
            ),
          ),
          _StickyCheckoutBar(),
        ],
      ),
    );
  }
}

class _BrandSection extends StatelessWidget {
  final String brand;
  final List<CartItem> items;

  @override
  Widget build(BuildContext c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brandTintColor(brand),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(_brandIcon(brand), size: 18, color: _brandColor(brand)),
              const SizedBox(width: 8),
              Text(
                _brandLabel(brand),
                style: AppTextStyles.caption(c, color: _brandColor(brand))
                  .copyWith(letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((i) => _CartLine(item: i)),
        ],
      ),
    );
  }
}
```

### 6.3 GST + coins preview (server-validated, but we calculate display version)

```dart
class _OrderSummary extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final config = ref.watch(venueConfigProvider).valueOrNull;
    final paymentMethod = ref.watch(checkoutPaymentMethodProvider);

    final subtotal = cart.subtotalPaise;
    final gst = (subtotal * 0.05).round();
    final total = subtotal + gst;
    final coins = paymentMethod == 'wallet'
      ? (subtotal * (config?.cashbackPercent ?? 7) / 100).floor()
      : 0;

    return Column(
      children: [
        _SummaryRow(label: "Subtotal", value: Money.fromPaise(subtotal)),
        _SummaryRow(label: "GST (5%)", value: Money.fromPaise(gst)),
        const Divider(),
        _SummaryRow(
          label: "Total",
          value: Money.fromPaise(total),
          valueStyle: AppTextStyles.h3(c, color: AppColors.navy),
        ),
        if (coins > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("+$coins Diaries Coins back",
                  style: AppTextStyles.caption(c, color: AppColors.gold)),
                PhosphorIcon(PhosphorIcons.star(PhosphorIconsStyle.fill),
                  size: 14, color: AppColors.gold),
              ],
            ),
          ),
      ],
    );
  }
}
```

### 6.4 Place order

```dart
Future<void> _placeOrder(BuildContext c, WidgetRef ref) async {
  setState(() => _isLoading = true);
  final idempotencyKey = const Uuid().v4();

  final cart = ref.read(cartProvider);
  final fulfillment = ref.read(checkoutFulfillmentProvider);
  final paymentMethod = ref.read(checkoutPaymentMethodProvider);

  // Server-side check: if any item is unavailable, RPC fails
  try {
    final result = await Supabase.instance.client.rpc('order_place', params: {
      'p_venue_id': await ref.read(currentVenueIdProvider.future),
      'p_family_id': Supabase.instance.client.auth.currentUser!.id,
      'p_items': cart.items.map((i) => {
        'menu_item_id': i.menuItemId,
        'quantity': i.quantity,
      }).toList(),
      'p_combo_id': cart.comboId,
      'p_fulfillment_mode': fulfillment,
      'p_payment_method': paymentMethod,
      'p_idempotency_key': idempotencyKey,
    });

    final orderId = result['order_id'];

    // Clear cart, navigate to tracking
    ref.read(cartProvider.notifier).clear();

    if (mounted) {
      Navigator.pop(c); // close cart sheet
      context.push('/club/order/$orderId');
    }
  } on PostgrestException catch (e) {
    setState(() => _isLoading = false);

    if (e.message.contains('insufficient_balance')) {
      _showInsufficientBalance(c, ref);
    } else if (e.message.contains('menu_item_unavailable')) {
      _showError(c, "An item just sold out. Please remove it from your bag.");
    } else if (e.message.contains('invalid_combo')) {
      _showError(c, "That combo isn't available right now.");
    } else {
      _showError(c, "Couldn't place order. Please try again.");
    }
  }
}
```

---

## 7. Order Tracking Screen — `lib/features/club/order_tracking_screen.dart`

### 7.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Order #1234                  │
├─────────────────────────────────────┤
│ STATUS HERO                         │
│                                     │
│       [animated icon]               │
│                                     │
│       PREPARING YOUR ORDER          │
│       Estimated time: 8 min         │
├─────────────────────────────────────┤
│ STATUS TIMELINE                     │
│ ✓ Order received                    │
│ ⏳ Preparing your food              │ ← current
│ ○ Ready for pickup                  │
│ ○ Served                            │
├─────────────────────────────────────┤
│ ORDER DETAILS                       │
│ Cappuccino x2            ₹360       │
│ Croissant x1             ₹160       │
│ Quinoa Bowl x1           ₹280       │
│ Subtotal                 ₹800       │
│ GST                       ₹40       │
│ Total                    ₹840       │
│                                     │
│ Paid via wallet                     │
│ +56 Diaries Coins earned            │
├─────────────────────────────────────┤
│ FULFILLMENT                         │
│ Dine in (table service)             │
├─────────────────────────────────────┤
│ NEED HELP?                          │
│ [Talk to staff via WhatsApp]        │
└─────────────────────────────────────┘
```

### 7.2 Realtime status updates

```dart
@riverpod
Stream<Order> orderStream(OrderStreamRef ref, String orderId) async* {
  await for (final rows in Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('id', orderId)
      .limit(1)) {
    if (rows.isEmpty) continue;
    yield Order.fromJson(rows.first);
  }
}
```

Status states (per Session 1 schema):
| Status | UX |
|---|---|
| `pending` | Spinner, "Order received" |
| `preparing` | Pulsing icon, "Preparing your food" |
| `ready` | Animation pulse + push notification, "Ready for pickup!" |
| `served` | Checkmark, "Enjoyed your order?" |
| `cancelled` | Red icon, "Order cancelled. Refunded to wallet." |

When status flips to `ready`, fire local notification (in case parent isn't looking at app).

### 7.3 Status timeline component

```dart
class OrderStatusTimeline extends StatelessWidget {
  final String currentStatus;

  @override
  Widget build(BuildContext c) {
    final statuses = ['pending', 'preparing', 'ready', 'served'];
    final currentIndex = statuses.indexOf(currentStatus);

    return Column(
      children: statuses.asMap().entries.map((entry) {
        final isPast = entry.key < currentIndex;
        final isCurrent = entry.key == currentIndex;
        return _TimelineStep(
          label: _stepLabel(entry.value),
          isPast: isPast,
          isCurrent: isCurrent,
          isLast: entry.key == statuses.length - 1,
        );
      }).toList(),
    );
  }
}
```

---

## 8. While-You-Wait Food Prompt

Per locked decision (Cross-3): from 2nd visit onwards, show in-app card during active session inviting Coffee/FIT order.

### 8.1 Trigger

- Shown on Home tab during active session state
- Visible only after the family has at least 2 completed sessions (i.e., 2nd visit or later)
- Not shown during grace state (don't push when timer is yellow)
- Dismissible per session (tracked in SharedPreferences with key `wyw_dismissed_<session_id>`)

### 8.2 Layout

```
┌─────────────────────────────────────┐
│ ☕ While Aarav plays...             │
│                                     │
│ Order Coffee Diaries or FIT to your │
│ table. We'll bring it right over.   │
│                                     │
│ [Browse menu →]   [Not now]         │
└─────────────────────────────────────┘
```

Tap "Browse menu" → Club tab opens, with a hint banner: "Table service mode" pre-selected for fulfillment, the tab opens to Coffee Diaries by default.

### 8.3 Implementation

```dart
@riverpod
Future<bool> shouldShowWhileYouWait(ShouldShowWhileYouWaitRef ref) async {
  final familyId = Supabase.instance.client.auth.currentUser?.id;
  if (familyId == null) return false;

  // Check completed sessions count
  final count = await Supabase.instance.client
    .from('sessions')
    .select('id', const FetchOptions(count: CountOption.exact))
    .eq('family_id', familyId)
    .eq('status', 'completed');

  if ((count.count ?? 0) < 2) return false;

  // Check current dismissal
  final activeSession = ref.watch(activeSessionProvider).valueOrNull;
  if (activeSession == null) return false;

  final prefs = await SharedPreferences.getInstance();
  return !prefs.getBool('wyw_dismissed_${activeSession.id}') ?? true;
}
```

---

## 9. Workshops Tab — `lib/features/club/workshops_tab.dart`

### 9.1 Layout

```
┌─────────────────────────────────────┐
│ HEADER                              │
│ "Workshops"                         │
│ "Themed sessions earn extra XP"     │
├─────────────────────────────────────┤
│ FILTER PILLS                        │
│ All | This week | Next week | Past  │
├─────────────────────────────────────┤
│ WORKSHOP CARD                       │
│ ┌─────────────────────────────────┐ │
│ │ [hero image]                    │ │
│ │ Sat Mar 30, 4 PM       [Curious]│ │
│ │ Mini Scientists                 │ │
│ │ Ages 5-9 · 90 min · ₹500        │ │
│ │ +100 XP to Gerry                │ │
│ │ 3 of 8 spots left               │ │
│ │ [Register →]                    │ │
│ └─────────────────────────────────┘ │
│ ...                                 │
└─────────────────────────────────────┘
```

### 9.2 Workshop card

```dart
class WorkshopCard extends ConsumerWidget {
  final Workshop workshop;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final spotsRemaining = workshop.spotsRemaining;
    final isFull = spotsRemaining == 0;
    final spotsLowWarning = spotsRemaining > 0 && spotsRemaining <= 3;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AspectRatio(
                  aspectRatio: 16/9,
                  child: CachedNetworkImage(
                    imageUrl: workshop.coverImageUrl ?? '',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Trait pill top-right
              if (workshop.primaryTrait != null)
                Positioned(
                  top: 12, right: 12,
                  child: _TraitPill(trait: workshop.primaryTrait!),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + time
                Text(
                  _formatScheduledAt(workshop.scheduledAt),
                  style: AppTextStyles.caption(c),
                ),
                const SizedBox(height: 4),
                Text(workshop.title, style: AppTextStyles.h3(c)),
                const SizedBox(height: 8),
                Text(
                  "Ages ${workshop.ageGroupMin}-${workshop.ageGroupMax} • "
                  "${workshop.durationMinutes} min • "
                  "${Money.fromPaise(workshop.pricePaise)}",
                  style: AppTextStyles.caption(c),
                ),
                const SizedBox(height: 8),
                if (workshop.primaryTrait != null)
                  Text(
                    "+${workshop.xpAward} XP to ${_heroName(workshop.primaryTrait!)}",
                    style: AppTextStyles.caption(c, color: _traitColor(workshop.primaryTrait!)),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isFull)
                      Text("Workshop full",
                        style: AppTextStyles.caption(c, color: AppColors.adminRed))
                    else if (spotsLowWarning)
                      Text(
                        "$spotsRemaining of ${workshop.capacity} spots left",
                        style: AppTextStyles.caption(c, color: AppColors.warningYellow),
                      )
                    else
                      Text(
                        "$spotsRemaining of ${workshop.capacity} spots left",
                        style: AppTextStyles.caption(c),
                      ),
                    PrimaryButton(
                      label: isFull ? "Full" : "Register",
                      onPressed: isFull
                        ? null
                        : () => context.push('/club/workshop/${workshop.id}'),
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 10. Workshop Detail Screen — `lib/features/club/workshop_detail_screen.dart`

### 10.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back]                              │
├─────────────────────────────────────┤
│ HERO IMAGE (full width)             │
│                                     │
├─────────────────────────────────────┤
│ Sat Mar 30, 4 PM         [Curious]  │
│ Mini Scientists                     │
│ Ages 5-9 · 90 min · ₹500            │
├─────────────────────────────────────┤
│ ABOUT                               │
│ Description text...                 │
│                                     │
│ WHAT TO EXPECT                      │
│ • Hands-on experiments              │
│ • All materials provided            │
│ • Take-home project                 │
├─────────────────────────────────────┤
│ XP REWARD                           │
│ +100 XP to Gerry (Curious trait)    │
│                                     │
│ AVAILABILITY                        │
│ 3 of 8 spots remaining              │
├─────────────────────────────────────┤
│ CHILD SELECTION                     │
│ [avatar row] Pick a child           │
├─────────────────────────────────────┤
│ STICKY BOTTOM                       │
│ [Register for ₹500]   PRIMARY        │
└─────────────────────────────────────┘
```

### 10.2 Register flow

```dart
Future<void> _register() async {
  if (_selectedChildId == null) return;
  setState(() => _isLoading = true);

  final idempotencyKey = const Uuid().v4();

  try {
    final result = await Supabase.instance.client.rpc('workshop_register', params: {
      'p_workshop_id': widget.workshopId,
      'p_family_id': Supabase.instance.client.auth.currentUser!.id,
      'p_child_id': _selectedChildId,
      'p_payment_method': _paymentMethod,
      'p_idempotency_key': idempotencyKey,
    });

    if (mounted) {
      Navigator.pop(context);
      _showSuccess("Registered! See you on March 30 at 4 PM.");
    }
  } on PostgrestException catch (e) {
    setState(() => _isLoading = false);

    if (e.message.contains('workshop_full')) {
      _showError("Sorry, that just filled up. Try another?");
    } else if (e.message.contains('insufficient_balance')) {
      _showInsufficientBalance();
    } else {
      _showError("Couldn't register. Please try again.");
    }
  }
}
```

---

## 11. Workshop Cancellation

From Profile → Past workshops → tap upcoming workshop → cancel button.

### 11.1 Cancel logic

```dart
Future<void> _cancelRegistration() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Cancel registration?"),
      content: const Text(
        "Your spot will be freed up and you'll be refunded ₹500 to your wallet."
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Keep it")),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Cancel")),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    await Supabase.instance.client.rpc('workshop_cancel', params: {
      'p_registration_id': widget.registrationId,
      'p_reason': 'user_cancelled',
    });
    _showSuccess("Registration cancelled. Refund applied.");
  } catch (e) {
    _showError("Couldn't cancel. Please try again.");
  }
}
```

---

## 12. Files to Create

```
lib/
└── features/
    └── club/
        ├── club_screen.dart
        ├── coffee_menu_tab.dart
        ├── fit_menu_tab.dart
        ├── combos_tab.dart
        ├── workshops_tab.dart
        ├── workshop_detail_screen.dart
        ├── order_tracking_screen.dart
        ├── widgets/
        │   ├── menu_item_card.dart
        │   ├── quantity_stepper.dart
        │   ├── combo_card.dart
        │   ├── workshop_card.dart
        │   ├── trait_pill.dart
        │   ├── cart_sheet.dart
        │   ├── brand_section.dart
        │   ├── cart_line.dart
        │   ├── order_summary.dart
        │   ├── fulfillment_selector.dart
        │   ├── payment_selector.dart
        │   ├── while_you_wait_card.dart
        │   └── order_status_timeline.dart
        └── providers/
            ├── cart_provider.dart
            ├── menu_items_provider.dart
            ├── combos_provider.dart
            ├── workshops_provider.dart
            ├── order_stream_provider.dart
            └── while_you_wait_provider.dart
```

---

## 13. Acceptance Tests

```
TEST 1 — Browse Coffee menu
  1. Tap Club tab → defaults to Coffee
  2. Menu items load via Realtime
  3. Tap "Cappuccino" "Add" → cart count = 1
  4. Bag icon shows badge "1"

TEST 2 — Mix brands in cart
  1. Add Cappuccino (Coffee) → cart count 1
  2. Switch to FIT tab, add Quinoa Bowl → cart count 2
  3. Open cart sheet
  4. See "COFFEE" section with Cappuccino, "FIT" section with Quinoa Bowl
  5. Brand sections visually distinct (different background tints)

TEST 3 — Combo replaces cart
  1. Cart has 2 items
  2. Switch to Combos, tap "Play + Café" combo → "Add"
  3. Confirm dialog: "Replace bag?"
  4. Confirm → cart now shows combo only
  5. Subtotal reflects combo price (not separate items)

TEST 4 — Sold out item
  1. In admin, mark Croissant is_available = false
  2. Coffee menu updates within 5s — Croissant shows "Sold out", grayed
  3. "Add" button disabled
  4. Try to bypass via direct RPC → returns menu_item_unavailable

TEST 5 — Place order via wallet
  1. Cart has items, wallet sufficient
  2. Select dine in + wallet
  3. Tap "Place order ₹840"
  4. RPC succeeds, navigates to /club/order/:id
  5. Status shows "preparing"
  6. wallet_transactions row created (order_debit), balance updated
  7. coins_earned credited (+56)

TEST 6 — Order status updates via Realtime
  1. On order tracking screen
  2. In DB, update orders.status = 'ready'
  3. Within 5s, screen status flips
  4. Local notification fires "Your order is ready!"

TEST 7 — Insufficient balance
  1. Cart total > wallet balance
  2. Tap place order with wallet → RPC raises insufficient_balance
  3. Show top-up sheet with required amount preselected

TEST 8 — While-you-wait card
  1. Family has ≥2 completed sessions
  2. Start a new session → state = active
  3. Home tab shows WYW card
  4. Tap "Browse menu" → opens Club, fulfillment pre-set to dine in
  5. Dismiss with "Not now" → SharedPreferences flag set, card hides for this session

TEST 9 — While-you-wait NOT shown for first-timer
  1. Brand new family, 0 completed sessions
  2. Start session → no WYW card

TEST 10 — Workshop registration
  1. Workshop with 3 spots remaining
  2. Tap card → detail screen
  3. Pick child, wallet payment, register
  4. RPC succeeds, spots_remaining = 2
  5. Workshop card on list shows "2 of 8 spots left"

TEST 11 — Concurrent workshop register
  1. Workshop with 1 spot
  2. In two simulated devices, both tap register at the same time
  3. One succeeds, the other gets workshop_full error
  4. spots_remaining = 0

TEST 12 — Workshop cancellation refunds wallet
  1. User has registered, paid ₹500 from wallet
  2. Profile → Workshops → tap upcoming workshop → Cancel
  3. workshop_cancel RPC fires
  4. wallet balance + ₹500 (refund row added)
  5. workshop spots_remaining + 1
```

---

## 14. Open Items for Founder

- [ ] Provide initial Coffee Diaries menu (item names, descriptions, prices, images, categories)
- [ ] Provide initial FIT Diaries menu (same)
- [ ] Decide initial 2-3 combos with explicit inclusions and prices
- [ ] Decide first 4-6 workshops to schedule (themes, pricing, dates)
- [ ] Confirm GST rate: 5% (already in spec) — verify with CA per service category
- [ ] Confirm "table service" terminology (vs "to your seat" or "in-venue delivery")
- [ ] Decide if workshops have age cutoffs enforced (e.g., reject child outside age_group_min/max)

---

## What's NOT in this session

- Kitchen Display System (Session 10 - Staff)
- Order receipt / GST invoice PDF generation (Session 13)
- Birthday packages (Session 9)
- Adventure tab (Session 8)
