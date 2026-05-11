-- 0085 — extend admin_package_create + admin_package_update to accept
-- the new experience_inclusions param. Same signature shape; appended
-- the new param at the tail with a default to keep existing callers
-- working.

CREATE OR REPLACE FUNCTION public.admin_package_create(
  p_venue_id UUID,
  p_name TEXT,
  p_tier TEXT,
  p_description TEXT DEFAULT NULL,
  p_price_paise INTEGER DEFAULT NULL,
  p_deposit_paise INTEGER DEFAULT NULL,
  p_duration_hours INTEGER DEFAULT 3,
  p_max_kids INTEGER DEFAULT NULL,
  p_max_adults INTEGER DEFAULT NULL,
  p_cover_image_url TEXT DEFAULT NULL,
  p_gallery_image_urls TEXT[] DEFAULT NULL,
  p_inclusions JSONB DEFAULT '[]'::jsonb,
  p_menu_options JSONB DEFAULT '{}'::jsonb,
  p_non_food_offerings JSONB DEFAULT '[]'::jsonb,
  p_available_days JSONB DEFAULT '{"weekday":true,"weekend":true,"specific_dates":[]}'::jsonb,
  p_hero_theme TEXT DEFAULT NULL,
  p_sort_order INTEGER DEFAULT 0,
  p_hall_name TEXT DEFAULT NULL,
  p_min_guests INTEGER DEFAULT NULL,
  p_max_guests INTEGER DEFAULT NULL,
  p_price_per_pax_veg_paise INTEGER DEFAULT NULL,
  p_price_per_pax_non_veg_paise INTEGER DEFAULT NULL,
  p_pdf_url TEXT DEFAULT NULL,
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  INSERT INTO birthday_packages(
    venue_id, name, tier, description,
    price_paise, deposit_paise,
    duration_hours, max_kids, max_adults,
    cover_image_url, gallery_image_urls,
    inclusions, menu_options, non_food_offerings, available_days,
    hero_theme, sort_order, is_active,
    hall_name, min_guests, max_guests,
    price_per_pax_veg_paise, price_per_pax_non_veg_paise,
    pdf_url, experience_inclusions
  ) VALUES (
    p_venue_id, p_name, p_tier, p_description,
    p_price_paise, p_deposit_paise,
    p_duration_hours, p_max_kids, p_max_adults,
    p_cover_image_url, p_gallery_image_urls,
    p_inclusions, p_menu_options, p_non_food_offerings, p_available_days,
    p_hero_theme, p_sort_order, true,
    p_hall_name, p_min_guests, p_max_guests,
    p_price_per_pax_veg_paise, p_price_per_pax_non_veg_paise,
    p_pdf_url, p_experience_inclusions
  ) RETURNING id INTO v_id;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'package.create', 'birthday_packages', v_id,
    jsonb_build_object('name', p_name, 'tier', p_tier, 'hall_name', p_hall_name)
  );

  RETURN jsonb_build_object('success', true, 'package_id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_package_update(
  p_id UUID,
  p_name TEXT,
  p_tier TEXT,
  p_description TEXT DEFAULT NULL,
  p_price_paise INTEGER DEFAULT NULL,
  p_deposit_paise INTEGER DEFAULT NULL,
  p_duration_hours INTEGER DEFAULT 3,
  p_max_kids INTEGER DEFAULT NULL,
  p_max_adults INTEGER DEFAULT NULL,
  p_cover_image_url TEXT DEFAULT NULL,
  p_gallery_image_urls TEXT[] DEFAULT NULL,
  p_inclusions JSONB DEFAULT '[]'::jsonb,
  p_menu_options JSONB DEFAULT '{}'::jsonb,
  p_non_food_offerings JSONB DEFAULT '[]'::jsonb,
  p_available_days JSONB DEFAULT '{"weekday":true,"weekend":true,"specific_dates":[]}'::jsonb,
  p_hero_theme TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT TRUE,
  p_sort_order INTEGER DEFAULT 0,
  p_hall_name TEXT DEFAULT NULL,
  p_min_guests INTEGER DEFAULT NULL,
  p_max_guests INTEGER DEFAULT NULL,
  p_price_per_pax_veg_paise INTEGER DEFAULT NULL,
  p_price_per_pax_non_veg_paise INTEGER DEFAULT NULL,
  p_pdf_url TEXT DEFAULT NULL,
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  UPDATE birthday_packages SET
    name = p_name, tier = p_tier, description = p_description,
    price_paise = p_price_paise, deposit_paise = p_deposit_paise,
    duration_hours = p_duration_hours,
    max_kids = p_max_kids, max_adults = p_max_adults,
    cover_image_url = p_cover_image_url,
    gallery_image_urls = p_gallery_image_urls,
    inclusions = p_inclusions, menu_options = p_menu_options,
    non_food_offerings = p_non_food_offerings, available_days = p_available_days,
    hero_theme = p_hero_theme, is_active = p_is_active, sort_order = p_sort_order,
    hall_name = p_hall_name, min_guests = p_min_guests, max_guests = p_max_guests,
    price_per_pax_veg_paise = p_price_per_pax_veg_paise,
    price_per_pax_non_veg_paise = p_price_per_pax_non_veg_paise,
    pdf_url = p_pdf_url,
    experience_inclusions = p_experience_inclusions
  WHERE id = p_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'package.update', 'birthday_packages', p_id,
    jsonb_build_object('name', p_name, 'tier', p_tier, 'hall_name', p_hall_name)
  );

  RETURN jsonb_build_object('success', true);
END $$;
