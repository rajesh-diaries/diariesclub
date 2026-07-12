-- 0232 — Staff floor ops: physical-exit tracking + shift money summary
--
-- Requested by the founder for the live staff app (2026-07-04):
--   1. Track WHO is physically still inside vs who left — a session can be
--      billing-closed (customer wraps up) while the kid is still in the play
--      area. Add sessions.left_at as a staff-set "physically exited" marker,
--      SEPARATE from status/completed_at, plus staff_confirm_exit() to set it.
--   2. Wallet-vs-cash money summary for end-of-shift reconciliation (the old
--      staff app deliberately showed no money; the founder now wants the
--      cash-drawer + wallet totals). staff_shift_summary() aggregates orders +
--      sessions + extends by payment method, tablet-authorised, money via a
--      SECURITY DEFINER RPC (no broad money RLS for staff).
--
-- All staff RPCs mirror session_force_close: tablet_devices auth + staff PIN.

ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;
COMMENT ON COLUMN public.sessions.left_at IS
  'Staff-confirmed physical exit from the play area. Independent of status/'
  'completed_at (a session can be billing-closed while the kid is still inside).';

-- Staff confirms a family/kid has physically left. Works on any status so a
-- kid who wrapped up in the app (session already completed) can still be
-- cleared off the "still inside" floor list.
CREATE OR REPLACE FUNCTION public.staff_confirm_exit(
  p_session_id uuid, p_staff_pin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet  tablet_devices%ROWTYPE;
  v_session sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff WHERE id = p_staff_pin_id
      AND venue_id = v_tablet.venue_id AND is_active = true
  ) THEN RAISE EXCEPTION 'staff_not_authorised'; END IF;

  SELECT * INTO v_session FROM sessions
    WHERE id = p_session_id AND venue_id = v_tablet.venue_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.left_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_left', true,
                              'session_id', p_session_id, 'left_at', v_session.left_at);
  END IF;

  UPDATE sessions SET left_at = now() WHERE id = p_session_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'session.confirm_exit', 'session',
          p_session_id, v_tablet.venue_id, jsonb_build_object('left_at', now()));

  RETURN jsonb_build_object('success', true, 'session_id', p_session_id, 'left_at', now());
END $function$;

-- End-of-shift / today money + headcount summary. Defaults to the current IST
-- calendar day; pass p_since to scope to a shift start.
CREATE OR REPLACE FUNCTION public.staff_shift_summary(p_since timestamptz DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_since  timestamptz;
  v_oc int; v_ow int;               -- orders cash / wallet
  v_sc int; v_sw int; v_sp int;     -- sessions cash / wallet / play_pass count
  v_ec int; v_ew int;               -- extends cash / wallet
  v_sessions int; v_kids int; v_inside int; v_left int;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  -- Default window = start of today in IST.
  v_since := COALESCE(
    p_since,
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata'
  );

  SELECT COALESCE(SUM(total_paise) FILTER (WHERE payment_method = 'cash'), 0),
         COALESCE(SUM(total_paise) FILTER (WHERE payment_method = 'wallet'), 0)
    INTO v_oc, v_ow
    FROM orders
   WHERE venue_id = v_tablet.venue_id AND created_at >= v_since;

  SELECT COALESCE(SUM(amount_paise) FILTER (WHERE payment_method = 'cash'), 0),
         COALESCE(SUM(amount_paise) FILTER (WHERE payment_method = 'wallet'), 0),
         COUNT(*) FILTER (WHERE payment_method = 'play_pass')
    INTO v_sc, v_sw, v_sp
    FROM sessions
   WHERE venue_id = v_tablet.venue_id AND created_at >= v_since
     AND status IN ('active', 'grace', 'completed', 'auto_closed');

  SELECT COALESCE(SUM(e.amount_paise) FILTER (WHERE e.payment_method = 'cash'), 0),
         COALESCE(SUM(e.amount_paise) FILTER (WHERE e.payment_method = 'wallet'), 0)
    INTO v_ec, v_ew
    FROM session_extensions e
    JOIN sessions s ON s.id = e.session_id
   WHERE s.venue_id = v_tablet.venue_id AND e.created_at >= v_since;

  SELECT COUNT(*),
         COUNT(DISTINCT child_id) FILTER (WHERE child_id IS NOT NULL),
         COUNT(*) FILTER (WHERE left_at IS NULL),
         COUNT(*) FILTER (WHERE left_at IS NOT NULL)
    INTO v_sessions, v_kids, v_inside, v_left
    FROM sessions
   WHERE venue_id = v_tablet.venue_id AND created_at >= v_since
     AND status IN ('active', 'grace', 'completed', 'auto_closed');

  RETURN jsonb_build_object(
    'since', v_since,
    'cash_paise',   v_oc + v_sc + v_ec,
    'wallet_paise', v_ow + v_sw + v_ew,
    'orders',   jsonb_build_object('cash_paise', v_oc, 'wallet_paise', v_ow),
    'sessions', jsonb_build_object('cash_paise', v_sc, 'wallet_paise', v_sw, 'play_pass_count', v_sp),
    'extends',  jsonb_build_object('cash_paise', v_ec, 'wallet_paise', v_ew),
    'sessions_today', v_sessions,
    'kids_today',     v_kids,
    'inside_count',   v_inside,
    'left_count',     v_left
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.staff_confirm_exit(uuid, uuid)  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.staff_shift_summary(timestamptz) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.staff_confirm_exit(uuid, uuid)  TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.staff_shift_summary(timestamptz) TO authenticated, service_role;
