-- ===========================================================================
--  Migration 0038 — Admin combo CRUD RPCs (Module 2.6)
--
--  combos table already exists (0001:355) with the columns we need. No
--  schema change. Item membership is stored in `inclusions` JSONB; new
--  admin writes use the shape:
--    { "menu_items": [ { "id": "<uuid>", "quantity": <int> }, ... ],
--      "session_minutes": <int|null> }
--  Backward-compat: existing rows may have "menu_item_ids" (flat array) —
--  customer-side reads accept either shape.
--
--  Soft-delete via is_active=false (combos table convention; menu_items
--  uses is_published — different table, different column. Keeping each
--  table consistent with its own history.)
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_combo_create(
  p_venue_id      UUID,
  p_name          TEXT,
  p_description   TEXT,
  p_price_paise   INTEGER,
  p_photo_url     TEXT,
  p_inclusions    JSONB,
  p_sort_order    INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID; v_row combos%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  INSERT INTO combos(
    venue_id, name, description, cover_image_url, price_paise,
    inclusions, sort_order
  ) VALUES (
    p_venue_id, p_name, p_description, p_photo_url, p_price_paise,
    COALESCE(p_inclusions, '{}'::JSONB), COALESCE(p_sort_order, 0)
  ) RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'combo.create', 'combo', v_row.id,
    jsonb_build_object('name', p_name, 'price_paise', p_price_paise)
  );

  RETURN jsonb_build_object('success', true, 'combo_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_combo_create(UUID, TEXT, TEXT, INTEGER, TEXT, JSONB, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_combo_create(UUID, TEXT, TEXT, INTEGER, TEXT, JSONB, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_combo_update(
  p_id            UUID,
  p_name          TEXT,
  p_description   TEXT,
  p_price_paise   INTEGER,
  p_photo_url     TEXT,
  p_inclusions    JSONB,
  p_is_active     BOOLEAN,
  p_sort_order    INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row combos%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM combos WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'combo_not_found'; END IF;
  IF p_price_paise IS NOT NULL AND p_price_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_price';
  END IF;

  UPDATE combos SET
    name = COALESCE(p_name, name),
    description = COALESCE(p_description, description),
    price_paise = COALESCE(p_price_paise, price_paise),
    cover_image_url = COALESCE(p_photo_url, cover_image_url),
    inclusions = COALESCE(p_inclusions, inclusions),
    is_active = COALESCE(p_is_active, is_active),
    sort_order = COALESCE(p_sort_order, sort_order)
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'combo.update', 'combo', v_row.id,
    jsonb_build_object('name', v_row.name, 'price_paise', v_row.price_paise, 'is_active', v_row.is_active)
  );

  RETURN jsonb_build_object('success', true, 'combo_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_combo_update(UUID, TEXT, TEXT, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_combo_update(UUID, TEXT, TEXT, INTEGER, TEXT, JSONB, BOOLEAN, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_combo_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row combos%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM combos WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'combo_not_found'; END IF;
  IF NOT v_row.is_active THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  UPDATE combos SET is_active = FALSE WHERE id = p_id;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'combo.deactivate', 'combo', p_id);
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_combo_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_combo_delete(UUID) TO authenticated, service_role;

COMMIT;
