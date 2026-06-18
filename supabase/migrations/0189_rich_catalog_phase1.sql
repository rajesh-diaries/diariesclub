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
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'menu_categories'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE menu_categories;
  END IF;
END $$;

-- 2. Extend menu_items
ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS symbols TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS offer_price_paise INTEGER,
  ADD COLUMN IF NOT EXISTS offer_label TEXT,
  ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER;

-- Constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_items_offer_price_check'
      AND conrelid = 'menu_items'::regclass
  ) THEN
    ALTER TABLE menu_items
      ADD CONSTRAINT menu_items_offer_price_check
      CHECK (offer_price_paise IS NULL OR offer_price_paise > 0);
  END IF;
END $$;

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
