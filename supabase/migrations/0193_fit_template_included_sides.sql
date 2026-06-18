BEGIN;

-- 1. Allow each FIT template to list sides/items included with every meal.
ALTER TABLE fit_meal_templates
  ADD COLUMN IF NOT EXISTS included_sides TEXT[] DEFAULT '{}';

-- 2. Recreate admin_fit_template_create with included_sides.
CREATE OR REPLACE FUNCTION admin_fit_template_create(
  p_venue_id         UUID,
  p_name             TEXT,
  p_description      TEXT,
  p_base_price_paise INTEGER,
  p_photo_url        TEXT,
  p_is_subscribable  BOOLEAN,
  p_subscription_meta JSONB,
  p_sort_order       INTEGER,
  p_included_sides   TEXT[] DEFAULT '{}'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_base_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  INSERT INTO fit_meal_templates(
    venue_id, name, description, base_price_paise, photo_url,
    is_subscribable, subscription_meta, sort_order, included_sides
  ) VALUES (
    p_venue_id, p_name, p_description, p_base_price_paise, p_photo_url,
    COALESCE(p_is_subscribable, FALSE), p_subscription_meta,
    COALESCE(p_sort_order, 0), COALESCE(p_included_sides, '{}')
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.create', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', p_name, 'base_price_paise', p_base_price_paise));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER, TEXT[]) TO authenticated, service_role;

-- 3. Recreate admin_fit_template_update with included_sides.
CREATE OR REPLACE FUNCTION admin_fit_template_update(
  p_id               UUID,
  p_name             TEXT,
  p_description      TEXT,
  p_base_price_paise INTEGER,
  p_photo_url        TEXT,
  p_is_subscribable  BOOLEAN,
  p_subscription_meta JSONB,
  p_is_published     BOOLEAN,
  p_is_available     BOOLEAN,
  p_sort_order       INTEGER,
  p_included_sides   TEXT[] DEFAULT '{}'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_templates WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'template_not_found'; END IF;
  IF p_base_price_paise IS NOT NULL AND p_base_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  UPDATE fit_meal_templates SET
    name = COALESCE(p_name, name),
    description = COALESCE(p_description, description),
    base_price_paise = COALESCE(p_base_price_paise, base_price_paise),
    photo_url = COALESCE(p_photo_url, photo_url),
    is_subscribable = COALESCE(p_is_subscribable, is_subscribable),
    subscription_meta = COALESCE(p_subscription_meta, subscription_meta),
    is_published = COALESCE(p_is_published, is_published),
    is_available = COALESCE(p_is_available, is_available),
    sort_order = COALESCE(p_sort_order, sort_order),
    included_sides = COALESCE(p_included_sides, included_sides),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.update', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', v_row.name, 'is_published', v_row.is_published));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER, TEXT[]) TO authenticated, service_role;

COMMIT;
