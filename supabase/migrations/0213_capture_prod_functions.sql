-- 0213_capture_prod_functions.sql
-- FULL-CONVERGENCE (DRAFT — not applied). Captures prod's current definitions for the
-- 9 functions missing from the repo + 29 functions where prod is ahead of the repo, so a
-- from-scratch replay reproduces prod. All are CREATE OR REPLACE (idempotent no-op on prod).
-- Reconstructed from live prod 2026-07-03. Ordering is safe: CREATE OR REPLACE
-- defers body resolution; the 3 tables they touch come from 0210.

CREATE OR REPLACE FUNCTION public._card_grant_surprise_inner(p_child_id uuid, p_card_id uuid, p_actor_id uuid, p_actor_type text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_child children%ROWTYPE;
  v_already_owned BOOLEAN;
  v_inserted BOOLEAN;
  v_collection_id UUID;
BEGIN
  SELECT * INTO v_card FROM hero_card_definitions WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'card_not_found'; END IF;
  IF NOT v_card.is_active THEN RAISE EXCEPTION 'card_inactive'; END IF;
  IF v_card.unlock_method <> 'surprise' THEN
    RAISE EXCEPTION 'not_a_surprise_card'
      USING DETAIL = format('unlock_method=%s', v_card.unlock_method);
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM hero_card_collection WHERE child_id = p_child_id AND card_id = p_card_id
  ) INTO v_already_owned;

  INSERT INTO hero_card_collection(child_id, card_id)
  VALUES (p_child_id, p_card_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = hero_card_collection.earned_at
  RETURNING id INTO v_collection_id;

  v_inserted := NOT v_already_owned;

  IF v_inserted THEN
    PERFORM public._send_notification(
      v_child.family_id, 'hero_card_received',
      jsonb_build_object(
        'collection_id', v_collection_id::text,
        'card_name',     v_card.name,
        'child_name',    v_child.name,
        'card_rarity',   'surprise'
      ),
      NULL, p_child_id
    );

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
    VALUES (
      p_actor_id, p_actor_type, 'hero_card.grant_surprise', 'child', p_child_id,
      jsonb_build_object(
        'card_id', p_card_id, 'card_name', v_card.name,
        'hero', v_card.hero, 'collection_id', v_collection_id, 'note', p_note
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'newly_granted', v_inserted,
    'card_id', p_card_id, 'card_name', v_card.name,
    'hero', v_card.hero, 'collection_id', v_collection_id
  );
END $function$
;

CREATE OR REPLACE FUNCTION public._dismiss_session_closed_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.reflection_status IS DISTINCT FROM OLD.reflection_status
     AND NEW.reflection_status IN ('reflected', 'auto_split') THEN
    DELETE FROM notifications
    WHERE type = 'session_closed'
      AND reference_id = NEW.session_id;
  END IF;
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION public._fanout_announcement_published(p_announcement_id uuid, p_title text, p_body text, p_cta_route text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_body  TEXT;
  v_row   RECORD;
BEGIN
  v_body := COALESCE(LEFT(p_body, 120), '');
  IF length(COALESCE(p_body, '')) > 120 THEN
    v_body := v_body || '…';
  END IF;

  FOR v_row IN
    SELECT f.id AS family_id
      FROM families f
     WHERE f.deleted_at IS NULL
       AND f.is_anonymised = FALSE
       AND f.is_walk_in = FALSE
       AND COALESCE((f.notification_preferences->>'announcements')::BOOLEAN, TRUE) = TRUE
  LOOP
    -- REFACTORED: title/body/deep_link come from the template, with the
    -- announcement's own title/body/cta_route substituted into the
    -- {{announcement_title}} / {{announcement_body}} / {{cta_route}}
    -- placeholders the seed defined.
    PERFORM public._send_notification(
      p_family_id    => v_row.family_id,
      p_type         => 'announcement_published',
      p_args         => jsonb_build_object(
        'announcement_title', p_title,
        'announcement_body',  v_body,
        'cta_route',          COALESCE(p_cta_route, '/home')
      ),
      p_reference_id => p_announcement_id
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END $function$
;

CREATE OR REPLACE FUNCTION public._fanout_workshop_published(p_workshop_id uuid, p_title text, p_scheduled_at timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_when  TEXT;
  v_row   RECORD;
BEGIN
  v_when := to_char(p_scheduled_at AT TIME ZONE 'Asia/Kolkata', 'Dy Mon DD, HH12:MIam');
  FOR v_row IN
    SELECT f.id AS family_id FROM families f
     WHERE f.deleted_at IS NULL AND f.is_anonymised = FALSE AND f.is_walk_in = FALSE
       AND COALESCE((f.notification_preferences->>'workshop_reminders')::BOOLEAN, TRUE) = TRUE
  LOOP
    PERFORM public._send_notification(
      v_row.family_id, 'workshop_reminder',
      jsonb_build_object('title', p_title, 'formatted_datetime', v_when, 'workshop_id', p_workshop_id::text),
      NULL, p_workshop_id
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$
;

CREATE OR REPLACE FUNCTION public._format_name_list(p_names text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
SELECT CASE
  WHEN array_length(p_names,1) IS NULL THEN 'your kid'
  WHEN array_length(p_names,1)=1 THEN p_names[1]
  WHEN array_length(p_names,1)=2 THEN p_names[1]||' & '||p_names[2]
  ELSE array_to_string(p_names[1:array_length(p_names,1)-1],', ')||' & '||p_names[array_length(p_names,1)]
END;
$function$
;

CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
  v_session_ids UUID[];
BEGIN
  FOR r IN
    UPDATE sessions SET healthy_bite_earned = true
    WHERE status='active' AND child_id IS NOT NULL AND family_id IS NULL
      AND healthy_bite_earned = false
      AND expires_at > now() AND expires_at <= now() + interval '10 minutes'
    RETURNING id, family_id, child_id, venue_id
  LOOP
    v_count := v_count + 1;
    v_session_ids := v_session_ids || r.id;
  END LOOP;
  FOR r IN
    SELECT s.family_id, array_agg(DISTINCT COALESCE(c.name,'your kid')) AS names
    FROM sessions s
    JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
    LEFT JOIN children c ON c.id = s.child_id
    GROUP BY s.family_id
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id => r.family_id,
        p_type => 'healthy_bite_earned',
        p_args => jsonb_build_object('child_name', _format_name_list(r.names)),
        p_reference_id => gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'healthy_bite.notify_failed', 'session', NULL, NULL,
              jsonb_build_object('error', SQLERRM, 'family_id', r.family_id));
    END;
  END LOOP;
  RETURN v_count;
END $function$
;

CREATE OR REPLACE FUNCTION public._hero_within_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_existing_id UUID;
BEGIN
  IF NEW.stage_rafi  <> 'legend' OR NEW.stage_ellie <> 'legend'
     OR NEW.stage_gerry <> 'legend' OR NEW.stage_zena  <> 'legend' THEN
    RETURN NEW;
  END IF;

  SELECT child_id INTO v_existing_id FROM hero_within_unlocks WHERE child_id = NEW.id;
  IF FOUND THEN RETURN NEW; END IF;

  INSERT INTO hero_within_unlocks(child_id, family_id, unlocked_at_total_xp)
  VALUES (NEW.id, NEW.family_id, NEW.total_xp)
  ON CONFLICT (child_id) DO NOTHING;

  PERFORM public._send_notification(
    NEW.family_id, 'hero_within_unlocked',
    jsonb_build_object('child_name', NEW.name),
    NULL, NEW.id
  );
  RETURN NEW;
END $function$
;

CREATE OR REPLACE FUNCTION public._hydration_reminder_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER := 0;
  v_session_ids UUID[];
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT id FROM sessions WHERE status='active' AND started_at <= v_now - INTERVAL '20 minutes' AND hydration_reminded_at IS NULL
  LOOP
    UPDATE sessions SET hydration_reminded_at = v_now WHERE id = v_row.id;
    v_session_ids := v_session_ids || v_row.id;
    v_count := v_count + 1;
  END LOOP;
  FOR v_row IN
    SELECT s.family_id, array_agg(DISTINCT COALESCE(c.name,'your kid')) AS names
    FROM sessions s
    JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
    LEFT JOIN children c ON c.id = s.child_id
    GROUP BY s.family_id
  LOOP
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (v_row.family_id, 'hydration_nudge', 'Hydration check 💧',
      CASE WHEN array_length(v_row.names,1)>1
        THEN 'Time for a sip of water — '||_format_name_list(v_row.names)||' need to stay hydrated!'
        ELSE 'Time for a sip of water — keeps the play going strong.' END,
      '/home', gen_random_uuid());
  END LOOP;
  RETURN v_count;
END $function$
;

CREATE OR REPLACE FUNCTION public._mirror_families_fcm_to_devices()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.fcm_token is null or new.fcm_platform is null then
    return new;
  end if;
  if new.fcm_token = coalesce(old.fcm_token, '') and new.fcm_platform = coalesce(old.fcm_platform, '') then
    return new;
  end if;

  -- Detach from any other family
  update public.family_devices
    set is_active = false
    where fcm_token = new.fcm_token
      and family_id <> new.id;

  insert into public.family_devices (family_id, fcm_token, platform, app_version, last_seen_at)
  values (new.id, new.fcm_token, new.fcm_platform, new.app_version, now())
  on conflict (fcm_token) do update
    set family_id    = excluded.family_id,
        platform     = excluded.platform,
        app_version  = coalesce(excluded.app_version, family_devices.app_version),
        last_seen_at = now(),
        is_active    = true;

  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public._send_notification(p_family_id uuid, p_type text, p_args jsonb DEFAULT '{}'::jsonb, p_deep_link_override text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template  notification_templates%ROWTYPE;
  v_variant   JSONB;
  v_title     TEXT;
  v_body      TEXT;
  v_deep_link TEXT;
  v_key       TEXT;
  v_val       TEXT;
  v_id        UUID;
BEGIN
  SELECT * INTO v_template FROM notification_templates WHERE type = p_type;
  IF NOT FOUND THEN
    RAISE WARNING 'notification_template_missing type=%', p_type;
    RETURN NULL;
  END IF;
  IF NOT v_template.enabled THEN RETURN NULL; END IF;

  IF v_template.variants IS NOT NULL
     AND jsonb_typeof(v_template.variants) = 'array'
     AND jsonb_array_length(v_template.variants) > 0 THEN
    v_variant := v_template.variants -> (floor(random() * jsonb_array_length(v_template.variants))::int);
    v_title := COALESCE(v_variant ->> 'title', v_template.title);
    v_body  := COALESCE(v_variant ->> 'body',  v_template.body);
  ELSE
    v_title := v_template.title;
    v_body  := v_template.body;
  END IF;

  v_deep_link := COALESCE(p_deep_link_override, v_template.deep_link_template);

  IF p_args IS NOT NULL AND jsonb_typeof(p_args) = 'object' THEN
    FOR v_key IN SELECT jsonb_object_keys(p_args)
    LOOP
      v_val := COALESCE(p_args ->> v_key, '');
      v_title := REPLACE(v_title, '{{' || v_key || '}}', v_val);
      v_body  := REPLACE(v_body,  '{{' || v_key || '}}', v_val);
      IF v_deep_link IS NOT NULL THEN
        v_deep_link := REPLACE(v_deep_link, '{{' || v_key || '}}', v_val);
      END IF;
    END LOOP;
  END IF;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (p_family_id, p_type, v_title, v_body, v_deep_link, p_reference_id)
  RETURNING id INTO v_id;

  RETURN v_id;
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_cancel(p_reservation_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  UPDATE birthday_reservations SET
    status = 'cancelled', cancelled_at = now(), cancelled_reason = p_reason
  WHERE id = p_reservation_id
    AND status IN ('interested','admin_contacted','confirmed')
  RETURNING * INTO v_res;

  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_cancellable'; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (auth.uid(), 'admin', 'birthday.cancel', 'birthday_reservations',
          p_reservation_id, jsonb_build_object('reason', p_reason));

  PERFORM public._send_notification(
    v_res.family_id, 'birthday_d_minus_90',
    jsonb_build_object('reservation_id', v_res.id::text),
    NULL, v_res.id
  );

  RETURN to_jsonb(v_res);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_confirm(p_reservation_id uuid, p_slot_date date, p_slot_start_time time without time zone, p_slot_end_time time without time zone, p_deposit_paid_paise integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('interested','admin_contacted') THEN
    RAISE EXCEPTION 'invalid_state';
  END IF;

  UPDATE birthday_reservations SET
    status = 'confirmed', slot_date = p_slot_date,
    slot_start_time = p_slot_start_time, slot_end_time = p_slot_end_time,
    deposit_paid_paise = p_deposit_paid_paise,
    balance_paise = package_price_paise - p_deposit_paid_paise
  WHERE id = p_reservation_id;

  PERFORM public._send_notification(
    v_res.family_id, 'birthday_d_minus_30',
    jsonb_build_object(
      'reservation_id', v_res.id::text,
      'date', to_char(p_slot_date, 'Dy, Mon DD')
    ),
    NULL, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (auth.uid(), 'admin', 'birthday.confirm', 'birthday_reservation',
          p_reservation_id, v_res.venue_id,
          jsonb_build_object('slot_date', p_slot_date,
            'slot_start_time', p_slot_start_time,
            'deposit_paid_paise', p_deposit_paid_paise));

  RETURN jsonb_build_object('success', true);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_contact(p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status <> 'interested' THEN RAISE EXCEPTION 'invalid_state'; END IF;

  UPDATE birthday_reservations SET status = 'admin_contacted' WHERE id = p_reservation_id;

  PERFORM public._send_notification(
    v_res.family_id, 'birthday_d_minus_60',
    jsonb_build_object('reservation_id', v_res.id::text),
    NULL, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (auth.uid(), 'admin', 'birthday.contact', 'birthday_reservation',
          p_reservation_id, v_res.venue_id);

  RETURN jsonb_build_object('success', true);
END $function$
;

CREATE OR REPLACE FUNCTION public.admin_update_notification_template(p_type text, p_enabled boolean DEFAULT NULL::boolean, p_title text DEFAULT NULL::text, p_body text DEFAULT NULL::text, p_deep_link_template text DEFAULT NULL::text, p_timing_offset_minutes integer DEFAULT NULL::integer, p_variants jsonb DEFAULT NULL::jsonb)
 RETURNS notification_templates
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_row      notification_templates%ROWTYPE;
  v_item     JSONB;
BEGIN
  SELECT id INTO v_admin_id
    FROM admin_users
   WHERE auth_user_id = auth.uid() AND is_active = true;
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'not_admin'; END IF;

  IF p_variants IS NOT NULL THEN
    IF jsonb_typeof(p_variants) <> 'array' THEN
      RAISE EXCEPTION 'variants_must_be_array';
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_variants)
    LOOP
      IF jsonb_typeof(v_item) <> 'object'
         OR v_item ->> 'title' IS NULL OR length(v_item ->> 'title') = 0
         OR v_item ->> 'body'  IS NULL OR length(v_item ->> 'body')  = 0 THEN
        RAISE EXCEPTION 'variant_must_have_title_and_body';
      END IF;
    END LOOP;
  END IF;

  UPDATE notification_templates SET
    enabled               = COALESCE(p_enabled,               enabled),
    title                 = COALESCE(p_title,                 title),
    body                  = COALESCE(p_body,                  body),
    deep_link_template    = COALESCE(p_deep_link_template,    deep_link_template),
    timing_offset_minutes = COALESCE(p_timing_offset_minutes, timing_offset_minutes),
    variants              = COALESCE(p_variants,              variants),
    updated_at            = now(),
    updated_by            = v_admin_id
  WHERE type = p_type
  RETURNING * INTO v_row;

  IF v_row.type IS NULL THEN
    RAISE EXCEPTION 'template_not_found: %', p_type;
  END IF;
  RETURN v_row;
END $function$
;

CREATE OR REPLACE FUNCTION public.birthday_deposit_record(p_reservation_id uuid, p_amount_paise integer, p_razorpay_payment_id text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('success', true, 'idempotent', true); END IF;
  END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('reserved') THEN RAISE EXCEPTION 'invalid_reservation_state'; END IF;

  UPDATE birthday_reservations SET
    deposit_paid_paise = p_amount_paise,
    total_paid_paise = total_paid_paise + p_amount_paise,
    status = 'deposit_paid'
  WHERE id = p_reservation_id;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = v_res.family_id;
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type, razorpay_payment_id, idempotency_key
  ) VALUES (
    v_res.family_id, 'birthday_deposit_debit', -p_amount_paise,
    COALESCE(v_wallet.balance_paise, 0), 'razorpay', p_reservation_id, 'birthday_deposit',
    p_razorpay_payment_id, p_idempotency_key
  );

  PERFORM public._send_notification(
    v_res.family_id, 'birthday_d_minus_90',
    jsonb_build_object('reservation_id', v_res.id::text),
    NULL, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'birthday.deposit', 'birthday_reservation', p_reservation_id,
          v_res.venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'razorpay_payment_id', p_razorpay_payment_id));

  RETURN jsonb_build_object('success', true);
END $function$
;

CREATE OR REPLACE FUNCTION public.birthday_inquiry_submit(p_venue_id uuid, p_family_id uuid, p_child_id uuid, p_package_id uuid, p_slot_date date, p_slot text, p_guest_count integer, p_special_requests text DEFAULT NULL::text, p_triggered_by text DEFAULT 'manual'::text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
  v_res birthday_reservations%ROWTYPE;
  v_birthday_year INTEGER;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_slot IS NULL OR p_slot NOT IN ('morning','evening') THEN RAISE EXCEPTION 'invalid_slot'; END IF;
  IF p_guest_count IS NULL OR p_guest_count <= 0 THEN RAISE EXCEPTION 'invalid_guest_count'; END IF;
  IF p_slot_date IS NULL THEN RAISE EXCEPTION 'invalid_slot_date'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'reservation_id', v_existing.id);
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages
   WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  IF v_pkg.min_guests IS NOT NULL AND p_guest_count < v_pkg.min_guests THEN
    RAISE EXCEPTION 'guest_count_below_min' USING DETAIL = format('min for this package is %s', v_pkg.min_guests);
  END IF;
  IF v_pkg.max_guests IS NOT NULL AND p_guest_count > v_pkg.max_guests THEN
    RAISE EXCEPTION 'guest_count_above_max' USING DETAIL = format('max for this package is %s', v_pkg.max_guests);
  END IF;

  IF EXISTS (
    SELECT 1 FROM birthday_reservations
     WHERE child_id = p_child_id
       AND status IN ('interested','admin_contacted','confirmed')
       AND created_at > now() - INTERVAL '3 months'
  ) THEN RAISE EXCEPTION 'reservation_exists'; END IF;

  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    slot_date, slot, special_requests, num_kids, num_adults,
    package_price_paise, balance_paise, triggered_by, idempotency_key, status
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_package_id,
    p_slot_date, p_slot, p_special_requests, p_guest_count, 0,
    COALESCE(v_pkg.price_per_pax_veg_paise, v_pkg.price_paise), 0,
    p_triggered_by, p_idempotency_key, 'interested'
  ) RETURNING * INTO v_res;

  v_birthday_year := EXTRACT(YEAR FROM p_slot_date)::INTEGER;
  INSERT INTO birthday_journey_state(child_id, reservation_id, birthday_year, arc_type)
  VALUES (p_child_id, v_res.id, v_birthday_year, 'reserved')
  ON CONFLICT (child_id) DO UPDATE
    SET reservation_id = EXCLUDED.reservation_id, arc_type = 'reserved', updated_at = now();

  -- REFACTORED
  PERFORM public._send_notification(
    p_family_id    => p_family_id,
    p_type         => 'birthday_d_minus_90',
    p_args         => jsonb_build_object('reservation_id', v_res.id::text),
    p_reference_id => v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_family_id, 'customer', 'birthday.inquiry_submit', 'birthday_reservation',
    v_res.id, p_venue_id,
    jsonb_build_object('package_id', p_package_id, 'package_name', v_pkg.name,
      'slot_date', p_slot_date, 'slot', p_slot, 'guest_count', p_guest_count,
      'special_requests', p_special_requests, 'triggered_by', p_triggered_by)
  );

  RETURN jsonb_build_object('success', true, 'reservation_id', v_res.id);
END $function$
;

CREATE OR REPLACE FUNCTION public.card_grant_surprise(p_child_id uuid, p_card_id uuid, p_staff_pin_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_child children%ROWTYPE;
BEGIN
  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  -- Staff must be active for the kid's family's venue. We resolve
  -- venue via the family's recent activity rather than a column;
  -- simpler check: staff_pin_id must exist and be active.
  IF NOT EXISTS (
    SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  RETURN _card_grant_surprise_inner(
    p_child_id, p_card_id, p_staff_pin_id, 'staff', p_note
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.child_create(p_name text, p_dob date, p_favourite_hero text DEFAULT 'ellie'::text, p_delivery_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_child children%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM families WHERE id = v_uid) THEN
    RAISE EXCEPTION 'family_not_found';
  END IF;

  IF char_length(coalesce(trim(p_name), '')) < 1 THEN
    RAISE EXCEPTION 'invalid_child_name';
  END IF;

  IF p_dob IS NULL OR p_dob > current_date OR p_dob < current_date - INTERVAL '14 years' THEN
    RAISE EXCEPTION 'invalid_dob';
  END IF;

  IF p_favourite_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero' USING DETAIL = p_favourite_hero;
  END IF;

  INSERT INTO children (
    family_id, name, date_of_birth, favourite_hero, delivery_address
  ) VALUES (
    v_uid, trim(p_name), p_dob, p_favourite_hero, p_delivery_address
  )
  RETURNING * INTO v_child;

  UPDATE families
     SET has_children   = true,
         is_cafe_only   = false,
         last_active_at = now()
   WHERE id = v_uid;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_uid, 'customer', 'child.create', 'child', v_child.id,
    jsonb_build_object(
      'name',           trim(p_name),
      'dob',            p_dob,
      'favourite_hero', p_favourite_hero
    )
  );

  RETURN jsonb_build_object(
    'success',        true,
    'child_id',       v_child.id,
    'name',           v_child.name,
    'date_of_birth',  v_child.date_of_birth,
    'favourite_hero', v_child.favourite_hero
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.child_update(p_child_id uuid, p_name text DEFAULT NULL::text, p_dob date DEFAULT NULL::date, p_favourite_hero text DEFAULT NULL::text, p_delivery_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_family_id UUID := auth.uid();
  v_child children%ROWTYPE;
  v_old   children%ROWTYPE;
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF v_family_id IS NULL THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_child FROM children
    WHERE id = p_child_id AND family_id = v_family_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_child.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'child_archived'; END IF;
  v_old := v_child;

  IF p_name IS NOT NULL THEN
    p_name := btrim(p_name);
    IF length(p_name) = 0 OR length(p_name) > 60 THEN
      RAISE EXCEPTION 'invalid_name';
    END IF;
  END IF;

  IF p_dob IS NOT NULL THEN
    IF p_dob > v_today OR p_dob < (v_today - INTERVAL '14 years') THEN
      RAISE EXCEPTION 'invalid_dob';
    END IF;
  END IF;

  IF p_favourite_hero IS NOT NULL
     AND p_favourite_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero';
  END IF;

  UPDATE children SET
    name             = COALESCE(p_name, name),
    date_of_birth    = COALESCE(p_dob, date_of_birth),
    favourite_hero   = COALESCE(p_favourite_hero, favourite_hero),
    delivery_address = COALESCE(p_delivery_address, delivery_address)
  WHERE id = p_child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    v_family_id, 'customer', 'child.update', 'child', p_child_id,
    jsonb_build_object(
      'name', v_old.name, 'dob', v_old.date_of_birth,
      'favourite_hero', v_old.favourite_hero,
      'delivery_address', v_old.delivery_address
    ),
    jsonb_build_object(
      'name', COALESCE(p_name, v_old.name),
      'dob', COALESCE(p_dob, v_old.date_of_birth),
      'favourite_hero', COALESCE(p_favourite_hero, v_old.favourite_hero),
      'delivery_address', COALESCE(p_delivery_address, v_old.delivery_address)
    )
  );

  RETURN jsonb_build_object('success', true, 'child_id', p_child_id);
END $function$
;

CREATE OR REPLACE FUNCTION public.family_set_birthday_interest(p_child_id uuid, p_interest_state text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_child   children%ROWTYPE;
  v_old     TEXT;
BEGIN
  IF p_interest_state NOT IN ('interested','not_this_year') THEN
    RAISE EXCEPTION 'invalid_interest_state';
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND OR v_child.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'child_not_found';
  END IF;

  PERFORM assert_caller_authority(v_child.family_id, NULL);

  v_old := v_child.birthday_interest_state;

  IF v_old = p_interest_state THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'child_id', v_child.id,
      'birthday_interest_state', v_child.birthday_interest_state
    );
  END IF;

  UPDATE children
     SET birthday_interest_state      = p_interest_state,
         birthday_interest_updated_at = now()
   WHERE id = p_child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_child.family_id, 'customer',
    'birthday.interest_state.update', 'child', p_child_id,
    jsonb_build_object('old', v_old, 'new', p_interest_state)
  );

  RETURN jsonb_build_object(
    'success', true,
    'child_id', v_child.id,
    'birthday_interest_state', p_interest_state
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.force_close_grace_sessions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count      INTEGER := 0;
  v_session    sessions%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_pool       INTEGER;
  v_deadline   TIMESTAMPTZ;
  v_child_name TEXT;
BEGIN
  FOR v_session IN
    SELECT * FROM sessions
    WHERE status IN ('active','grace')
      AND grace_force_close_at IS NOT NULL
      AND now() > grace_force_close_at
    LIMIT 200
  LOOP
    SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
    v_pool     := v_session.duration_minutes * COALESCE(v_config.xp_per_session_minute, 0);
    v_deadline := now() + (COALESCE(v_config.reflection_window_hours, 24) || ' hours')::INTERVAL;

    UPDATE sessions SET
      status              = 'auto_closed',
      completed_at        = now(),
      reflection_deadline = v_deadline,
      total_xp_earned     = v_pool
    WHERE id = v_session.id AND status IN ('active','grace');

    INSERT INTO hero_recaps(
      session_id, child_id, total_xp_pool, reflection_status, reflection_deadline
    ) VALUES (
      v_session.id, v_session.child_id, v_pool, 'pending', v_deadline
    )
    ON CONFLICT (session_id) DO NOTHING;

    SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

    BEGIN
      PERFORM public._send_notification(
        p_family_id    => v_session.family_id,
        p_type         => 'session_closed',
        p_args         => jsonb_build_object(
          'child_name', COALESCE(v_child_name, 'your kid'),
          'session_id', v_session.id::text
        ),
        p_reference_id => v_session.id
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
      VALUES (NULL, 'system', 'session.auto_close.notify_failed', 'session', v_session.id, v_session.venue_id,
              jsonb_build_object('error', SQLERRM));
    END;

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'session.auto_close', 'session', v_session.id, v_session.venue_id,
            jsonb_build_object(
              'previous_status', v_session.status,
              'total_xp_pool', v_pool,
              'reflection_deadline', v_deadline
            ));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'auto_closed_count', v_count);
END $function$
;

CREATE OR REPLACE FUNCTION public.gift_redeem(p_child_id uuid, p_gift_id uuid, p_venue_id uuid, p_staff_pin_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_child children%ROWTYPE;
  v_gift gift_ladder%ROWTYPE;
  v_redemption gift_redemptions%ROWTYPE;
BEGIN
  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  PERFORM assert_caller_authority(v_child.family_id, p_staff_pin_id);

  SELECT * INTO v_gift FROM gift_ladder WHERE id = p_gift_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'gift_not_available'; END IF;

  IF v_child.current_level < v_gift.level_required THEN RAISE EXCEPTION 'level_too_low'; END IF;

  IF EXISTS(SELECT 1 FROM gift_redemptions WHERE child_id = p_child_id AND gift_id = p_gift_id) THEN
    RAISE EXCEPTION 'already_redeemed';
  END IF;

  INSERT INTO gift_redemptions(child_id, gift_id, venue_id, staff_pin_id)
  VALUES (p_child_id, p_gift_id, p_venue_id, p_staff_pin_id)
  RETURNING * INTO v_redemption;

  -- REFACTORED: uses hero_card_received template (same type the original
  -- used). Admin can customize per-type copy; for gift-specific framing
  -- the founder can edit the template to "{{card_name}} is ready..."
  -- and pass gift_name as the card_name var.
  PERFORM public._send_notification(
    p_family_id    => v_child.family_id,
    p_type         => 'hero_card_received',
    p_args         => jsonb_build_object(
      'card_name',     v_gift.gift_name,
      'collection_id', v_redemption.id::text,
      'card_rarity',   'gift'
    ),
    p_reference_id => v_redemption.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_child.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'gift.redeem', 'gift_redemption', v_redemption.id, p_venue_id,
    jsonb_build_object('gift_id', p_gift_id, 'gift_name', v_gift.gift_name)
  );

  RETURN jsonb_build_object(
    'success', true,
    'redemption_id', v_redemption.id,
    'gift_name', v_gift.gift_name,
    'delivery_method', v_gift.delivery_method
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.healthy_bite_distribute(p_session_id uuid, p_child_id uuid, p_staff_pin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_is_rare BOOLEAN;
  v_collection_id UUID;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.healthy_bite_distributed THEN RAISE EXCEPTION 'already_cancelled'; END IF;

  UPDATE sessions SET
    healthy_bite_earned = true, healthy_bite_distributed = true,
    healthy_bite_claimed_at = now()
  WHERE id = p_session_id;

  v_is_rare := random() <= 0.10;

  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare AND is_birthday_exclusive = false AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN RAISE EXCEPTION 'no_cards_available'; END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = hero_card_collection.earned_at
  RETURNING id INTO v_collection_id;

  -- REFACTORED: template body is the single editable copy. Rare/common
  -- distinction can be expressed via the {{card_rarity}} variable if the
  -- admin wants to vary copy by rarity in the template.
  PERFORM public._send_notification(
    p_family_id    => v_session.family_id,
    p_type         => 'hero_card_received',
    p_args         => jsonb_build_object(
      'collection_id', v_collection_id::text,
      'card_rarity',   CASE WHEN v_card.is_rare THEN 'rare' ELSE 'common' END,
      'card_name',     v_card.name
    ),
    p_reference_id => p_child_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
          v_session.venue_id,
          jsonb_build_object('card_id', v_card.id, 'is_rare', v_card.is_rare,
                             'collection_id', v_collection_id));

  RETURN jsonb_build_object(
    'success', true, 'card_id', v_card.id, 'card_name', v_card.name,
    'is_rare', v_card.is_rare, 'collection_id', v_collection_id
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.mark_counter_payment(p_ref_type text, p_ref_id uuid, p_staff_pin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tablet tablet_devices%rowtype;
  v_method text;
  v_paid timestamptz;
begin
  select * into v_tablet from tablet_devices
    where auth_user_id = auth.uid() and is_active = true;
  if not found then raise exception 'tablet_not_authorised'; end if;

  if not exists (
    select 1 from staff where id = p_staff_pin_id
      and venue_id = v_tablet.venue_id and is_active = true
  ) then raise exception 'staff_not_authorised'; end if;

  if p_ref_type = 'session' then
    select payment_method, counter_paid_at into v_method, v_paid
      from sessions where id = p_ref_id and venue_id = v_tablet.venue_id for update;
    if not found then raise exception 'ref_not_found'; end if;
    if v_method <> 'cash' then raise exception 'not_a_counter_payment'; end if;
    if v_paid is not null then raise exception 'already_collected'; end if;
    update sessions set counter_paid_at = now(), counter_paid_by = p_staff_pin_id
      where id = p_ref_id;
  elsif p_ref_type = 'order' then
    select payment_method, counter_paid_at into v_method, v_paid
      from orders where id = p_ref_id and venue_id = v_tablet.venue_id for update;
    if not found then raise exception 'ref_not_found'; end if;
    if v_method <> 'cash' then raise exception 'not_a_counter_payment'; end if;
    if v_paid is not null then raise exception 'already_collected'; end if;
    update orders set counter_paid_at = now(), counter_paid_by = p_staff_pin_id
      where id = p_ref_id;
  else
    raise exception 'invalid_ref_type';
  end if;

  insert into audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  values (p_staff_pin_id, 'staff', 'counter_payment.received', p_ref_type,
          p_ref_id, v_tablet.venue_id);

  return jsonb_build_object('success', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.notifications_purge_old()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM notifications
   WHERE created_at < now() - INTERVAL '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'deleted', v_deleted,
    'cutoff',  (now() - INTERVAL '7 days')
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.qr_scan_validate(p_qr_payload text, p_staff_pin_id uuid DEFAULT NULL::uuid, p_batch_mode boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$                                                                                                                                                                                       
     DECLARE                                                                                                                                                                                             
       v_tablet        tablet_devices%ROWTYPE;                                                                                                                                                           
       v_decoded       JSONB;                                                                                                                                                                            
       v_session_id    UUID;                                                                                                                                                                             
       v_session       sessions%ROWTYPE;                                                                                                                                                                 
       v_config        venue_config%ROWTYPE;                                                                                                                                                             
       v_child_name    TEXT;                                                                                                                                                                             
       v_was_pending   BOOLEAN;                                                                                                                                                                          
       v_family_deleted BOOLEAN;                                                                                                                                                                         
                                                                                                                                                                                                         
       v_batch_session sessions%ROWTYPE;                                                                                                                                                                 
       v_batch_child   TEXT;                                                                                                                                                                             
       v_batch_results jsonb := '[]'::jsonb;                                                                                                                                                             
     BEGIN                                                                                                                                                                                               
       SELECT * INTO v_tablet FROM tablet_devices                                                                                                                                                        
         WHERE auth_user_id = auth.uid() AND is_active = true;                                                                                                                                           
       IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;                                                                                                                                
                                                                                                                                                                                                         
       IF p_staff_pin_id IS NOT NULL THEN                                                                                                                                                                
         IF NOT EXISTS (                                                                                                                                                                                 
           SELECT 1 FROM staff                                                                                                                                                                           
            WHERE id = p_staff_pin_id AND venue_id = v_tablet.venue_id AND is_active = true                                                                                                              
         ) THEN RAISE EXCEPTION 'staff_not_authorised'; END IF;                                                                                                                                          
       END IF;                                                                                                                                                                                           
                                                                                                                                                                                                         
       BEGIN                                                                                                                                                                                             
         v_decoded := convert_from(                                                                                                                                                                      
           decode(                                                                                                                                                                                       
             translate(p_qr_payload, '-_', '+/') ||                                                                                                                                                      
               repeat('=', (4 - length(p_qr_payload) % 4) % 4),                                                                                                                                          
             'base64'                                                                                                                                                                                    
           ), 'UTF8'                                                                                                                                                                                     
         )::JSONB;                                                                                                                                                                                       
       EXCEPTION WHEN others THEN                                                                                                                                                                        
         RAISE EXCEPTION 'qr_payload_invalid';                                                                                                                                                           
       END;                                                                                                                                                                                              
                                                                                                                                                                                                         
       v_session_id := (v_decoded->>'session_id')::UUID;                                                                                                                                                 
       IF v_session_id IS NULL THEN RAISE EXCEPTION 'qr_payload_invalid'; END IF;                                                                                                                        
                                                                                                                                                                                                         
       IF NOT p_batch_mode AND (v_decoded->>'batch_mode')::boolean IS TRUE THEN                                                                                                                          
         p_batch_mode := true;                                                                                                                                                                           
       END IF;                                                                                                                                                                                           
                                                                                                                                                                                                         
       SELECT * INTO v_session FROM sessions WHERE id = v_session_id FOR UPDATE;                                                                                                                         
       IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;                                                                                                                                    
       IF v_session.venue_id != v_tablet.venue_id THEN RAISE EXCEPTION 'session_wrong_venue'; END IF;                                                                                                    
       IF v_session.status NOT IN ('pending','active','grace') THEN                                                                                                                                      
         RAISE EXCEPTION 'session_not_active';                                                                                                                                                           
       END IF;                                                                                                                                                                                           
       IF v_session.staff_scanned_at IS NOT NULL THEN RAISE EXCEPTION 'qr_already_scanned'; END IF;                                                                                                      
                                                                                                                                                                                                         
       SELECT (deleted_at IS NOT NULL) INTO v_family_deleted                                                                                                                                             
         FROM families WHERE id = v_session.family_id;                                                                                                                                                   
       IF v_family_deleted IS TRUE THEN RAISE EXCEPTION 'family_deleted'; END IF;                                                                                                                        
                                                                                                                                                                                                         
       v_was_pending := (v_session.status = 'pending');                                                                                                                                                  
                                                                                                                                                                                                         
       IF v_was_pending THEN                                                                                                                                                                             
         SELECT * INTO v_config FROM venue_config WHERE venue_id = v_tablet.venue_id;                                                                                                                    
         IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;                                                                                                                             
                                                                                                                                                                                                         
         UPDATE sessions SET                                                                                                                                                                             
           status               = 'active',                                                                                                                                                              
           started_at           = now(),                                                                                                                                                                 
           expires_at           = now() + (v_session.duration_minutes || ' minutes')::INTERVAL,                                                                                                          
           grace_force_close_at = now() + ((v_session.duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,                                                                   
           staff_scanned_at     = now(),                                                                                                                                                                 
           staff_pin_id         = p_staff_pin_id                                                                                                                                                         
         WHERE id = v_session.id RETURNING * INTO v_session;                                                                                                                                             
       ELSE                                                                                                                                                                                              
         UPDATE sessions SET                                                                                                                                                                             
           staff_scanned_at = now(),                                                                                                                                                                     
           staff_pin_id     = COALESCE(p_staff_pin_id, staff_pin_id)                                                                                                                                     
         WHERE id = v_session.id RETURNING * INTO v_session;                                                                                                                                             
       END IF;                                                                                                                                                                                           
                                                                                                                                                                                                         
       SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;                                                                                                                        
                                                                                                                                                                                                         
       IF v_was_pending THEN                                                                                                                                                                             
         BEGIN                                                                                                                                                                                           
           PERFORM public._send_notification(                                                                                                                                                            
             p_family_id    => v_session.family_id,                                                                                                                                                      
             p_type         => 'session_started',                                                                                                                                                        
             p_args         => jsonb_build_object(                                                                                                                                                       
               'child_name', COALESCE(v_child_name, 'your kid'),                                                                                                                                         
               'session_id', v_session.id::text                                                                                                                                                          
             ),                                                                                                                                                                                          
             p_reference_id => v_session.id                                                                                                                                                              
           );                                                                                                                                                                                            
         EXCEPTION WHEN OTHERS THEN                                                                                                                                                                      
           INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)                                                                                              
           VALUES (NULL, 'system', 'session.start_push_failed', 'session', v_session.id, v_session.venue_id,                                                                                             
                   jsonb_build_object('error', SQLERRM));                                                                                                                                                
         END;                                                                                                                                                                                            
       END IF;                                                                                                                                                                                           
                                                                                                                                                                                                         
       INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)                                                                                                  
       VALUES (                                                                                                                                                                                          
         p_staff_pin_id, CASE WHEN p_staff_pin_id IS NULL THEN 'tablet' ELSE 'staff' END,                                                                                                                
         CASE WHEN v_was_pending THEN 'session.qr_scan_activate' ELSE 'session.qr_scan_revisit' END,                                                                                                     
         'session', v_session.id, v_tablet.venue_id,                                                                                                                                                     
         jsonb_build_object(                                                                                                                                                                             
           'was_pending', v_was_pending,                                                                                                                                                                 
           'amount_paise', v_session.amount_paise,                                                                                                                                                       
           'tablet_device_id', v_tablet.id,                                                                                                                                                              
           'pin_skipped', (p_staff_pin_id IS NULL),                                                                                                                                                      
           'batch_mode', p_batch_mode                                                                                                                                                                    
         )                                                                                                                                                                                               
       );                                                                                                                                                                                                
                                                                                                                                                                                                         
       v_batch_results := jsonb_build_array(jsonb_build_object(                                                                                                                                          
         'session_id', v_session.id,                                                                                                                                                                     
         'child_id', v_session.child_id,                                                                                                                                                                 
         'child_name', v_child_name,                                                                                                                                                                     
         'status', v_session.status,                                                                                                                                                                     
         'was_pending', v_was_pending                                                                                                                                                                    
       ));                                                                                                                                                                                               
                                                                                                                                                                                                         
       IF p_batch_mode AND v_was_pending THEN                                                                                                                                                            
         FOR v_batch_session IN                                                                                                                                                                          
           SELECT * FROM sessions                                                                                                                                                                        
            WHERE family_id    = v_session.family_id                                                                                                                                                     
              AND venue_id     = v_tablet.venue_id                                                                                                                                                       
              AND status       = 'pending'                                                                                                                                                               
              AND staff_scanned_at IS NULL                                                                                                                                                               
              AND created_at   > now() - interval '5 minutes'                                                                                                                                            
              AND id          != v_session.id                                                                                                                                                            
           FOR UPDATE                                                                                                                                                                                    
         LOOP                                                                                                                                                                                            
           UPDATE sessions SET                                                                                                                                                                           
             status               = 'active',                                                                                                                                                            
             started_at           = now(),                                                                                                                                                               
             expires_at           = now() + (v_batch_session.duration_minutes || ' minutes')::INTERVAL,                                                                                                  
             grace_force_close_at = now() + ((v_batch_session.duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,                                                           
             staff_scanned_at     = now(),                                                                                                                                                               
             staff_pin_id         = p_staff_pin_id                                                                                                                                                       
           WHERE id = v_batch_session.id RETURNING * INTO v_batch_session;                                                                                                                               
                                                                                                                                                                                                         
           SELECT name INTO v_batch_child FROM children WHERE id = v_batch_session.child_id;                                                                                                             
                                                                                                                                                                                                         
           BEGIN                                                                                                                                                                                         
             PERFORM public._send_notification(                                                                                                                                                          
               p_family_id    => v_batch_session.family_id,                                                                                                                                              
               p_type         => 'session_started',                                                                                                                                                      
               p_args         => jsonb_build_object(                                                                                                                                                     
                 'child_name', COALESCE(v_batch_child, 'your kid'),                                                                                                                                      
                 'session_id', v_batch_session.id::text                                                                                                                                                  
               ),                                                                                                                                                                                        
               p_reference_id => v_batch_session.id                                                                                                                                                      
             );                                                                                                                                                                                          
           EXCEPTION WHEN OTHERS THEN                                                                                                                                                                    
             INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)                                                                                            
             VALUES (NULL, 'system', 'session.start_push_failed', 'session', v_batch_session.id, v_batch_session.venue_id,                                                                               
                     jsonb_build_object('error', SQLERRM));                                                                                                                                              
           END;                                                                                                                                                                                          
                                                                                                                                                                                                         
           INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)                                                                                              
           VALUES (                                                                                                                                                                                      
             p_staff_pin_id, CASE WHEN p_staff_pin_id IS NULL THEN 'tablet' ELSE 'staff' END,                                                                                                            
             'session.qr_scan_activate',                                                                                                                                                                 
             'session', v_batch_session.id, v_tablet.venue_id,                                                                                                                                           
             jsonb_build_object(                                                                                                                                                                         
               'was_pending', true,                                                                                                                                                                      
               'amount_paise', v_batch_session.amount_paise,                                                                                                                                             
               'tablet_device_id', v_tablet.id,                                                                                                                                                          
               'pin_skipped', (p_staff_pin_id IS NULL),                                                                                                                                                  
               'batch_mode', true,                                                                                                                                                                       
               'batch_parent_session_id', v_session.id                                                                                                                                                   
             )                                                                                                                                                                                           
           );                                                                                                                                                                                            
                                                                                                                                                                                                         
           v_batch_results := v_batch_results || jsonb_build_array(jsonb_build_object(                                                                                                                   
             'session_id', v_batch_session.id,                                                                                                                                                           
             'child_id', v_batch_session.child_id,                                                                                                                                                       
             'child_name', v_batch_child,                                                                                                                                                                
             'status', v_batch_session.status,                                                                                                                                                           
             'was_pending', true                                                                                                                                                                         
           ));                                                                                                                                                                                           
         END LOOP;                                                                                                                                                                                       
       END IF;                                                                                                                                                                                           
                                                                                                                                                                                                         
       RETURN jsonb_build_object(                                                                                                                                                                        
         'success', true,                                                                                                                                                                                
         'session_id', v_session.id,                                                                                                                                                                     
         'child_id', v_session.child_id,                                                                                                                                                                 
         'child_name', v_child_name,                                                                                                                                                                     
         'status', v_session.status,                                                                                                                                                                     
         'expires_at', v_session.expires_at,                                                                                                                                                             
         'was_pending', v_was_pending,                                                                                                                                                                   
         'batch_mode', p_batch_mode,                                                                                                                                                                     
         'batch_count', jsonb_array_length(v_batch_results),                                                                                                                                             
         'batch_sessions', v_batch_results                                                                                                                                                               
       );                                                                                                                                                                                                
     END $function$
;

CREATE OR REPLACE FUNCTION public.reactivation_redeem(p_family_id uuid, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_contact reactivation_contacts%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_contact FROM reactivation_contacts
    WHERE phone = p_phone AND redeemed_at IS NULL AND NOT is_paused
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', true, 'redeemed', false, 'reason', 'no_match');
  END IF;
  IF now() > v_contact.credit_expires_at THEN
    RETURN jsonb_build_object('success', true, 'redeemed', false, 'reason', 'expired');
  END IF;

  UPDATE wallets SET balance_paise = balance_paise + v_contact.credit_paise, updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type
  ) VALUES (
    p_family_id, 'reactivation_credit', v_contact.credit_paise, v_wallet.balance_paise, 'system',
    v_contact.id, 'reactivation_contact'
  );

  UPDATE reactivation_contacts SET redeemed_at = now(), redeemed_family_id = p_family_id
    WHERE id = v_contact.id;

  PERFORM public._send_notification(
    p_family_id, 'reactivation_welcome',
    jsonb_build_object('credit_amount', (v_contact.credit_paise / 100)::TEXT)
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (p_family_id, 'system', 'reactivation.redeem', 'family', p_family_id,
          jsonb_build_object('credit_paise', v_contact.credit_paise,
                             'reactivation_contact_id', v_contact.id));

  RETURN jsonb_build_object('success', true, 'redeemed', true, 'credit_paise', v_contact.credit_paise);
END $function$
;

CREATE OR REPLACE FUNCTION public.referral_convert(p_referrer_family_id uuid, p_new_family_id uuid, p_triggering_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_config venue_config%ROWTYPE;
  v_venue_id UUID;
  v_month_start DATE;
  v_month_total INTEGER;
  v_is_first BOOLEAN;
  v_referrer_wallet wallets%ROWTYPE;
  v_new_wallet wallets%ROWTYPE;
  v_first_child UUID;
  v_gifter_credit INTEGER;
  v_new_credit INTEGER;
  v_split RECORD;
BEGIN
  IF p_referrer_family_id = p_new_family_id THEN RAISE EXCEPTION 'invalid_referral'; END IF;

  SELECT venue_id INTO v_venue_id FROM sessions WHERE id = p_triggering_session_id;
  IF v_venue_id IS NULL THEN RAISE EXCEPTION 'session_not_found'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_venue_id;
  v_gifter_credit := v_config.referral_gifter_credit_paise;
  v_new_credit    := v_config.referral_new_family_credit_paise;
  v_month_start   := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::DATE;

  SELECT COALESCE(SUM(gifter_wallet_credit_paise), 0) INTO v_month_total
    FROM referral_conversions
    WHERE referrer_family_id = p_referrer_family_id AND conversion_month = v_month_start;
  IF (v_month_total + v_gifter_credit) > v_config.referral_monthly_cap_paise THEN
    RAISE EXCEPTION 'monthly_cap_exceeded';
  END IF;

  SELECT NOT EXISTS(
    SELECT 1 FROM referral_conversions WHERE referrer_family_id = p_referrer_family_id
  ) INTO v_is_first;

  SELECT * INTO v_referrer_wallet FROM wallets WHERE family_id = p_referrer_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_gifter_credit, updated_at = now()
    WHERE family_id = p_referrer_family_id RETURNING * INTO v_referrer_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
  VALUES (p_referrer_family_id, 'bonus', v_gifter_credit, v_referrer_wallet.balance_paise, 'system');

  SELECT * INTO v_new_wallet FROM wallets WHERE family_id = p_new_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_new_credit, updated_at = now()
    WHERE family_id = p_new_family_id RETURNING * INTO v_new_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
  VALUES (p_new_family_id, 'bonus', v_new_credit, v_new_wallet.balance_paise, 'system');

  IF v_is_first AND v_config.xp_referral_bonus_rafi > 0 THEN
    SELECT id INTO v_first_child FROM children
      WHERE family_id = p_referrer_family_id ORDER BY created_at LIMIT 1;
    IF v_first_child IS NOT NULL THEN
      SELECT * INTO v_split FROM _xp_split_for_trait(
        v_config.xp_referral_bonus_rafi, v_config.xp_referral_bonus_trait
      );
      PERFORM xp_credit_with_split(
        v_first_child, p_referrer_family_id, v_venue_id, 'referral_bonus',
        v_split.r_rafi, v_split.r_ellie, v_split.r_gerry, v_split.r_zena,
        NULL,
        jsonb_build_object('reason', 'first_referral_xp_boost', 'trait', v_config.xp_referral_bonus_trait)
      );
      PERFORM public._send_notification(
        p_referrer_family_id, 'first_referral_brave_boost',
        jsonb_build_object('xp_bonus', v_config.xp_referral_bonus_rafi::TEXT,
                           'trait', v_config.xp_referral_bonus_trait)
      );
    END IF;
  ELSIF NOT v_is_first THEN
    PERFORM public._send_notification(
      p_referrer_family_id, 'referral_reward',
      jsonb_build_object('gifter_credit', (v_gifter_credit / 100)::TEXT)
    );
  END IF;

  INSERT INTO referral_conversions(
    referrer_family_id, new_family_id, triggering_session_id, conversion_month,
    gifter_wallet_credit_paise, gifter_xp_bonus_rafi, new_family_wallet_credit_paise,
    is_first_referral
  ) VALUES (
    p_referrer_family_id, p_new_family_id, p_triggering_session_id, v_month_start,
    v_gifter_credit,
    CASE WHEN v_is_first THEN v_config.xp_referral_bonus_rafi ELSE 0 END,
    v_new_credit, v_is_first
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'referral.convert', 'family', p_referrer_family_id, v_venue_id,
          jsonb_build_object('new_family_id', p_new_family_id));

  RETURN jsonb_build_object('success', true);
END $function$
;

CREATE OR REPLACE FUNCTION public.reflection_auto_split()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_recap hero_recaps%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_per INTEGER;
  v_remainder INTEGER;
  v_count INTEGER := 0;
BEGIN
  FOR v_recap IN
    SELECT * FROM hero_recaps
    WHERE reflection_status = 'pending' AND reflection_deadline < now()
    ORDER BY reflection_deadline ASC LIMIT 100
  LOOP
    SELECT * INTO v_session FROM sessions WHERE id = v_recap.session_id;
    v_per := v_recap.total_xp_pool / 4;
    v_remainder := v_recap.total_xp_pool - (v_per * 4);

    PERFORM xp_credit_with_split(
      v_session.child_id, v_session.family_id, v_session.venue_id, 'auto_split',
      v_per, v_per, v_per, v_per + v_remainder, v_recap.session_id, '{}'::JSONB
    );

    UPDATE hero_recaps SET reflection_status = 'auto_split', reflection_at = now()
    WHERE id = v_recap.id;
    UPDATE sessions SET reflection_status = 'auto_split' WHERE id = v_recap.session_id;

    PERFORM public._send_notification(
      v_session.family_id, 'reflection_auto_split',
      '{}'::jsonb, NULL, v_recap.session_id
    );

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'reflection.auto_split', 'session', v_recap.session_id,
            v_session.venue_id,
            jsonb_build_object('total_xp_pool', v_recap.total_xp_pool));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'auto_split_count', v_count);
END $function$
;

CREATE OR REPLACE FUNCTION public.refund_approve(p_refund_id uuid, p_approver_id uuid, p_venue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_refund refunds%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_refund FROM refunds WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_refund.status <> 'pending' THEN RAISE EXCEPTION 'invalid_state'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF v_config.require_two_person_for_debit AND p_approver_id = v_refund.staff_pin_id THEN
    RAISE EXCEPTION 'two_person_required';
  END IF;

  UPDATE refunds SET status = 'approved', approved_by = p_approver_id, approved_at = now()
    WHERE id = p_refund_id;

  IF v_refund.destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + v_refund.amount_paise, updated_at = now()
      WHERE family_id = v_refund.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type
    ) VALUES (
      v_refund.family_id, 'refund', v_refund.amount_paise, v_wallet.balance_paise, 'system',
      v_refund.id, 'refund'
    );

    UPDATE refunds SET status = 'completed' WHERE id = p_refund_id;

    PERFORM public._send_notification(
      v_refund.family_id, 'refund_processed',
      jsonb_build_object('amount_rupees', (v_refund.amount_paise / 100)::TEXT),
      NULL, v_refund.id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_approver_id, 'admin', 'refund.approve', 'refund', p_refund_id, p_venue_id,
          jsonb_build_object('amount_paise', v_refund.amount_paise,
                             'destination', v_refund.destination));

  RETURN jsonb_build_object('success', true, 'refund_id', v_refund.id);
END $function$
;

CREATE OR REPLACE FUNCTION public.refund_issue(p_family_id uuid, p_reference_id uuid, p_reference_type text, p_amount_paise integer, p_destination text, p_reason text, p_staff_pin_id uuid, p_venue_id uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_existing refunds%ROWTYPE;
  v_refund refunds%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_auto_approve BOOLEAN;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_reference_type NOT IN ('session','order','workshop','birthday','manual') THEN
    RAISE EXCEPTION 'invalid_reference_type';
  END IF;
  IF p_destination NOT IN ('wallet','razorpay') THEN RAISE EXCEPTION 'invalid_destination'; END IF;

  IF NOT EXISTS(SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM refunds WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'refund_id', v_existing.id, 'status', v_existing.status
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_auto_approve := (p_amount_paise <= v_config.staff_refund_cap_paise);

  INSERT INTO refunds(
    family_id, reference_id, reference_type, amount_paise, destination,
    initiated_by, staff_pin_id, status, reason, approved_by, approved_at, idempotency_key
  ) VALUES (
    p_family_id, p_reference_id, p_reference_type, p_amount_paise, p_destination,
    'staff', p_staff_pin_id,
    CASE WHEN v_auto_approve THEN 'approved' ELSE 'pending' END,
    p_reason,
    CASE WHEN v_auto_approve THEN p_staff_pin_id ELSE NULL END,
    CASE WHEN v_auto_approve THEN now() ELSE NULL END,
    p_idempotency_key
  ) RETURNING * INTO v_refund;

  IF v_auto_approve AND p_destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + p_amount_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'refund', p_amount_paise, v_wallet.balance_paise, 'system',
      v_refund.id, 'refund', p_idempotency_key
    );

    UPDATE refunds SET status = 'completed' WHERE id = v_refund.id;

    PERFORM public._send_notification(
      p_family_id, 'refund_processed',
      jsonb_build_object('amount_rupees', (p_amount_paise / 100)::TEXT),
      NULL, v_refund.id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'refund.issue', 'refund', v_refund.id, p_venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'destination', p_destination,
                             'auto_approved', v_auto_approve, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'refund_id', v_refund.id,
    'status', CASE WHEN v_auto_approve AND p_destination = 'wallet' THEN 'completed'
                   WHEN v_auto_approve THEN 'approved' ELSE 'pending' END,
    'auto_approved', v_auto_approve
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.register_family_device(p_fcm_token text, p_platform text, p_app_version text DEFAULT NULL::text, p_device_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id   uuid;
  v_family_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  v_family_id := v_user_id;

  if p_fcm_token is null or length(p_fcm_token) < 20 then
    raise exception 'invalid_token';
  end if;
  if p_platform not in ('ios','android','web') then
    raise exception 'invalid_platform';
  end if;

  -- Detach this token from any other family (reused / borrowed phone case).
  update public.family_devices
    set is_active = false
    where fcm_token = p_fcm_token
      and family_id <> v_family_id;

  -- Upsert this device for the current family.
  insert into public.family_devices (family_id, fcm_token, platform, app_version, device_label, last_seen_at)
  values (v_family_id, p_fcm_token, p_platform, p_app_version, p_device_label, now())
  on conflict (fcm_token) do update
    set family_id    = excluded.family_id,
        platform     = excluded.platform,
        app_version  = coalesce(excluded.app_version, family_devices.app_version),
        device_label = coalesce(excluded.device_label, family_devices.device_label),
        last_seen_at = now(),
        is_active    = true;

  -- Keep families.fcm_token loosely in sync so legacy code & admin panels
  -- still see "the most recently seen device" without breaking. Not used
  -- by send-push anymore.
  update public.families
    set fcm_token      = p_fcm_token,
        fcm_platform   = p_platform,
        app_version    = coalesce(p_app_version, app_version),
        last_active_at = now()
  where id = v_family_id;

  return jsonb_build_object('success', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.session_extend(p_session_id uuid, p_duration_minutes integer, p_payment_method text, p_initiated_by text DEFAULT 'parent'::text, p_staff_pin_id uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session   sessions%ROWTYPE;
  v_wallet    wallets%ROWTYPE;
  v_config    venue_config%ROWTYPE;
  v_amount    INTEGER;
  v_new_exp   TIMESTAMPTZ;
  v_existing  session_extensions%ROWTYPE;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_initiated_by NOT IN ('parent','staff_on_behalf') THEN RAISE EXCEPTION 'invalid_initiator'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM session_extensions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_expires_at', v_existing.new_expires_at,
        'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  SELECT (value->>'price_paise')::INTEGER INTO v_amount
    FROM jsonb_array_elements(v_config.session_extension_options)
   WHERE (value->>'minutes')::INTEGER = p_duration_minutes
   LIMIT 1;
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'invalid_duration'; END IF;

  -- Compute new expiry from the ORIGINAL expires_at (not now()) so grace
  -- minutes are deducted from the extension rather than handed out free.
  v_new_exp := v_session.expires_at + (p_duration_minutes || ' minutes')::INTERVAL;

  -- Guard: customer has been in grace longer than the extension covers.
  -- Reject so the UI can suggest a longer extension instead of charging
  -- them for a session that's already in the past.
  IF v_new_exp <= now() THEN
    RAISE EXCEPTION 'extension_too_short'
      USING DETAIL = format(
        'session already %s min past expiry; %s-min extension does not move expiry forward',
        EXTRACT(EPOCH FROM (now() - v_session.expires_at))::INTEGER / 60,
        p_duration_minutes
      );
  END IF;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = v_session.family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_amount THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

    UPDATE wallets SET balance_paise = balance_paise - v_amount, updated_at = now()
      WHERE family_id = v_session.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_id, reference_type, idempotency_key
    ) VALUES (
      v_session.family_id, 'extension_debit', -v_amount, v_wallet.balance_paise,
      'wallet', p_session_id, 'session_extension', p_idempotency_key
    );
  END IF;

  UPDATE sessions SET
    expires_at = v_new_exp,
    grace_force_close_at = v_new_exp + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL,
    status = 'active',
    grace_started_at = NULL
  WHERE id = p_session_id;

  INSERT INTO session_extensions(
    session_id, duration_minutes, amount_paise, payment_method, new_expires_at,
    staff_pin_id, initiated_by, idempotency_key
  ) VALUES (
    p_session_id, p_duration_minutes, v_amount, p_payment_method, v_new_exp,
    p_staff_pin_id, p_initiated_by, p_idempotency_key
  );

  IF p_initiated_by = 'staff_on_behalf' THEN
    PERFORM public._send_notification(
      p_family_id    => v_session.family_id,
      p_type         => 'extend_nudge',
      p_args         => jsonb_build_object('duration_minutes', p_duration_minutes::text),
      p_reference_id => p_session_id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.extend', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('duration_minutes', p_duration_minutes, 'amount_paise', v_amount,
                       'initiated_by', p_initiated_by, 'new_expires_at', v_new_exp)
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_expires_at', v_new_exp,
    'amount_paise', v_amount
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.staff_customer_summary(p_family_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet         tablet_devices%ROWTYPE;
  v_family         families%ROWTYPE;
  v_child_names    text[];
  v_visit_count    int;
  v_last_visit_at  timestamptz;
  v_avg_minutes    int;
  v_session_spend  bigint;
  v_food_spend     bigint;
  v_workshop_spend bigint;
  v_birthday_spend bigint;
  v_top_items      jsonb;
  v_wallet         wallets%ROWTYPE;
  v_total_xp       int;
  v_member_tier    text;
BEGIN
  -- Auth: caller must be a registered tablet device
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  -- Family must exist and not be deleted/anonymised. Staff should not
  -- see a customer summary for a family that's been closed for privacy.
  SELECT * INTO v_family FROM families WHERE id = p_family_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'family_not_found'; END IF;
  IF v_family.deleted_at IS NOT NULL OR v_family.is_anonymised IS TRUE THEN
    RAISE EXCEPTION 'family_deleted';
  END IF;

  -- Child names (non-deleted), oldest first so the header reads naturally
  SELECT COALESCE(array_agg(name ORDER BY date_of_birth NULLS LAST), ARRAY[]::text[])
    INTO v_child_names
    FROM children
    WHERE family_id = p_family_id AND deleted_at IS NULL;

  -- Visit metrics. Visit count = distinct days with a session at this
  -- venue, so a same-day extension doesn't double-count. Excludes
  -- cancelled_pre_scan (kid never actually started a session).
  SELECT
    COUNT(DISTINCT DATE(started_at)),
    MAX(started_at),
    COALESCE(AVG(duration_minutes)::int, 0)
  INTO v_visit_count, v_last_visit_at, v_avg_minutes
  FROM sessions
  WHERE family_id = p_family_id
    AND venue_id = v_tablet.venue_id
    AND status NOT IN ('cancelled_pre_scan')
    AND started_at IS NOT NULL;

  -- Lifetime spend components ---------------------------------------

  -- Sessions paid directly (NOT via an order bundle). Skipping
  -- paid_via_order_id rows avoids double-counting combos that bundle
  -- a session — the order's session_value_paise already captures it.
  SELECT COALESCE(SUM(amount_paise), 0) INTO v_session_spend
  FROM sessions
  WHERE family_id = p_family_id
    AND venue_id = v_tablet.venue_id
    AND status NOT IN ('cancelled_pre_scan')
    AND paid_via_order_id IS NULL;

  -- Food spend = order total minus any bundled session portion, so the
  -- "food" number is honest even for Play + meal combos.
  SELECT COALESCE(SUM(total_paise - COALESCE(session_value_paise, 0)), 0)
  INTO v_food_spend
  FROM orders
  WHERE family_id = p_family_id
    AND venue_id = v_tablet.venue_id
    AND status IN ('pending','preparing','ready','served');

  -- Workshop spend (cancelled rows excluded by NULL filter)
  SELECT COALESCE(SUM(wr.amount_paise), 0) INTO v_workshop_spend
  FROM workshop_registrations wr
  JOIN workshops w ON w.id = wr.workshop_id
  WHERE wr.family_id = p_family_id
    AND w.venue_id = v_tablet.venue_id
    AND wr.cancelled_at IS NULL;

  -- Birthday spend (only confirmed/completed reservations count)
  SELECT COALESCE(SUM(total_paid_paise), 0) INTO v_birthday_spend
  FROM birthday_reservations
  WHERE family_id = p_family_id
    AND venue_id = v_tablet.venue_id
    AND status IN ('confirmed','completed');

  -- Top 3 food items by total quantity ordered. Uses name_snapshot so
  -- renamed/deleted menu items still display their original name.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'count', cnt)
                            ORDER BY cnt DESC), '[]'::jsonb)
  INTO v_top_items
  FROM (
    SELECT
      COALESCE(NULLIF(oi.name_snapshot, ''), mi.name, '(unknown)') AS name,
      SUM(oi.quantity)::int AS cnt
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    LEFT JOIN menu_items mi ON mi.id = oi.menu_item_id
    WHERE o.family_id = p_family_id
      AND o.venue_id = v_tablet.venue_id
      AND o.status IN ('pending','preparing','ready','served')
      AND oi.line_type IN ('menu_item','fit_meal','combo')
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 3
  ) t;

  -- Wallet (one row per family; left-join effectively via maybe-null)
  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id;

  -- Total XP across all non-deleted children + highest overall stage
  -- among them (so a 1-kid family shows that kid's tier; a 2-kid family
  -- shows the more-advanced kid's tier).
  SELECT COALESCE(SUM(total_xp), 0)::int INTO v_total_xp
    FROM children
    WHERE family_id = p_family_id AND deleted_at IS NULL;

  SELECT current_overall_stage INTO v_member_tier
  FROM (
    SELECT
      current_overall_stage,
      ARRAY_POSITION(
        ARRAY['seedling','explorer','adventurer','champion','legend'],
        current_overall_stage
      ) AS rank
    FROM children
    WHERE family_id = p_family_id
      AND deleted_at IS NULL
      AND current_overall_stage IS NOT NULL
  ) ranked
  ORDER BY rank DESC NULLS LAST
  LIMIT 1;

  RETURN jsonb_build_object(
    'family_id',                  v_family.id,
    'guardian_name',              v_family.name,
    'guardian_phone',             v_family.phone,
    'is_walk_in',                 v_family.is_walk_in,
    'child_names',                v_child_names,
    'visit_count',                COALESCE(v_visit_count, 0),
    'last_visit_at',              v_last_visit_at,
    'avg_session_length_minutes', v_avg_minutes,
    'lifetime_spend_paise',
      v_session_spend + v_food_spend + v_workshop_spend + v_birthday_spend,
    'session_spend_paise',        v_session_spend,
    'food_spend_paise',           v_food_spend,
    'workshop_spend_paise',       v_workshop_spend,
    'birthday_spend_paise',       v_birthday_spend,
    'top_food_items',             v_top_items,
    'wallet_balance_paise',       COALESCE(v_wallet.balance_paise, 0),
    'wallet_held_paise',          COALESCE(v_wallet.held_paise, 0),
    'coins_balance',              COALESCE(v_wallet.coins_balance, 0),
    'total_xp',                   v_total_xp,
    'member_tier',                v_member_tier
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.staff_roster()
 RETURNS TABLE(staff_id uuid, staff_name text, role text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tablet tablet_devices%rowtype;
begin
  select * into v_tablet from tablet_devices
    where auth_user_id = auth.uid() and is_active = true;
  if not found then raise exception 'tablet_not_authorised'; end if;

  return query
    select s.id, s.name, s.role
    from staff s
    where s.venue_id = v_tablet.venue_id and s.is_active = true
    order by s.name;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_workshop_list_registrations(p_workshop_id uuid)
 RETURNS TABLE(id uuid, child_id uuid, child_name text, child_dob date, family_id uuid, family_phone text, attended boolean, cancelled_at timestamp with time zone, payment_method text, amount_paise integer, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_venue UUID;
BEGIN
  SELECT w.venue_id INTO v_venue
    FROM workshops w
   WHERE w.id = p_workshop_id;
  IF v_venue IS NULL THEN RAISE EXCEPTION 'workshop_not_found'; END IF;
  IF NOT _is_active_tablet_for_venue(v_venue) THEN
    RAISE EXCEPTION 'not_authorised_for_venue';
  END IF;

  RETURN QUERY
    SELECT
      r.id, r.child_id,
      c.name AS child_name,
      c.date_of_birth AS child_dob,
      r.family_id,
      f.phone AS family_phone,
      r.attended,
      r.cancelled_at,
      r.payment_method,
      r.amount_paise,
      r.created_at
    FROM workshop_registrations r
    JOIN children c ON c.id = r.child_id
    JOIN families f ON f.id = r.family_id
    WHERE r.workshop_id = p_workshop_id
    ORDER BY r.created_at ASC;
END $function$
;

CREATE OR REPLACE FUNCTION public.stage_perk_redeem(p_code text, p_staff_pin_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_grant stage_perk_grants%ROWTYPE;
  v_perk  stage_perks%ROWTYPE;
  v_child children%ROWTYPE;
  v_normalized TEXT := upper(trim(p_code));
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  SELECT * INTO v_grant FROM stage_perk_grants
    WHERE upper(code) = v_normalized FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'perk_code_not_found'; END IF;

  IF v_grant.redeemed_at IS NOT NULL THEN
    RAISE EXCEPTION 'perk_already_redeemed';
  END IF;

  IF v_grant.expires_at < now() THEN
    RAISE EXCEPTION 'perk_expired';
  END IF;

  SELECT * INTO v_perk  FROM stage_perks WHERE id = v_grant.perk_id;
  SELECT * INTO v_child FROM children    WHERE id = v_grant.child_id;

  UPDATE stage_perk_grants SET
    redeemed_at = now(),
    redeemed_by_pin = p_staff_pin_id,
    redeem_note = p_note
  WHERE id = v_grant.id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'stage_perk.redeem', 'stage_perk_grant', v_grant.id,
    jsonb_build_object(
      'code', v_grant.code,
      'child_id', v_grant.child_id,
      'family_id', v_grant.family_id,
      'stage', v_grant.stage,
      'trait', v_grant.trait,
      'perk_label', v_perk.perk_label,
      'note', p_note
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'grant_id', v_grant.id,
    'family_id', v_grant.family_id,
    'child_name', v_child.name,
    'stage', v_grant.stage,
    'trait', v_grant.trait,
    'perk_label', v_perk.perk_label,
    'perk_description', v_perk.perk_description
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.streak_update(p_child_id uuid, p_venue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec streak_records%ROWTYPE;
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_today DATE;
  v_this_monday DATE;
  v_milestone_hit INTEGER := 0;
  v_bonus_xp INTEGER := 0;
  v_split RECORD;
BEGIN
  v_today := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_this_monday := v_today - ((EXTRACT(ISODOW FROM v_today)::INTEGER - 1));

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  INSERT INTO streak_records (child_id) VALUES (p_child_id) ON CONFLICT (child_id) DO NOTHING;
  SELECT * INTO v_rec FROM streak_records WHERE child_id = p_child_id FOR UPDATE;

  IF v_rec.last_streak_week_ist = v_this_monday THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true,
                              'current_streak_weeks', v_rec.current_streak_weeks);
  END IF;

  IF v_rec.last_streak_week_ist = v_this_monday - INTERVAL '7 days' THEN
    UPDATE streak_records SET
      current_streak_weeks = current_streak_weeks + 1,
      longest_streak_weeks = GREATEST(longest_streak_weeks, current_streak_weeks + 1),
      total_visit_stars = total_visit_stars + 1,
      last_visit_date_ist = v_today, last_streak_week_ist = v_this_monday
    WHERE child_id = p_child_id RETURNING * INTO v_rec;
  ELSE
    UPDATE streak_records SET
      current_streak_weeks = 1,
      longest_streak_weeks = GREATEST(longest_streak_weeks, 1),
      total_visit_stars = total_visit_stars + 1,
      last_visit_date_ist = v_today, last_streak_week_ist = v_this_monday
    WHERE child_id = p_child_id RETURNING * INTO v_rec;
  END IF;

  IF v_rec.current_streak_weeks >= 3 AND NOT v_rec.milestone_3_achieved THEN
    UPDATE streak_records SET milestone_3_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 3;
  ELSIF v_rec.current_streak_weeks >= 5 AND NOT v_rec.milestone_5_achieved THEN
    UPDATE streak_records SET milestone_5_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 5;
  ELSIF v_rec.current_streak_weeks >= 10 AND NOT v_rec.milestone_10_achieved THEN
    UPDATE streak_records SET milestone_10_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 10;
  END IF;

  IF v_milestone_hit > 0 THEN
    v_bonus_xp := v_config.xp_streak_bonus * v_milestone_hit;
    SELECT * INTO v_split FROM _xp_split_for_trait(v_bonus_xp, v_config.xp_streak_bonus_trait);
    PERFORM xp_credit_with_split(
      p_child_id, v_child.family_id, p_venue_id, 'streak_bonus',
      v_split.r_rafi, v_split.r_ellie, v_split.r_gerry, v_split.r_zena,
      NULL,
      jsonb_build_object('milestone_weeks', v_milestone_hit, 'trait', v_config.xp_streak_bonus_trait)
    );

    PERFORM public._send_notification(
      v_child.family_id, 'streak_milestone',
      jsonb_build_object(
        'child_name', v_child.name,
        'milestone_weeks', v_milestone_hit::TEXT,
        'bonus_xp', v_bonus_xp::TEXT
      ),
      NULL, p_child_id
    );
  END IF;

  RETURN jsonb_build_object('success', true,
    'current_streak_weeks', v_rec.current_streak_weeks,
    'milestone_hit', v_milestone_hit, 'bonus_xp', v_bonus_xp);
END $function$
;
