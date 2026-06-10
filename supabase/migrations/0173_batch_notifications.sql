-- Batch notifications for multi-kid sessions.
-- When 3 kids are checked in together, the parent gets 1 combined
-- "session started" push instead of 3 individual ones. Same for
-- hydration nudge and healthy bite — one per family per event.

-- ===========================================================================
-- 1. qr_scan_validate — single combined session_started push for batch.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.qr_scan_validate(
  p_qr_payload    text,
  p_staff_pin_id  uuid    DEFAULT NULL,
  p_batch_mode    boolean DEFAULT false
)
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
  v_batch_names   TEXT[] := ARRAY[]::TEXT[];
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
  v_batch_names := ARRAY[COALESCE(v_child_name, 'your kid')];

  -- BATCH MODE: also activate sibling sessions created in the same batch.
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
      v_batch_names := v_batch_names || COALESCE(v_batch_child, 'your kid');
    END LOOP;
  END IF;

  -- Send ONE combined notification for the whole batch.
  IF v_was_pending THEN
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => v_session.family_id,
        p_type         => 'session_started',
        p_args         => jsonb_build_object(
          'child_name', _format_name_list(v_batch_names),
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
END $function$;

-- ===========================================================================
-- 2. _hydration_reminder_sweep — one nudge per family, listing all kids.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public._hydration_reminder_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER := 0;
  v_family_id UUID;
  v_names TEXT[];
  v_session_ids UUID[];
  v_row RECORD;
BEGIN
  -- Build a family → names map for all sessions that need a nudge.
  FOR v_row IN
    SELECT id, family_id, child_id
      FROM sessions
     WHERE status = 'active'
       AND started_at <= v_now - INTERVAL '20 minutes'
       AND hydration_reminded_at IS NULL
     ORDER BY family_id
  LOOP
    UPDATE sessions
       SET hydration_reminded_at = v_now
     WHERE id = v_row.id;

    v_session_ids := v_session_ids || v_row.id;
    v_count := v_count + 1;
  END LOOP;

  -- Group by family and send ONE notification per family.
  FOR v_row IN
    SELECT family_id,
           array_agg(DISTINCT COALESCE(c.name, 'your kid')) AS names
      FROM sessions s
      JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
      LEFT JOIN children c ON c.id = s.child_id
     GROUP BY family_id
  LOOP
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_row.family_id,
      'hydration_nudge',
      'Hydration check 💧',
      CASE WHEN array_length(v_row.names, 1) > 1
           THEN 'Time for a sip of water — ' || _format_name_list(v_row.names) || ' need to stay hydrated!'
           ELSE 'Time for a sip of water — keeps the play going strong.'
      END,
      '/home',
      gen_random_uuid()
    );
  END LOOP;

  RETURN v_count;
END $$;

-- ===========================================================================
-- 3. _healthy_bite_eligibility_sweep — one bite per family.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
  v_family_id UUID;
  v_names TEXT[];
  v_session_ids UUID[];
BEGIN
  -- Flip eligible sessions and collect IDs.
  FOR r IN
    UPDATE sessions
       SET healthy_bite_earned = true
     WHERE status = 'active'
       AND child_id IS NOT NULL
       AND family_id IS NOT NULL
       AND healthy_bite_earned = false
       AND expires_at > now()
       AND expires_at <= now() + interval '10 minutes'
    RETURNING id, family_id, child_id, venue_id
  LOOP
    v_count := v_count + 1;
    v_session_ids := v_session_ids || r.id;
  END LOOP;

  -- Group by family and send ONE notification per family.
  FOR r IN
    SELECT s.family_id,
           array_agg(DISTINCT COALESCE(c.name, 'your kid')) AS names
      FROM sessions s
      JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
      LEFT JOIN children c ON c.id = s.child_id
     GROUP BY s.family_id
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => r.family_id,
        p_type         => 'healthy_bite_earned',
        p_args         => jsonb_build_object(
          'child_name', _format_name_list(r.names)
        ),
        p_reference_id => gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'healthy_bite.notify_failed', 'session', NULL, NULL,
              jsonb_build_object('error', SQLERRM, 'family_id', r.family_id));
    END;
  END LOOP;

  RETURN v_count;
END $function$;

-- ===========================================================================
-- 4. Helper: format an array of names as "Alice, Bob & Charlie".
-- ===========================================================================
CREATE OR REPLACE FUNCTION public._format_name_list(p_names TEXT[])
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN array_length(p_names, 1) IS NULL THEN 'your kid'
    WHEN array_length(p_names, 1) = 1 THEN p_names[1]
    WHEN array_length(p_names, 1) = 2 THEN p_names[1] || ' & ' || p_names[2]
    ELSE array_to_string(p_names[1:array_length(p_names,1)-1], ', ') || ' & ' || p_names[array_length(p_names,1)]
  END;
$$;
