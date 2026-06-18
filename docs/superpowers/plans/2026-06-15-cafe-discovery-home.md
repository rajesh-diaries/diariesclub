# Cafe Discovery Home — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Goal

Transform the **Cafe** tab in the customer app from a simple category-pill + vertical-list layout into a rich **food-discovery home** similar to the Swiggy/Zomato-style reference shared by the team. Increase browsing speed, conversion, and visual appeal while keeping the existing top-level Club tabs intact.

## Scope

- **In scope:** Cafe tab redesign only.
- **Out of scope (for now):** FIT, Combos, Birthdays, Workshops tabs remain unchanged.

---

## Reference layout

```
[AppBar: Club]                           [Bag icon]
[Cafe | FIT | Combos | Birthdays | ...]  ← existing tabs kept

Cafe tab:
┌────────────────────────────────────────┐
│  [Search bar]  [Offers / banners]      │
├────────────────────────────────────────┤
│  WHAT'S ON YOUR PLATE TODAY?           │
│  [Grid of category chips with images]  │
│  Healthy Bowls  Burgers  Rice Bowls    │
│  Specialty Coffee  Desi Bites ...      │
├────────────────────────────────────────┤
│  CURATED COLLECTIONS                   │
│  [Tiny Tummies] [Power Up] [Parents'    │
│   Coffee Corner] [Share & Celebrate]   │
├────────────────────────────────────────┤
│  CROWD FAVS / RECOMMENDED FOR YOU      │
│  [Horizontal cards]                    │
├────────────────────────────────────────┤
│  ALL ITEMS                             │
│  [Vertical list / grid]                │
├────────────────────────────────────────┤
│  [Sticky bottom cart bar]              │
└────────────────────────────────────────┘
```

---

## Task 1: Data layer updates

### Files
- `lib/features/club/providers/menu_items_provider.dart` — keep existing stream.
- `lib/features/club/providers/cafe_home_provider.dart` — new derived provider.

### Steps

- [ ] **1.1 Create `cafeHomeProvider`**
  - Watch `menuItemsByBrandProvider('coffee')`.
  - Expose derived lists:
    - `categories`: unique `category` values with a representative item image.
    - `curatedCollections`: Play-Diaries-specific groups such as:
      - **Tiny Tummies** — kid-friendly items (tagged `Kids`, `Mild`, or low spice).
      - **Power Up** — FIT-aligned healthy/high-protein items (tagged `Healthy`, `Protein`, `Veg`).
      - **Parents' Coffee Corner** — coffee and quick bites for adults.
      - **Share & Celebrate** — party/birthday-friendly items (tagged `Share`, `Bestseller`, large portions).
      - **Quick Grabs** — items with `prep_time_minutes <= 15`.
      - **New on the Menu** — items tagged `New`.
    - `popularItems`: top N items sorted by a proxy (e.g., `Bestseller` tag, then price, or a new `order_count` column if added).
    - `allItems`: full list for bottom section.
- [ ] **1.2 Optional: add `order_count` / `popularity_score` to `menu_items`**
  - Migration `0193_menu_item_popularity.sql` adds `order_count INTEGER DEFAULT 0`.
  - Update admin create/update RPCs to accept the new column (or default to 0).
  - Update admin edit form with an optional `Popularity / order count` field.
  - If skipped, popularity can be approximated by `Bestseller` tag.

---

## Task 2: UI components

### Files
- `lib/features/club/widgets/cafe_discovery_home.dart` — new root widget for Cafe tab.
- `lib/features/club/widgets/cafe_category_grid.dart`
- `lib/features/club/widgets/cafe_curated_collections_row.dart`
- `lib/features/club/widgets/cafe_recommendation_row.dart`
- `lib/features/club/widgets/cafe_cart_bar.dart`
- `lib/features/club/cafe_menu_tab.dart` — replace current `BrandMenuTab` usage.

### Steps

