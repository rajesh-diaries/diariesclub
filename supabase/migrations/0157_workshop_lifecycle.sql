-- 0157 — Workshop lifecycle: auto-close, pre-event reminder, attendance push.
--
-- Three behaviours added so a workshop end-to-end runs without admin
-- babysitting:
--   1. workshop_close_past_due() — flips status='upcoming' → 'completed'
--      once scheduled_at + duration_minutes passes. Solves "May 16
--      workshop still says Upcoming on May 18" UI bug.
--   2. workshop_send_reminders() — fires a "Starting soon" push to every
--      registered family N minutes before scheduled_at (N is
--      venue_config.workshop_reminder_minutes_before, admin-editable;
--      default 30). Dedups via workshop_registrations.reminded_at.
--   3. workshop_attend RPC patched to send "{{child}} just joined!"
--      push to the parent at the moment staff marks attended.
--
-- A separate Edge Function `workshop-lifecycle-cron` ticks every minute
-- and calls (1) + (2). Schedule rows added in this migration.

-- ── Schema additions ────────────────────────────────────────────────────
ALTER TABLE workshop_registrations
  ADD COLUMN IF NOT EXISTS reminded_at TIMESTAMPTZ;

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS workshop_reminder_minutes_before
    INTEGER NOT NULL DEFAULT 30;

-- ── Notification templates ──────────────────────────────────────────────
INSERT INTO notification_templates(
  type, category, enabled, title, body, deep_link_template,
  variables, preference_key
) VALUES (
  'workshop_starting_soon',
  'workshop',
  true,
  'Starting soon ✨',
  '{{title}} starts in {{minutes}} min. See you there, {{child_name}}!',
  '/profile/workshops',
  '["title","minutes","child_name","workshop_id"]'::jsonb,
  'workshop_reminders'
)
ON CONFLICT (type) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  title   = EXCLUDED.title,
  body    = EXCLUDED.body,
  deep_link_template = EXCLUDED.deep_link_template,
  preference_key = EXCLUDED.preference_key,
  variables = EXCLUDED.variables;

INSERT INTO notification_templates(
  type, category, enabled, title, body, deep_link_template,
  variables, preference_key
) VALUES (
  'workshop_attended',
  'workshop',
  true,
  'Welcome in! 🎨',
  '{{child_name}} just joined {{title}}.',
  '/profile/workshops',
  '["title","child_name","workshop_id"]'::jsonb,
  'workshop_reminders'
)
ON CONFLICT (type) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  title   = EXCLUDED.title,
  body    = EXCLUDED.body,
  deep_link_template = EXCLUDED.deep_link_template,
  preference_key = EXCLUDED.preference_key,
  variables = EXCLUDED.variables;

-- ── workshop_close_past_due ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.workshop_close_past_due()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE workshops
     SET status = 'completed'
   WHERE status = 'upcoming'
     AND scheduled_at + (duration_minutes || ' minutes')::INTERVAL < now();
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count > 0 THEN
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
    VALUES (NULL, 'system', 'workshop.auto_close', 'workshop', NULL,
            jsonb_build_object('closed_count', v_count));
  END IF;

  RETURN jsonb_build_object('closed_count', v_count);
END $function$;

-- ── workshop_send_reminders ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.workshop_send_reminders()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_lead_minutes INTEGER;
  v_window INTERVAL;
  r RECORD;
BEGIN
  -- Use first venue's config (single-venue MVP); easy to per-venue later.
  SELECT COALESCE(workshop_reminder_minutes_before, 30)
    INTO v_lead_minutes
    FROM venue_config LIMIT 1;
  v_window := (v_lead_minutes || ' minutes')::INTERVAL;

  -- A registration is "due for reminder" when the workshop is starting
  -- within the next v_lead_minutes, hasn't started yet, registration
  -- isn't cancelled, and we haven't already reminded.
  FOR r IN
    SELECT wr.id AS registration_id,
           wr.family_id,
           wr.child_id,
           w.id AS workshop_id,
           w.title,
           w.scheduled_at,
           ROUND(EXTRACT(EPOCH FROM (w.scheduled_at - now())) / 60)::INTEGER AS minutes_left,
           c.name AS child_name
      FROM workshop_registrations wr
      JOIN workshops w ON w.id = wr.workshop_id
      LEFT JOIN children c ON c.id = wr.child_id
     WHERE w.status = 'upcoming'
       AND w.scheduled_at > now()
       AND w.scheduled_at <= now() + v_window
       AND wr.cancelled_at IS NULL
       AND wr.reminded_at IS NULL
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => r.family_id,
        p_type         => 'workshop_starting_soon',
        p_args         => jsonb_build_object(
          'title',       r.title,
          'minutes',     r.minutes_left::TEXT,
          'child_name',  COALESCE(r.child_name, 'your kid'),
          'workshop_id', r.workshop_id::TEXT
        ),
        p_reference_id => r.workshop_id
      );
      UPDATE workshop_registrations
         SET reminded_at = now()
       WHERE id = r.registration_id;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'workshop.reminder.notify_failed',
              'workshop_registration', r.registration_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;

  RETURN jsonb_build_object('reminded_count', v_count, 'lead_minutes', v_lead_minutes);
