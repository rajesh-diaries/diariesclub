# Rich Catalog Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add managed categories, tags, symbols/badges, and offer pricing to the admin catalog and surface them in the customer app.

**Architecture:** Extend `menu_items` with new JSONB/ARRAY columns; introduce `menu_categories` for category management; update admin CRUD RPCs; enhance admin edit/list screens; update customer `MenuItemCard` and `BrandMenuTab` to show badges, offer prices, and category filters.

**Tech Stack:** Flutter web (admin), Flutter mobile/web (customer), Supabase Postgres + RPCs, Riverpod.

---

## File structure

| File | Responsibility |
|------|----------------|
| `supabase/migrations/0189_rich_catalog_phase1.sql` | Schema migration |
| `lib/admin/catalog/menu_item_edit_screen.dart` | Rich create/edit form |
| `lib/admin/catalog/coffee_list_screen.dart` | List with badges/offer indicator |
| `lib/admin/catalog/combos_list_screen.dart` | Optional badge polish |
| `lib/admin/providers/admin_catalog_providers.dart` | `menuCategoriesProvider` (new or existing) |
| `lib/features/club/widgets/menu_item_card.dart` | Customer card badges + offer price |
| `lib/features/club/widgets/brand_menu_tab.dart` | Category filter chips |
| `lib/features/club/providers/menu_items_provider.dart` | Customer menu items stream |

---

## Task 1: Backend schema + RPCs

**Files:**
- Create: `supabase/migrations/0189_rich_catalog_phase1.sql`
- Modify: `supabase/migrations/0034_admin_menu_item_crud.sql` (conceptual — actual change is in new migration via `CREATE OR REPLACE FUNCTION`)

### Steps

- [ ] **Step 1.1: Create migration file**

Create `supabase/migrations/0189_rich_catalog_phase1.sql`:

```sql
BEGIN;

-- 1. Managed categories
CREATE TABLE IF NOT EXISTS menu_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id UUID NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(menu_id, name)
);

ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;

-- Admin full access
DROP POLICY IF EXISTS "menu_categories_admin_all" ON menu_categories;
CREATE POLICY "menu_categories_admin_all"
  ON menu_categories FOR ALL
  TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE id = auth.uid() AND role IN ('admin','super_admin')));

-- Customer read
DROP POLICY IF EXISTS "menu_categories_customer_read" ON menu_categories;
CREATE POLICY "menu_categories_customer_read"
  ON menu_categories FOR SELECT
  TO authenticated
  USING (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE menu_categories;

-- 2. Extend menu_items
ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS symbols TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS offer_price_paise INTEGER,
  ADD COLUMN IF NOT EXISTS offer_label TEXT,
  ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER;

-- Constraint
ALTER TABLE menu_items
  ADD CONSTRAINT menu_items_offer_price_check
    CHECK (offer_price_paise IS NULL OR offer_price_paise > 0);

-- 3. Seed existing categories from menu_items into menu_categories
INSERT INTO menu_categories (menu_id, name, sort_order)
SELECT DISTINCT menu_id, category, 0
FROM menu_items
WHERE category IS NOT NULL
  AND category <> ''
ON CONFLICT (menu_id, name) DO NOTHING;

-- 4. Replace admin_menu_item_create with new params
CREATE OR REPLACE FUNCTION admin_menu_item_create(
  p_menu_id           UUID,
  p_name              TEXT,
  p_description       TEXT,
  p_price_paise       INTEGER,
  p_category          TEXT,
  p_image_url         TEXT,
  p_sort_order        INTEGER,
  p_tags              TEXT[] DEFAULT '{}',
  p_symbols           TEXT[] DEFAULT '{}',
  p_offer_price_paise INTEGER DEFAULT NULL,
  p_offer_label       TEXT DEFAULT NULL,
  p_prep_time_minutes INTEGER DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
  v_max      INTEGER;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  IF p_sort_order IS NULL THEN
    SELECT COALESCE(MAX(sort_order), 0) + 10 INTO v_max
      FROM menu_items
     WHERE menu_id = p_menu_id AND category IS NOT DISTINCT FROM p_category;
  ELSE
    v_max := p_sort_order;
  END IF;

  -- Upsert category
  INSERT INTO menu_categories (menu_id, name, sort_order)
  VALUES (p_menu_id, p_category, 0)
  ON CONFLICT (menu_id, name) DO NOTHING;

  INSERT INTO menu_items(
    menu_id, name, description, price_paise, image_url,
    category, is_available, is_published, sort_order,
    tags, symbols, offer_price_paise, offer_label, prep_time_minutes
  ) VALUES (
    p_menu_id, p_name, p_description, p_price_paise, p_image_url,
    p_category, TRUE, TRUE, v_max,
    COALESCE(p_tags, '{}'), COALESCE(p_symbols, '{}'),
    p_offer_price_paise, p_offer_label, p_prep_time_minutes
  ) RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.create', 'menu_item', v_row.id,
    jsonb_build_object('name', p_name, 'price_paise', p_price_paise)
  );

  RETURN jsonb_build_object('success', true, 'item_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_create(UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER, TEXT[], TEXT[], INTEGER, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_menu_item_create(UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER, TEXT[], TEXT[], INTEGER, TEXT, INTEGER) TO authenticated, service_role;

-- 5. Replace admin_menu_item_update with new params
CREATE OR REPLACE FUNCTION admin_menu_item_update(
  p_id                UUID,
  p_name              TEXT,
  p_description       TEXT,
  p_price_paise       INTEGER,
  p_category          TEXT,
  p_image_url         TEXT,
  p_is_available      BOOLEAN,
  p_is_published      BOOLEAN,
  p_tags              TEXT[] DEFAULT '{}',
  p_symbols           TEXT[] DEFAULT '{}',
  p_offer_price_paise INTEGER DEFAULT NULL,
  p_offer_label       TEXT DEFAULT NULL,
  p_prep_time_minutes INTEGER DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM menu_items WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'item_not_found'; END IF;
  IF p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  INSERT INTO menu_categories (menu_id, name, sort_order)
  VALUES (v_row.menu_id, p_category, 0)
  ON CONFLICT (menu_id, name) DO NOTHING;

  UPDATE menu_items SET
    name = p_name,
    description = p_description,
    price_paise = p_price_paise,
    category = p_category,
    image_url = p_image_url,
    is_available = COALESCE(p_is_available, v_row.is_available),
    is_published = COALESCE(p_is_published, v_row.is_published),
    tags = COALESCE(p_tags, v_row.tags),
    symbols = COALESCE(p_symbols, v_row.symbols),
    offer_price_paise = p_offer_price_paise,
    offer_label = p_offer_label,
    prep_time_minutes = p_prep_time_minutes,
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.update', 'menu_item', v_row.id,
    jsonb_build_object('name', p_name, 'price_paise', p_price_paise)
  );

  RETURN jsonb_build_object('success', true, 'item_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_update(UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_menu_item_update(UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, TEXT, INTEGER) TO authenticated, service_role;

COMMIT;
```