- [ ] **2.1 Build `CafeDiscoveryHome`**
  - `CustomScrollView` with slivers:
    - Search + promo banner sliver.
    - Category grid sliver.
    - Curated collections row sliver.
    - Recommendations horizontal list sliver.
    - All items list sliver.
  - Wrap with `Stack` + bottom `CafeCartBar`.

- [ ] **2.2 Category grid** (`CafeCategoryGrid`)
  - 2-row horizontal scroll or responsive `GridView`.
  - Each cell: circular/square image + category name below.
  - Tapping a cell filters the "All items" section to that category.
  - Use first menu item image in that category as the cell image; fallback to a brand icon.

- [ ] **2.3 Curated collections row** (`CafeCuratedCollectionsRow`)
  - Horizontal scroll of themed cards: "Tiny Tummies", "Power Up", "Parents' Coffee Corner", "Share & Celebrate", "Quick Grabs", "New on the Menu".
  - Each card has a distinct color/illustration and a short subtitle.
  - Tapping a card filters the "All items" section to matching items.
  - Rules are tag/prep-time based (no backend changes needed).

- [ ] **2.4 Recommendations row** (`CafeRecommendationRow`)
  - Horizontal list of `MenuItemCard`s or smaller `CompactItemCard`s.
  - Source: `popularItems` from `cafeHomeProvider`.
  - Title: "Crowd Favs" or "Recommended for you".

- [ ] **2.5 All items section**
  - Keep existing `MenuItemCard` vertical list.
  - Add section title "All Items".
  - Respect category and curated-collection filters set by tapping grid/collection cards.

- [ ] **2.6 Persistent cart bar** (`CafeCartBar`)
  - Watch `cartProvider`.
  - Show item count + total + "View Cart".
  - Visible only when cart has items.
  - Tapping navigates to cart.

- [ ] **2.7 Search bar (optional v1.1)**
  - Static search bar at the top that filters items by name/tag.

---

## Task 3: Replace Cafe tab entry point

- [ ] **3.1 Update `CafeMenuTab`**
  - Replace `BrandMenuTab(brand: 'coffee', ...)` with `CafeDiscoveryHome()`.
- [ ] **3.2 Remove unused BrandMenuTab params**
  - If `BrandMenuTab` is no longer used by Cafe, ensure FIT still uses it for a la carte.

---

## Task 4: Styling and polish

- [ ] **4.1 Match reference colors**
  - Purple/yellow accents from screenshot are **not** current app colors. Decide whether to:
    - Use existing Play Diaries navy/gold palette, OR
    - Adopt the reference purple theme for the Club section.
- [ ] **4.2 Typography and spacing**
  - Section titles uppercase, letter spacing.
  - Generous vertical padding.
- [ ] **4.3 Loading / error / empty states**
  - Skeleton for each section.
  - Error state if menu fails to load.

---

## Task 5: Testing and deployment

- [ ] **5.1 Run `flutter test` and `flutter analyze`**
- [ ] **5.2 Build customer app on device/simulator**
- [ ] **5.3 Verify interactions:**
  - Category tap filters all-items list.
  - Curated collection tap filters all-items list.
  - Cart bar updates when items added.
  - Tapping item card navigates to detail/add.

---

## Open questions to resolve before implementation

1. **Color palette:** Keep current navy/gold or adopt the reference purple/yellow?
2. **Curated collections:** Which themes? Current proposal:
   - Tiny Tummies
   - Power Up
   - Parents' Coffee Corner
   - Share & Celebrate
   - Quick Grabs
   - New on the Menu
3. **Popularity data:** Add `order_count` column, or approximate by `Bestseller` tag?
4. **Category images:** Use first item photo per category, or upload dedicated category images in admin?
5. **Search:** Include a real-time search bar in v1, or defer to v1.1?
6. **Cart bar:** Show only on Cafe tab, or app-wide bottom bar?

---

## Recommended first step

Start with **Task 1.1 + Task 2.1–2.3** (category grid + curated collections) using existing tags and prep-time data. This gives the biggest visual impact without backend changes. Add popularity/order_count and recommendations in a follow-up.
