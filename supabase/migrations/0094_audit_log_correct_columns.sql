-- 0094 — Fix audit_log INSERTs in 8 admin RPCs that used wrong column
-- names. Canonical audit_log schema: actor_id, actor_type, action,
-- entity_type, entity_id, new_value (not actor_user_id / entity /
-- payload). Only the audit_log INSERT changes in each function;
-- bodies are otherwise unchanged.

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

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'menu_item.bulk_set', 'menu_items', NULL,
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

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'menu_item.set_price', 'menu_items', p_id,
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

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'menu_category.rename', 'menus', NULL,
    jsonb_build_object(
      'brand', p_brand, 'from', p_from, 'to', p_to, 'updated', v_updated
    )
  );

  RETURN jsonb_build_object('success', true, 'updated', v_updated);
END $$;

CREATE OR REPLACE FUNCTION admin_hero_within_set_birthday_upgrade(
  p_child_id UUID,
  p_granted BOOLEAN,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row hero_within_unlocks%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  UPDATE hero_within_unlocks
     SET granted_birthday_upgrade = p_granted,
         granted_birthday_upgrade_at =
           CASE WHEN p_granted THEN COALESCE(granted_birthday_upgrade_at, now())
                ELSE NULL END,
         notes = COALESCE(p_notes, notes)
   WHERE child_id = p_child_id
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'hero_within_not_unlocked' USING HINT = p_child_id::text;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'hero_within.birthday_upgrade', 'children', p_child_id,
    jsonb_build_object('granted', p_granted, 'notes', p_notes)
  );

  RETURN to_jsonb(v_row);
END $$;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_edit(
  p_reservation_id UUID,
  p_package_id UUID DEFAULT NULL,
  p_slot_date DATE DEFAULT NULL,
  p_slot TEXT DEFAULT NULL,
  p_guest_count INTEGER DEFAULT NULL,
  p_special_requests TEXT DEFAULT NULL,
  p_admin_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  IF p_slot IS NOT NULL AND p_slot NOT IN ('morning','evening') THEN
    RAISE EXCEPTION 'invalid_slot';
  END IF;
  IF p_guest_count IS NOT NULL AND p_guest_count <= 0 THEN
    RAISE EXCEPTION 'invalid_guest_count';
  END IF;

  UPDATE birthday_reservations SET
    package_id       = COALESCE(p_package_id, package_id),
    slot_date        = COALESCE(p_slot_date, slot_date),
    slot             = COALESCE(p_slot, slot),
    num_kids         = COALESCE(p_guest_count, num_kids),
    special_requests = COALESCE(p_special_requests, special_requests),
    admin_notes      = COALESCE(p_admin_notes, admin_notes)
  WHERE id = p_reservation_id
  RETURNING * INTO v_res;

  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'birthday.edit', 'birthday_reservations', p_reservation_id,
    jsonb_build_object(
      'package_id', p_package_id, 'slot_date', p_slot_date,
      'slot', p_slot, 'guest_count', p_guest_count,
      'special_requests', p_special_requests, 'admin_notes', p_admin_notes
    )
  );

  RETURN to_jsonb(v_res);
END $$;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_cancel(
  p_reservation_id UUID,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  UPDATE birthday_reservations SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_reason = p_reason
  WHERE id = p_reservation_id
    AND status IN ('interested','admin_contacted','confirmed')
  RETURNING * INTO v_res;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_cancellable';
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'birthday.cancel', 'birthday_reservations', p_reservation_id,
    jsonb_build_object('reason', p_reason)
  );

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_90',
    'Inquiry update',
    'Your birthday inquiry was cancelled. Reach us to discuss alternatives.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  RETURN to_jsonb(v_res);
END $$;

-- admin_package_create + admin_package_update are recreated with the
-- single canonical signature (with p_experience_inclusions + p_category)
-- and the corrected audit_log INSERT. See the dedicated drop in 0095
-- for the older overloads that need removing.

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
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb,
  p_category TEXT DEFAULT 'birthday'
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
    pdf_url, experience_inclusions, category
  ) VALUES (
    p_venue_id, p_name, p_tier, p_description,
    p_price_paise, p_deposit_paise,
    p_duration_hours, p_max_kids, p_max_adults,
    p_cover_image_url, p_gallery_image_urls,
    p_inclusions, p_menu_options, p_non_food_offerings, p_available_days,
    p_hero_theme, p_sort_order, true,
    p_hall_name, p_min_guests, p_max_guests,
    p_price_per_pax_veg_paise, p_price_per_pax_non_veg_paise,
    p_pdf_url, p_experience_inclusions, p_category
  ) RETURNING id INTO v_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'package.create', 'birthday_packages', v_id,
    jsonb_build_object(
      'name', p_name, 'tier', p_tier,
      'hall_name', p_hall_name, 'category', p_category
    )
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
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb,
  p_category TEXT DEFAULT 'birthday'
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
    experience_inclusions = p_experience_inclusions,
    category = p_category
  WHERE id = p_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'package.update', 'birthday_packages', p_id,
    jsonb_build_object(
      'name', p_name, 'tier', p_tier,
      'hall_name', p_hall_name, 'category', p_category
    )
  );

  RETURN jsonb_build_object('success', true);
END $$;