- [ ] **Step 1.2: Apply migration**

Run: `supabase db push` or `supabase db query --linked -f supabase/migrations/0189_rich_catalog_phase1.sql`

- [ ] **Step 1.3: Verify**

Query `menu_categories` and `menu_items` columns exist.

---

## Task 2: Admin UI — category provider + edit form

**Files:**
- Modify: `lib/admin/catalog/menu_item_edit_screen.dart`
- Create/Modify: `lib/admin/providers/admin_catalog_providers.dart` (or add to existing admin providers)
- Modify: `lib/admin/catalog/coffee_list_screen.dart`

### Steps

- [ ] **Step 2.1: Add menu categories provider**

In `lib/admin/providers/admin_catalog_providers.dart` (create if missing):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final menuCategoriesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, menuId) {
  return Supabase.instance.client
      .from('menu_categories')
      .stream(primaryKey: ['id'])
      .eq('menu_id', menuId)
      .order('sort_order');
});
```

- [ ] **Step 2.2: Update edit form**

In `MenuItemEditScreen`:
- Replace category `TextField` with `DropdownButtonFormField` populated from `menuCategoriesProvider(menu_id)`.
- Add multi-select chips for `tags` and `symbols`.
- Add optional `offer_price_paise` and `offer_label` fields.
- Add optional `prep_time_minutes` field.
- Pass new fields to `admin_menu_item_create` / `admin_menu_item_update`.

- [ ] **Step 2.3: Update coffee list screen**

In `coffee_list_screen.dart`:
- Show tag/symbol chips and offer badge in the DataTable rows.
- Existing sort_order arrows stay.

---

## Task 3: Customer UI — badges, offers, category filter

**Files:**
- Modify: `lib/features/club/widgets/menu_item_card.dart`
- Modify: `lib/features/club/widgets/brand_menu_tab.dart`
- Modify: `lib/features/club/providers/menu_items_provider.dart` (if filtering in provider)

### Steps

- [ ] **Step 3.1: Update MenuItemCard**

Show:
- Tags as small pills below name.
- Symbols as icons (e.g., chilli for Spicy, leaf for Healthy).
- Offer price with strikethrough original price when `offer_price_paise` exists.
- Prep time badge if present.

- [ ] **Step 3.2: Add category filter chips in BrandMenuTab**

Build unique category list from items; render horizontal `ChoiceChip` row below hero. Selecting a chip filters the list. Include an “All” chip.

- [ ] **Step 3.3: Verify customer stream still works**

`menuItemsByBrandProvider` streams `menu_items` with all columns; no change needed unless you want server-side category filtering (do it client-side for now).

---

## Task 4: Deploy admin + test

- [ ] **Step 4.1: Run migrations on dev**
- [ ] **Step 4.2: Build and deploy admin web**
- [ ] **Step 4.3: Test create/edit item in admin**
- [ ] **Step 4.4: Test customer app Cafe/FIT tabs show badges and filters**
