BEGIN;

-- 1. Allow each FIT option to declare its dietary type so templates can
--    auto-detect Veg / Non-Veg availability from the protein category.
ALTER TABLE fit_meal_options
  ADD COLUMN IF NOT EXISTS dietary_type TEXT;

ALTER TABLE fit_meal_options
  DROP CONSTRAINT IF EXISTS fit_meal_options_dietary_type_check;

ALTER TABLE fit_meal_options
  ADD CONSTRAINT fit_meal_options_dietary_type_check
    CHECK (dietary_type IS NULL OR dietary_type IN ('veg', 'non_veg', 'egg', 'customizable'));

-- 2. Admin overrides on templates. NULL = auto-detect from options;
--    TRUE/FALSE = force the badge on/off.
ALTER TABLE fit_meal_templates
  ADD COLUMN IF NOT EXISTS veg_available BOOLEAN,
  ADD COLUMN IF NOT EXISTS non_veg_available BOOLEAN;

-- 3. Recreate admin_fit_option_create with dietary_type.
CREATE OR REPLACE FUNCTION admin_fit_option_create(
  p_venue_id      UUID,
  p_category_id   UUID,
  p_name          TEXT,
  p_upcharge_paise INTEGER,
  p_display_order INTEGER,
  p_dietary_type  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_options%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_upcharge_paise IS NOT NULL AND p_upcharge_paise < 0 THEN RAISE EXCEPTION 'invalid_upcharge'; END IF;
  INSERT INTO fit_meal_options(
    venue_id, category_id, name, upcharge_paise, display_order, dietary_type
  ) VALUES (
    p_venue_id, p_category_id, p_name,
    COALESCE(p_upcharge_paise, 0), COALESCE(p_display_order, 0), p_dietary_type
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_option.create', 'fit_meal_option', v_row.id,
          jsonb_build_object('name', p_name, 'upcharge_paise', v_row.upcharge_paise, 'dietary_type', v_row.dietary_type));
  RETURN jsonb_build_object('success', true, 'option_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_option_create(UUID, UUID, TEXT, INTEGER, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_create(UUID, UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated, service_role;

-- 4. Recreate admin_fit_option_update with dietary_type.
CREATE OR REPLACE FUNCTION admin_fit_option_update(
  p_id            UUID,
  p_name          TEXT,
  p_upcharge_paise INTEGER,
  p_is_available  BOOLEAN,
  p_is_published  BOOLEAN,
  p_display_order INTEGER,
  p_dietary_type  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_options%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_options WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'option_not_found'; END IF;
  IF p_upcharge_paise IS NOT NULL AND p_upcharge_paise < 0 THEN RAISE EXCEPTION 'invalid_upcharge'; END IF;

  UPDATE fit_meal_options SET
    name = COALESCE(p_name, name),
    upcharge_paise = COALESCE(p_upcharge_paise, upcharge_paise),
    is_available = COALESCE(p_is_available, is_available),
    is_published = COALESCE(p_is_published, is_published),
    display_order = COALESCE(p_display_order, display_order),
    dietary_type = COALESCE(p_dietary_type, dietary_type),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_option.update', 'fit_meal_option', v_row.id,
          jsonb_build_object('name', v_row.name, 'upcharge_paise', v_row.upcharge_paise,
                             'is_available', v_row.is_available, 'is_published', v_row.is_published,
                             'dietary_type', v_row.dietary_type));
  RETURN jsonb_build_object('success', true, 'option_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_option_update(UUID, TEXT, INTEGER, BOOLEAN, BOOLEAN, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_update(UUID, TEXT, INTEGER, BOOLEAN, BOOLEAN, INTEGER, TEXT) TO authenticated, service_role;

-- 5. Recreate admin_fit_template_create with availability overrides.
CREATE OR REPLACE FUNCTION admin_fit_template_create(
  p_venue_id            UUID,
  p_name                TEXT,
  p_description         TEXT,
  p_base_price_paise    INTEGER,
  p_photo_url           TEXT,
  p_is_subscribable     BOOLEAN,
  p_subscription_meta   JSONB,
  p_sort_order          INTEGER,
  p_included_sides      TEXT[] DEFAULT '{}',
  p_veg_available       BOOLEAN DEFAULT NULL,
  p_non_veg_available   BOOLEAN DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_base_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  INSERT INTO fit_meal_templates(
    venue_id, name, description, base_price_paise, photo_url,
    is_subscribable, subscription_meta, sort_order, included_sides,
    veg_available, non_veg_available
  ) VALUES (
    p_venue_id, p_name, p_description, p_base_price_paise, p_photo_url,
    COALESCE(p_is_subscribable, FALSE), p_subscription_meta,
    COALESCE(p_sort_order, 0), COALESCE(p_included_sides, '{}'),
    p_veg_available, p_non_veg_available
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.create', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', p_name, 'base_price_paise', p_base_price_paise));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER, TEXT[], BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER, TEXT[], BOOLEAN, BOOLEAN) TO authenticated, service_role;

-- 6. Recreate admin_fit_template_update with availability overrides.
CREATE OR REPLACE FUNCTION admin_fit_template_update(
  p_id                  UUID,
  p_name                TEXT,
  p_description         TEXT,
  p_base_price_paise    INTEGER,
  p_photo_url           TEXT,
  p_is_subscribable     BOOLEAN,
  p_subscription_meta   JSONB,
  p_is_published        BOOLEAN,
  p_is_available        BOOLEAN,
  p_sort_order          INTEGER,
  p_included_sides      TEXT[] DEFAULT '{}',
  p_veg_available       BOOLEAN DEFAULT NULL,
  p_non_veg_available   BOOLEAN DEFAULT NULL
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
    veg_available = COALESCE(p_veg_available, veg_available),
    non_veg_available = COALESCE(p_non_veg_available, non_veg_available),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.update', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', v_row.name, 'is_published', v_row.is_published));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER, TEXT[], BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER, TEXT[], BOOLEAN, BOOLEAN) TO authenticated, service_role;

COMMIT;
