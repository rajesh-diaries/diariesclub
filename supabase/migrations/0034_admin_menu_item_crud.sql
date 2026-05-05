-- ===========================================================================
--  Migration 0034 — Coffee/FIT menu_items admin CRUD (Module 2.4)
--
--  Adds:
--    1. menu_items.is_published BOOLEAN — separate from is_available.
--       is_available = sold out for the day (admin quick-toggle).
--       is_published = hidden entirely (soft-delete).
--    2. menu-photos private storage bucket + RLS.
--    3. Five RPCs: create / update / delete / toggle_available / reorder.
--
--  Reorder uses a sort_order swap with the neighbour rather than full
--  drag-and-drop (which would require a different UI shell). Admin
--  clicks ↑/↓ → RPC swaps the row's sort_order with the adjacent row
--  in the same menu+category.
-- ===========================================================================

BEGIN;

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS is_published BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_menu_items_published_sort
  ON menu_items(menu_id, category, sort_order)
  WHERE is_published = TRUE;

INSERT INTO storage.buckets (id, name, public)
VALUES ('menu-photos', 'menu-photos', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "menu_photos_authenticated_read" ON storage.objects;
CREATE POLICY "menu_photos_authenticated_read"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'menu-photos');

DROP POLICY IF EXISTS "menu_photos_service_role_write" ON storage.objects;
CREATE POLICY "menu_photos_service_role_write"
  ON storage.objects FOR ALL
  TO service_role
  USING (bucket_id = 'menu-photos')
  WITH CHECK (bucket_id = 'menu-photos');

-- 1. admin_menu_item_create
CREATE OR REPLACE FUNCTION admin_menu_item_create(
  p_menu_id      UUID,
  p_name         TEXT,
  p_description  TEXT,
  p_price_paise  INTEGER,
  p_category     TEXT,
  p_image_url    TEXT,
  p_sort_order   INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
  v_max      INTEGER;
BEGIN
  v_admin_id := _assert_active_admin();

  IF p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  -- If sort_order not provided, append after the last item in this category.
  IF p_sort_order IS NULL THEN
    SELECT COALESCE(MAX(sort_order), 0) + 10 INTO v_max
      FROM menu_items
     WHERE menu_id = p_menu_id AND category IS NOT DISTINCT FROM p_category;
  ELSE
    v_max := p_sort_order;
  END IF;

  INSERT INTO menu_items(
    menu_id, name, description, price_paise, image_url,
    category, is_available, is_published, sort_order
  ) VALUES (
    p_menu_id, p_name, p_description, p_price_paise, p_image_url,
    p_category, TRUE, TRUE, v_max
  ) RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.create', 'menu_item', v_row.id,
    jsonb_build_object('name', p_name, 'price_paise', p_price_paise, 'menu_id', p_menu_id)
  );

  RETURN jsonb_build_object('success', true, 'item_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_create(
  UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_menu_item_create(
  UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, INTEGER
) TO authenticated, service_role;

-- 2. admin_menu_item_update
CREATE OR REPLACE FUNCTION admin_menu_item_update(
  p_id           UUID,
  p_name         TEXT,
  p_description  TEXT,
  p_price_paise  INTEGER,
  p_category     TEXT,
  p_image_url    TEXT,
  p_is_available BOOLEAN,
  p_is_published BOOLEAN
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

  UPDATE menu_items SET
    name = p_name,
    description = p_description,
    price_paise = p_price_paise,
    category = p_category,
    image_url = p_image_url,
    is_available = COALESCE(p_is_available, v_row.is_available),
    is_published = COALESCE(p_is_published, v_row.is_published),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.update', 'menu_item', v_row.id,
    jsonb_build_object('name', p_name, 'price_paise', p_price_paise,
                       'is_available', v_row.is_available,
                       'is_published', v_row.is_published)
  );

  RETURN jsonb_build_object('success', true, 'item_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_update(
  UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, BOOLEAN, BOOLEAN
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_menu_item_update(
  UUID, TEXT, TEXT, INTEGER, TEXT, TEXT, BOOLEAN, BOOLEAN
) TO authenticated, service_role;

-- 3. admin_menu_item_delete (soft via is_published=false)
CREATE OR REPLACE FUNCTION admin_menu_item_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM menu_items WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'item_not_found'; END IF;
  IF NOT v_row.is_published THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  UPDATE menu_items SET is_published = FALSE, updated_at = now() WHERE id = p_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'menu_item.unpublish', 'menu_item', p_id);

  RETURN jsonb_build_object('success', true, 'item_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_menu_item_delete(UUID) TO authenticated, service_role;

-- 4. admin_menu_item_toggle_available — quick action for sold-out
CREATE OR REPLACE FUNCTION admin_menu_item_toggle_available(
  p_id        UUID,
  p_available BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM menu_items WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'item_not_found'; END IF;

  UPDATE menu_items SET is_available = p_available, updated_at = now() WHERE id = p_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.toggle_available', 'menu_item', p_id,
    jsonb_build_object('is_available', p_available)
  );

  RETURN jsonb_build_object('success', true, 'is_available', p_available);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_toggle_available(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_menu_item_toggle_available(UUID, BOOLEAN) TO authenticated, service_role;

-- 5. admin_menu_item_reorder — swap sort_order with neighbour. Direction
-- 'up' or 'down' moves the item one slot within (menu_id, category).
CREATE OR REPLACE FUNCTION admin_menu_item_reorder(
  p_id        UUID,
  p_direction TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      menu_items%ROWTYPE;
  v_neighbour menu_items%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_direction NOT IN ('up','down') THEN RAISE EXCEPTION 'invalid_direction'; END IF;

  SELECT * INTO v_row FROM menu_items WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'item_not_found'; END IF;

  IF p_direction = 'up' THEN
    SELECT * INTO v_neighbour FROM menu_items
     WHERE menu_id = v_row.menu_id
       AND category IS NOT DISTINCT FROM v_row.category
       AND sort_order < v_row.sort_order
       AND is_published = TRUE
     ORDER BY sort_order DESC LIMIT 1 FOR UPDATE;
  ELSE
    SELECT * INTO v_neighbour FROM menu_items
     WHERE menu_id = v_row.menu_id
       AND category IS NOT DISTINCT FROM v_row.category
       AND sort_order > v_row.sort_order
       AND is_published = TRUE
     ORDER BY sort_order ASC LIMIT 1 FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    -- No neighbour — already at the edge.
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  -- Swap sort_order values.
  UPDATE menu_items SET sort_order = v_neighbour.sort_order, updated_at = now()
   WHERE id = v_row.id;
  UPDATE menu_items SET sort_order = v_row.sort_order, updated_at = now()
   WHERE id = v_neighbour.id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'menu_item.reorder', 'menu_item', p_id,
    jsonb_build_object('direction', p_direction, 'swapped_with', v_neighbour.id)
  );

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION admin_menu_item_reorder(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_menu_item_reorder(UUID, TEXT) TO authenticated, service_role;

COMMIT;
