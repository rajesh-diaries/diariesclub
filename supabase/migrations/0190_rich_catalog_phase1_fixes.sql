BEGIN;

-- Fix 1: Correct admin RLS policy to use is_active_admin().
DROP POLICY IF EXISTS "menu_categories_admin_all" ON menu_categories;
CREATE POLICY "menu_categories_admin_all"
  ON menu_categories FOR ALL
  TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

-- Fix 2: Add public read policy so logged-out customers can see categories.
DROP POLICY IF EXISTS "menu_categories_public_read" ON menu_categories;
CREATE POLICY "menu_categories_public_read"
  ON menu_categories FOR SELECT
  USING (true);

-- Fix 3: Idempotent realtime publication addition.
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

-- Fix 4: Idempotent check constraint.
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

-- Fix 5: GIN indexes for new array columns.
CREATE INDEX IF NOT EXISTS idx_menu_items_tags ON menu_items USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_menu_items_symbols ON menu_items USING GIN(symbols);

-- Fix 5b: Composite index for category sort-order calculation.
CREATE INDEX IF NOT EXISTS idx_menu_items_menu_category_sort
  ON menu_items(menu_id, category, sort_order);

-- Fix 5c: Offer price must be lower than regular price when present.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'menu_items_offer_price_lt_price_check'
      AND conrelid = 'menu_items'::regclass
  ) THEN
    ALTER TABLE menu_items
      ADD CONSTRAINT menu_items_offer_price_lt_price_check
      CHECK (offer_price_paise IS NULL OR offer_price_paise < price_paise);
  END IF;
END $$;

-- Fix 6: Recreate admin_menu_item_create with NULL/empty category guard.
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

  -- Upsert category only when provided.
  IF p_category IS NOT NULL AND p_category <> '' THEN
    INSERT INTO menu_categories (menu_id, name, sort_order)
    VALUES (p_menu_id, p_category, 0)
    ON CONFLICT (menu_id, name) DO NOTHING;
  END IF;

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

-- Fix 7: Recreate admin_menu_item_update with NULL/empty category guard.
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

  IF p_category IS NOT NULL AND p_category <> '' THEN
    INSERT INTO menu_categories (menu_id, name, sort_order)
    VALUES (v_row.menu_id, p_category, 0)
    ON CONFLICT (menu_id, name) DO NOTHING;
  END IF;

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
