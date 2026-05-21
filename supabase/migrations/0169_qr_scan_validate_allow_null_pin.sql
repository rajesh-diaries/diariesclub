-- Allow qr_scan_validate to be called WITHOUT a staff PIN id. The
-- staff-app UI shortcuts the PIN gate for QR scans (floor flow needs
-- to be fast — scanning doesn't move money, only validates that the
-- session is real and marks it as scanned). The tablet_device row
-- still authenticates the call; we just no longer require which
-- specific staff member tapped scan.
--
-- Backwards compatible: if p_staff_pin_id IS NOT NULL it's still
-- validated against the staff table. The session's staff_pin_id and
-- audit_log's actor_id become NULL for PIN-less scans; the audit log
-- still records the venue + tablet device implicitly.

CREATE OR REPLACE FUNCTION public.qr_scan_validate(p_qr_payload text, p_staff_pin_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet     tablet_devices%ROWTYPE;
  v_decoded    JSONB;
  v_session_id UUID;
  v_session    sessions%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_child_name TEXT;
  v_was_pending BOOLEAN;
  v_family_deleted BOOLEAN;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  -- Only validate the staff PIN id when one was actually passed. The
  -- floor-flow Scan QR shortcut sends NULL.
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
      'pin_skipped', (p_staff_pin_id IS NULL)
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'session_id', v_session.id,
    'child_id', v_session.child_id, 'child_name', v_child_name,
    'status', v_session.status, 'expires_at', v_session.expires_at,
    'was_pending', v_was_pending
  );
END $function$;
