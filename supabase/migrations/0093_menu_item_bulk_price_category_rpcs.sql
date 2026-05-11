-- 0093 — three productivity RPCs for the catalog admin screens:
--   * admin_menu_items_bulk_set   — flip published/available across N items
--   * admin_menu_item_set_price   — quick price-only update (inline edit)
--   * admin_menu_category_rename  — rename a category for one brand
--     (and merge into an existing one if the new name already exists)

CREATE OR REPLACE FUNCTION public.admin_menu_items_bulk_set(
  p_ids UUID[],
  p_is_available BOOLEAN DEFAULT NULL,
  p_is_published BOOLEAN DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_updated INT;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('success', true, 'updated', 0);
  END IF;
  IF p_is_available IS NULL AND p_is_published IS NULL THEN
    RAISE EXCEPTION 'nothing_to_update';
  END IF;

  UPDATE menu_items SET
    is_available = COALESCE(p_is_available, is_available),
    is_published = COALESCE(p_is_published, is_published),
    updated_at = now()
  WHERE id = ANY(p_ids);
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'menu_item.bulk_set', 'menu_items', NULL,
    jsonb_build_object(
      'ids', to_jsonb(p_ids),
      'is_available', p_is_available,
      'is_published', p_is_published,
      'updated', v_updated
    )
  );

  RETURN jsonb_build_object('success', true, 'updated', v_updated);
END $$;

CREATE OR REPLACE FUNCTION public.admin_menu_item_set_price(
  p_id UUID,
  p_price_paise INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  IF p_price_paise IS NULL OR p_price_paise < 0 THEN
    RAISE EXCEPTION 'invalid_price';
  END IF;

  UPDATE menu_items SET
    price_paise = p_price_paise,
    updated_at = now()
  WHERE id = p_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'menu_item_not_found'; END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'menu_item.set_price', 'menu_items', p_id,
    jsonb_build_object('price_paise', p_price_paise)
  );

  RETURN jsonb_build_object('success', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_menu_category_rename(
  p_brand TEXT,
  p_from TEXT,
  p_to TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_updated INT;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR
     length(trim(p_from)) = 0 OR length(trim(p_to)) = 0 THEN
    RAISE EXCEPTION 'invalid_category';
  END IF;

  UPDATE menu_items SET
    category = trim(p_to),
    updated_at = now()
  WHERE menu_id IN (SELECT id FROM menus WHERE brand = p_brand)
    AND category = p_from;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'menu_category.rename', 'menus', NULL,
    jsonb_build_object(
      'brand', p_brand, 'from', p_from, 'to', p_to, 'updated', v_updated
    )
  );

  RETURN jsonb_build_object('success', true, 'updated', v_updated);
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_menu_items_bulk_set(uuid[], boolean, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_menu_items_bulk_set(uuid[], boolean, boolean)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_menu_item_set_price(uuid, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_menu_item_set_price(uuid, integer)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_menu_category_rename(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_menu_category_rename(text, text, text)
  TO authenticated;
