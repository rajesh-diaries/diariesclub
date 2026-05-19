-- 0154 — Admin-editable taglines for Coffee Diaries / FIT Diaries / Workshops
--        + delete pre-launch seed coffee items in the OLD taxonomy.
--
-- Customer-facing copy on the three Club sections is moving from hardcoded
-- Dart strings to venue_config so the founder can edit live.
--
--   coffee_diaries_tagline   → Cafe hero banner subtitle
--   fit_diaries_tagline      → new FIT hero banner subtitle
--   workshops_tagline        → workshops list-page subtitle
--                              (was: "Themed sessions earn extra XP.")
--
-- Per founder content policy: all three default to NULL. UI hides the
-- tagline row if empty so nothing pretends to be authored.
--
-- Also one-shot cleanup of 15 seed-only menu_items in the Coffee Diaries
-- menu that used the old taxonomy (LEAN/Cold/Espresso/Tea). Founder is
-- re-authoring categories per the new 10-category list (Coffee, Ice Tea,
-- Milkshakes, Mocktails, Quick Bites, Sandwiches, Noodles, Pizzas, Pasta,
-- Last Bites). Dev-phase data — no real customer ever ordered these.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS coffee_diaries_tagline TEXT,
  ADD COLUMN IF NOT EXISTS fit_diaries_tagline    TEXT,
  ADD COLUMN IF NOT EXISTS workshops_tagline      TEXT;

-- Soft-delete (rather than DELETE) because some test orders reference
-- these rows via order_items.menu_item_id FK. Setting both flags hides
-- them from the customer menu and the chip-derivation logic without
-- breaking order history.
UPDATE menu_items
   SET is_published = false,
       is_available = false,
       updated_at   = now()
 WHERE menu_id IN (SELECT id FROM menus WHERE brand = 'coffee')
   AND category IN ('LEAN', 'Cold', 'Espresso', 'Tea',
                    'cold', 'espresso', 'tea', 'lean');

CREATE OR REPLACE FUNCTION public.admin_set_venue_config(p_venue_id uuid, p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old JSONB;
  v_key TEXT;
  v_allowed TEXT[] := ARRAY[
    'session_1hr_price_paise', 'session_2hr_price_paise',
    'session_extension_per_hour_paise', 'overtime_per_min_paise',
    'session_extension_options', 'pre_booking_slots_per_day',
    'gst_percent', 'walkin_food_gst_percent',
    'cashback_percent', 'topup_offers',
    'low_balance_threshold_paise',
    'reactivation_credit_paise', 'reactivation_expiry_days',
    'referral_gifter_credit_paise', 'referral_new_family_credit_paise',
    'referral_monthly_cap_paise', 'churn_threshold_days',
    'xp_per_session_minute', 'xp_reflection_participation',
    'xp_healthy_bite', 'xp_workshop_attendance',
    'xp_birthday_hosted', 'xp_birthday_guest',
    'xp_first_session', 'xp_streak_bonus',
    'xp_referral_bonus_rafi', 'xp_birthday_bonus',
    'xp_referral_bonus_trait', 'xp_healthy_bite_trait',
    'xp_birthday_hosted_trait', 'xp_birthday_guest_trait',
    'xp_birthday_bonus_trait', 'xp_first_session_trait',
    'xp_streak_bonus_trait',
    'stage_thresholds_per_trait', 'level_thresholds',
    'stage_imminent_xp_gap', 'visit_milestones',
    'birthday_reservation_autocancel_hours',
    'birthday_home_card_threshold_days',
    'birthday_interest_ttl_hours', 'birthday_booking_enabled',
    'child_birthday_wish_enabled', 'child_birthday_wish_time',
    'child_birthday_wish_copy_celebrating',
    'child_birthday_wish_copy_default',
    'session_grace_period_minutes', 'session_grace_max_minutes',
    'session_extend_nudge_after_minutes',
    'session_force_close_after_grace_minutes',
    'session_pre_scan_timeout_minutes',
    'qr_validity_minutes', 'otp_validity_minutes',
    'reflection_window_hours',
    'pre_booking_hold_percent', 'pre_booking_grace_minutes',
    'max_sessions_per_family_per_day',
    'healthy_bite_enabled', 'workshops_enabled',
    'wall_of_legends_enabled', 'wall_of_legends_anonymise',
    'marketing_opt_in_default', 'require_two_person_for_debit',
    'ios_min_supported_version', 'ios_latest_version',
    'android_min_supported_version', 'android_latest_version',
    'force_update_message', 'staff_refund_cap_paise',
    'cash_discrepancy_alert_threshold_paise',
    'whatsapp_support_phone',
    'venue_phone', 'venue_address', 'venue_email', 'venue_maps_url',
    'privacy_policy_url', 'terms_of_service_url',
    'refund_policy_url', 'marketing_site_url',
    'fit_whatsapp_phone', 'fit_app_url',
    'gstin', 'food_gst_percent', 'business_name',
    'coffee_diaries_tagline', 'fit_diaries_tagline', 'workshops_tagline'
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
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF (SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'venue_config'
            AND column_name = v_key) = 'jsonb' THEN
      EXECUTE format('UPDATE venue_config SET %I = $1->%L WHERE venue_id = $2',
        v_key, v_key) USING p_patch, p_venue_id;
    ELSE
      EXECUTE format('UPDATE venue_config SET %I = ($1->>%L)::%s WHERE venue_id = $2',
        v_key, v_key,
        (SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'venue_config'
            AND column_name = v_key)
      ) USING p_patch, p_venue_id;
    END IF;
  END LOOP;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id,
                        venue_id, old_value, new_value)
  VALUES (auth.uid(), 'admin', 'config.update', 'venue_config', p_venue_id,
          p_venue_id, v_old, p_patch);
  RETURN jsonb_build_object('success', true, 'updated_keys', p_patch);
END $function$;
