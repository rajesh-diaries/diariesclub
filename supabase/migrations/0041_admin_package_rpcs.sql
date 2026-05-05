-- ===========================================================================
--  Migration 0041 — admin_package_{create,update,delete,regenerate_pdf}
--
--  Standard SECURITY DEFINER + audit-logged + admin-gated CRUD for
--  birthday_packages. Soft-delete via is_active=false (matches the
--  existing column convention).
--
--  PDF regeneration: admin_package_regenerate_pdf clears pdf_url and
--  asks the Edge function via pg_net (same pattern as notify_push).
--  The Edge function reads the package row, composes a PDF via pdf-lib,
--  uploads to package-pdfs bucket, and updates birthday_packages.pdf_url.
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_package_create(
  p_venue_id          UUID,
  p_name              TEXT,
  p_tier              TEXT,
  p_description       TEXT,
  p_price_paise       INTEGER,
  p_deposit_paise     INTEGER,
  p_duration_hours    INTEGER,
  p_max_kids          INTEGER,
  p_max_adults        INTEGER,
  p_cover_image_url   TEXT,
  p_gallery_image_urls TEXT[],
  p_inclusions        JSONB,
  p_menu_options      JSONB,
  p_non_food_offerings JSONB,
  p_available_days    JSONB,
  p_hero_theme        TEXT,
  p_sort_order        INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID; v_row birthday_packages%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  IF p_tier NOT IN ('basic','hero_adventure','legendary','custom') THEN
    RAISE EXCEPTION 'invalid_tier';
  END IF;

  INSERT INTO birthday_packages(
    venue_id, name, tier, description, price_paise, deposit_paise,
    duration_hours, max_kids, max_adults,
    cover_image_url, gallery_image_urls, inclusions,
    menu_options, non_food_offerings, available_days,
    hero_theme, sort_order
  ) VALUES (
    p_venue_id, p_name, p_tier, p_description, p_price_paise,
    COALESCE(p_deposit_paise, 0),
    COALESCE(p_duration_hours, 2),
    COALESCE(p_max_kids, 15),
    COALESCE(p_max_adults, 10),
    p_cover_image_url, COALESCE(p_gallery_image_urls, '{}'::TEXT[]),
    COALESCE(p_inclusions, '{}'::JSONB),
    COALESCE(p_menu_options, '[]'::JSONB),
    COALESCE(p_non_food_offerings, '[]'::JSONB),
    COALESCE(p_available_days, '{"weekend":true,"weekday":true,"specific_dates":[]}'::JSONB),
    p_hero_theme, COALESCE(p_sort_order, 0)
  ) RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'package.create', 'birthday_package', v_row.id,
          jsonb_build_object('name', p_name, 'tier', p_tier, 'price_paise', p_price_paise));

  RETURN jsonb_build_object('success', true, 'package_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_package_create(UUID,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,TEXT,TEXT[],JSONB,JSONB,JSONB,JSONB,TEXT,INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_package_create(UUID,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,TEXT,TEXT[],JSONB,JSONB,JSONB,JSONB,TEXT,INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_package_update(
  p_id                UUID,
  p_name              TEXT,
  p_tier              TEXT,
  p_description       TEXT,
  p_price_paise       INTEGER,
  p_deposit_paise     INTEGER,
  p_duration_hours    INTEGER,
  p_max_kids          INTEGER,
  p_max_adults        INTEGER,
  p_cover_image_url   TEXT,
  p_gallery_image_urls TEXT[],
  p_inclusions        JSONB,
  p_menu_options      JSONB,
  p_non_food_offerings JSONB,
  p_available_days    JSONB,
  p_hero_theme        TEXT,
  p_is_active         BOOLEAN,
  p_sort_order        INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID; v_row birthday_packages%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM birthday_packages WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF p_price_paise IS NOT NULL AND p_price_paise <= 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  IF p_tier IS NOT NULL AND p_tier NOT IN ('basic','hero_adventure','legendary','custom') THEN
    RAISE EXCEPTION 'invalid_tier';
  END IF;

  UPDATE birthday_packages SET
    name = COALESCE(p_name, name),
    tier = COALESCE(p_tier, tier),
    description = COALESCE(p_description, description),
    price_paise = COALESCE(p_price_paise, price_paise),
    deposit_paise = COALESCE(p_deposit_paise, deposit_paise),
    duration_hours = COALESCE(p_duration_hours, duration_hours),
    max_kids = COALESCE(p_max_kids, max_kids),
    max_adults = COALESCE(p_max_adults, max_adults),
    cover_image_url = COALESCE(p_cover_image_url, cover_image_url),
    gallery_image_urls = COALESCE(p_gallery_image_urls, gallery_image_urls),
    inclusions = COALESCE(p_inclusions, inclusions),
    menu_options = COALESCE(p_menu_options, menu_options),
    non_food_offerings = COALESCE(p_non_food_offerings, non_food_offerings),
    available_days = COALESCE(p_available_days, available_days),
    hero_theme = COALESCE(p_hero_theme, hero_theme),
    is_active = COALESCE(p_is_active, is_active),
    sort_order = COALESCE(p_sort_order, sort_order),
    pdf_url = NULL  -- invalidate cached PDF on edit
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'package.update', 'birthday_package', v_row.id,
          jsonb_build_object('name', v_row.name, 'price_paise', v_row.price_paise, 'is_active', v_row.is_active));

  RETURN jsonb_build_object('success', true, 'package_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_package_update(UUID,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,TEXT,TEXT[],JSONB,JSONB,JSONB,JSONB,TEXT,BOOLEAN,INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_package_update(UUID,TEXT,TEXT,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,TEXT,TEXT[],JSONB,JSONB,JSONB,JSONB,TEXT,BOOLEAN,INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_package_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row birthday_packages%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM birthday_packages WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF NOT v_row.is_active THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  UPDATE birthday_packages SET is_active = FALSE WHERE id = p_id;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'package.deactivate', 'birthday_package', p_id);
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_package_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_package_delete(UUID) TO authenticated, service_role;

-- Trigger PDF regeneration via Edge Function. Same pg_net pattern as
-- notify_push_dispatch in 0017. Vault-stored service-role key.
CREATE OR REPLACE FUNCTION admin_package_regenerate_pdf(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_url      CONSTANT TEXT := 'https://stpxtenyatjwcazuxhtu.supabase.co/functions/v1/generate-package-menu-pdf';
  v_key      TEXT;
BEGIN
  v_admin_id := _assert_active_admin();

  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_key IS NULL OR v_key = '' THEN
    RAISE EXCEPTION 'vault_service_role_key_missing';
  END IF;

  -- Async fire-and-forget. The Edge Function callback updates pdf_url.
  PERFORM net.http_post(
    url := v_url,
    body := jsonb_build_object('package_id', p_id),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    )
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'package.regenerate_pdf', 'birthday_package', p_id);

  RETURN jsonb_build_object('success', true, 'queued', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_package_regenerate_pdf(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_package_regenerate_pdf(UUID) TO authenticated, service_role;

COMMIT;
