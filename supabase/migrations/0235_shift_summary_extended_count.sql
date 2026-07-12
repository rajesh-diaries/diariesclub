-- 0235 — staff_shift_summary: add today's extended-session count
--
-- Home tiles were driven by a separate rolling-24h query (showed yesterday's
-- sessions). Point them at this IST-calendar-day summary instead, and add
-- extended_today (distinct sessions that got an extension today) so the second
-- tile can show "Extended" instead of "Kids today".

CREATE OR REPLACE FUNCTION public.staff_shift_summary(p_since timestamptz DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_since  timestamptz;
  v_oc int; v_ow int;
  v_sc int; v_sw int; v_sp int;
  v_ec int; v_ew int;
  v_sessions int; v_kids int; v_inside int; v_left int; v_extended int;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

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
         COALESCE(SUM(e.amount_paise) FILTER (WHERE e.payment_method = 'wallet'), 0),
         COUNT(DISTINCT e.session_id)
    INTO v_ec, v_ew, v_extended
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
    'extended_today', v_extended,
    'inside_count',   v_inside,
    'left_count',     v_left
  );
END $function$;