END $function$;

-- ── Patch workshop_attend to fire attendance push ───────────────────────
-- Preserves all existing behaviour (per-trait XP split, streak_update,
-- audit row) and only adds the parent-facing push between XP credit
-- and the audit-log insert.
CREATE OR REPLACE FUNCTION public.workshop_attend(p_registration_id uuid, p_staff_pin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_reg workshop_registrations%ROWTYPE;
  v_wshop workshops%ROWTYPE;
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_xp INTEGER;
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena INTEGER := 0;
BEGIN
  SELECT * INTO v_reg FROM workshop_registrations WHERE id = p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_reg.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'already_cancelled'; END IF;
  IF v_reg.attended THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  SELECT * INTO v_wshop FROM workshops WHERE id = v_reg.workshop_id;
  SELECT * INTO v_child FROM children WHERE id = v_reg.child_id;
  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_wshop.venue_id;
  v_xp := COALESCE(v_wshop.xp_award, v_config.xp_workshop_attendance);

  IF v_wshop.primary_trait IS NULL THEN
    v_xp_rafi  := v_xp / 4;
    v_xp_ellie := v_xp / 4;
    v_xp_gerry := v_xp / 4;
    v_xp_zena  := v_xp - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  ELSE
    v_xp_rafi  := CASE WHEN v_wshop.primary_trait = 'rafi'  THEN v_xp ELSE 0 END;
    v_xp_ellie := CASE WHEN v_wshop.primary_trait = 'ellie' THEN v_xp ELSE 0 END;
    v_xp_gerry := CASE WHEN v_wshop.primary_trait = 'gerry' THEN v_xp ELSE 0 END;
    v_xp_zena  := CASE WHEN v_wshop.primary_trait = 'zena'  THEN v_xp ELSE 0 END;
  END IF;

  PERFORM xp_credit_with_split(
    v_reg.child_id, v_reg.family_id, v_wshop.venue_id,
    'workshop',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    v_reg.id, jsonb_build_object('workshop_id', v_wshop.id)
  );

  UPDATE workshop_registrations SET
    attended = true, xp_credited = true
  WHERE id = p_registration_id;

  PERFORM streak_update(v_reg.child_id, v_wshop.venue_id);

  -- Attendance push to parent (best-effort: failure must not break attend)
  BEGIN
    PERFORM public._send_notification(
      p_family_id    => v_reg.family_id,
      p_type         => 'workshop_attended',
      p_args         => jsonb_build_object(
        'title',       v_wshop.title,
        'child_name',  COALESCE(v_child.name, 'your kid'),
        'workshop_id', v_wshop.id::TEXT
      ),
      p_reference_id => v_wshop.id
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'workshop.attend.notify_failed',
            'workshop_registration', p_registration_id, v_wshop.venue_id,
            jsonb_build_object('error', SQLERRM));
  END;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'workshop.attend', 'workshop_registration', p_registration_id,
          v_wshop.venue_id,
          jsonb_build_object('xp_award', v_xp, 'primary_trait', v_wshop.primary_trait));

  RETURN jsonb_build_object('success', true, 'xp_credited', v_xp);
END $function$;

-- ── Whitelist new venue_config key in admin_set_venue_config ────────────
-- Done by re-extending the array via a separate ALTER. The function is
-- regenerated by 0156; we just append the new key here.
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
    'coffee_diaries_tagline', 'fit_diaries_tagline', 'workshops_tagline',
    'birthday_celebrations_count', 'birthday_happy_kids_count',
    'birthday_testimonials',
    'birthday_brochure_url',
    'workshop_reminder_minutes_before'
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
