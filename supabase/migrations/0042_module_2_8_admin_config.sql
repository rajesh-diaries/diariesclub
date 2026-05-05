-- Module 2.8 — admin config UI surface area.
--
-- 1. Expand admin_set_venue_config whitelist to cover the additional
--    knobs surfaced in the new admin config screens (XP economy, stage
--    thresholds, milestones, birthday parameters, contact info, JSONB
--    knobs like session_extension_options + pre_booking_slots_per_day).
--
-- 2. Add admin_* RPCs for content tables that already exist but had no
--    edit surface: reflection_moments + hero_card_definitions.
--
-- Notification copy templates intentionally NOT included — call sites
-- currently use hardcoded strings, so an admin-editable templates
-- table is a v1.1 follow-up that requires refactoring sendNotification
-- (and similar) call sites.

-- ---------------------------------------------------------------------
-- 1. Expanded admin_set_venue_config whitelist.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_venue_config(
  p_venue_id uuid,
  p_patch    jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old JSONB;
  v_key TEXT;
  v_allowed TEXT[] := ARRAY[
    -- Pricing.
    'session_1hr_price_paise', 'session_2hr_price_paise',
    'session_extension_per_hour_paise', 'overtime_per_min_paise',
    'session_extension_options', 'pre_booking_slots_per_day',
    -- GST.
    'gst_percent', 'walkin_food_gst_percent',
    -- Cashback / referrals / reactivation.
    'cashback_percent', 'topup_offers',
    'low_balance_threshold_paise',
    'reactivation_credit_paise', 'reactivation_expiry_days',
    'referral_gifter_credit_paise', 'referral_new_family_credit_paise',
    'referral_monthly_cap_paise',
    'churn_threshold_days',
    -- XP economy.
    'xp_per_session_minute', 'xp_reflection_participation',
    'xp_healthy_bite', 'xp_workshop_attendance',
    'xp_birthday_hosted', 'xp_birthday_guest',
    'xp_first_session', 'xp_streak_bonus',
    'xp_referral_bonus_rafi', 'xp_birthday_bonus',
    'stage_thresholds_per_trait', 'level_thresholds',
    'stage_imminent_xp_gap',
    -- Milestones.
    'visit_milestones',
    -- Birthday.
    'birthday_reservation_autocancel_hours',
    'birthday_home_card_threshold_days',
    'birthday_interest_ttl_hours',
    'birthday_booking_enabled',
    'child_birthday_wish_enabled',
    'child_birthday_wish_time',
    'child_birthday_wish_copy_celebrating',
    'child_birthday_wish_copy_default',
    -- Sessions.
    'session_grace_period_minutes', 'session_grace_max_minutes',
    'session_extend_nudge_after_minutes',
    'session_force_close_after_grace_minutes',
    'session_pre_scan_timeout_minutes',
    'qr_validity_minutes', 'otp_validity_minutes',
    'reflection_window_hours',
    'pre_booking_hold_percent', 'pre_booking_grace_minutes',
    'max_sessions_per_family_per_day',
    -- Feature flags.
    'healthy_bite_enabled', 'workshops_enabled',
    'wall_of_legends_enabled', 'wall_of_legends_anonymise',
    'marketing_opt_in_default', 'require_two_person_for_debit',
    -- Versioning + ops.
    'ios_min_supported_version', 'ios_latest_version',
    'android_min_supported_version', 'android_latest_version',
    'force_update_message',
    'staff_refund_cap_paise',
    'cash_discrepancy_alert_threshold_paise',
    -- Contact / URLs.
    'whatsapp_support_phone',
    'venue_phone', 'venue_address', 'venue_email', 'venue_maps_url',
    'privacy_policy_url', 'terms_of_service_url',
    'refund_policy_url', 'marketing_site_url'
  ];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF NOT (v_key = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'config_key_not_allowed: %', v_key;
    END IF;
  END LOOP;

  SELECT jsonb_object_agg(key, value) INTO v_old FROM (
    SELECT k AS key, to_jsonb(venue_config) -> k AS value
      FROM venue_config, jsonb_object_keys(p_patch) k
     WHERE venue_id = p_venue_id
  ) t;

  -- Walk each key. Cast scalars via ->>; pass JSONB columns through as-is.
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF (SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'venue_config'
            AND column_name = v_key) = 'jsonb' THEN
      EXECUTE format(
        'UPDATE venue_config SET %I = $1->%L WHERE venue_id = $2',
        v_key, v_key
      ) USING p_patch, p_venue_id;
    ELSE
      EXECUTE format(
        'UPDATE venue_config SET %I = ($1->>%L)::%s WHERE venue_id = $2',
        v_key, v_key,
        (SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'venue_config'
            AND column_name = v_key)
      ) USING p_patch, p_venue_id;
    END IF;
  END LOOP;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id,
    old_value, new_value
  ) VALUES (
    auth.uid(), 'admin', 'config.update', 'venue_config', p_venue_id,
    p_venue_id, v_old, p_patch
  );

  RETURN jsonb_build_object('success', true, 'updated_keys', p_patch);
END $function$;

REVOKE EXECUTE ON FUNCTION public.admin_set_venue_config(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_set_venue_config(uuid, jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- 2. reflection_moments admin CRUD.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reflection_moment_upsert(
  p_id            uuid,
  p_tag           text,
  p_display_text  text,
  p_icon          text,
  p_primary_trait text,
  p_xp_weight     numeric,
  p_sort_order    integer,
  p_is_active     boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_primary_trait NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_trait: %', p_primary_trait;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO reflection_moments(
      tag, display_text, icon, primary_trait, xp_weight, sort_order, is_active
    ) VALUES (
      p_tag, p_display_text, p_icon, p_primary_trait,
      COALESCE(p_xp_weight, 1), COALESCE(p_sort_order, 0),
      COALESCE(p_is_active, true)
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE reflection_moments
       SET tag           = COALESCE(p_tag, tag),
           display_text  = COALESCE(p_display_text, display_text),
           icon          = COALESCE(p_icon, icon),
           primary_trait = COALESCE(p_primary_trait, primary_trait),
           xp_weight     = COALESCE(p_xp_weight, xp_weight),
           sort_order    = COALESCE(p_sort_order, sort_order),
           is_active     = COALESCE(p_is_active, is_active)
     WHERE id = p_id
     RETURNING id INTO v_id;

    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'reflection_moment.create' ELSE 'reflection_moment.update' END,
    'reflection_moment', v_id,
    jsonb_build_object(
      'tag', p_tag, 'display_text', p_display_text,
      'primary_trait', p_primary_trait, 'is_active', p_is_active
    )
  );

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_reflection_moment_upsert(
  uuid, text, text, text, text, numeric, integer, boolean
) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_reflection_moment_upsert(
  uuid, text, text, text, text, numeric, integer, boolean
) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. hero_card_definitions admin CRUD.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_hero_card_upsert(
  p_id                   uuid,
  p_name                 text,
  p_hero                 text,
  p_description          text,
  p_image_url            text,
  p_is_rare              boolean,
  p_is_birthday_exclusive boolean,
  p_is_active            boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero: %', p_hero;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO hero_card_definitions(
      name, hero, description, image_url,
      is_rare, is_birthday_exclusive, is_active
    ) VALUES (
      p_name, p_hero, p_description, p_image_url,
      COALESCE(p_is_rare, false),
      COALESCE(p_is_birthday_exclusive, false),
      COALESCE(p_is_active, true)
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE hero_card_definitions
       SET name                  = COALESCE(p_name, name),
           hero                  = COALESCE(p_hero, hero),
           description           = COALESCE(p_description, description),
           image_url             = COALESCE(p_image_url, image_url),
           is_rare               = COALESCE(p_is_rare, is_rare),
           is_birthday_exclusive = COALESCE(p_is_birthday_exclusive, is_birthday_exclusive),
           is_active             = COALESCE(p_is_active, is_active)
     WHERE id = p_id
     RETURNING id INTO v_id;

    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'hero_card.create' ELSE 'hero_card.update' END,
    'hero_card', v_id,
    jsonb_build_object(
      'name', p_name, 'hero', p_hero,
      'is_rare', p_is_rare, 'is_active', p_is_active
    )
  );

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_hero_card_upsert(
  uuid, text, text, text, text, boolean, boolean, boolean
) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_hero_card_upsert(
  uuid, text, text, text, text, boolean, boolean, boolean
) TO authenticated;

COMMENT ON FUNCTION public.admin_set_venue_config IS
'Whitelisted patch updater for venue_config. Module 2.8 expands the whitelist to cover XP economy, milestones, birthday parameters, contact info and JSONB knobs.';

COMMENT ON FUNCTION public.admin_reflection_moment_upsert IS
'Module 2.8 — admin CRUD for reflection_moments. NULL p_id creates; otherwise updates by id (NULL fields are kept).';

COMMENT ON FUNCTION public.admin_hero_card_upsert IS
'Module 2.8 — admin CRUD for hero_card_definitions. NULL p_id creates; otherwise updates by id (NULL fields are kept).';
