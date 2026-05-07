-- ===========================================================================
--  Migration 0047 — session_complete guard against pending-status leak
--
--  Why
--  ---
--  Forensic audit on family 37ab8070 (test customer) showed wallet
--  held_paise had accumulated to ₹5,100 while no active wallet sessions
--  existed. Tracing the audit_log:
--    * 7 wallet sessions created with used_hold=true (each adds to held)
--    * 0 session.qr_scan events (no qr_scan_validate ever ran)
--    * 1 session.cancel_pending event (only one hold released)
--    * 8 session.complete events with old_status='active'
--
--  Sessions reached 'active' bypassing qr_scan_validate (the only RPC
--  that releases the hold + debits the wallet). Likely dev-test artifact
--  — direct UPDATEs during testing, no real staff scan. session_complete
--  then blindly transitioned them to 'completed' without touching
--  held_paise, leaking the hold permanently.
--
--  Production risk
--  ---------------
--  In real operations qr_scan_validate is the only legitimate path from
--  pending → active. But session_complete previously accepted ANY status
--  transition. If anything (admin tool, future RPC, rogue migration, or
--  a bug) ever moves a session out of pending without releasing the
--  hold, session_complete silently buries the bug. This guard makes that
--  inconsistency loud.
--
--  Behaviour change
--  ----------------
--  session_complete now raises 'session_must_be_active_or_grace' if
--  called on a session with status NOT IN
--  ('active','grace','completed','auto_closed','void').
--  Idempotent return for already-terminal statuses unchanged.
--
--  Reversibility: re-deploy the prior body from 0010_reflection.sql.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.session_complete(
  p_session_id uuid,
  p_staff_pin_id uuid DEFAULT NULL::uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_config  venue_config%ROWTYPE;
  v_pool    INTEGER;
  v_recap_id UUID;
  v_deadline TIMESTAMPTZ;
  v_old_status TEXT;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF auth.role() <> 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);
  END IF;

  -- Idempotent for already-terminal sessions.
  IF v_session.status IN ('completed','auto_closed','void') THEN
    SELECT id INTO v_recap_id FROM hero_recaps WHERE session_id = p_session_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', p_session_id,
      'recap_id', v_recap_id,
      'status', v_session.status
    );
  END IF;

  -- Guard (BUG-047): a pending session has an unconverted wallet hold
  -- (or unpaid cash) and must NOT be completed directly. The legitimate
  -- paths are:
  --   * qr_scan_validate  → pending to active + releases hold + debits
  --   * session_cancel_pending → pending to cancelled_pre_scan + releases hold
  -- Any code that tries to short-cut to completed is buggy and would
  -- leak the hold. Raise loudly so the bug is caught instead of buried.
  IF v_session.status = 'pending' THEN
    RAISE EXCEPTION 'session_must_be_active_or_grace'
      USING DETAIL = 'session is still pending; route through '
                  || 'qr_scan_validate or session_cancel_pending';
  END IF;

  IF v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_must_be_active_or_grace'
      USING DETAIL = format('unexpected status: %s', v_session.status);
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  v_pool := v_session.duration_minutes * v_config.xp_per_session_minute;
  v_deadline := now() + (v_config.reflection_window_hours || ' hours')::INTERVAL;
  v_old_status := v_session.status;

  UPDATE sessions SET
    status = 'completed',
    completed_at = now(),
    reflection_deadline = v_deadline,
    total_xp_earned = v_pool
  WHERE id = p_session_id;

  INSERT INTO hero_recaps(
    session_id, child_id, total_xp_pool,
    reflection_status, reflection_deadline
  ) VALUES (
    p_session_id, v_session.child_id, v_pool,
    'pending', v_deadline
  )
  ON CONFLICT (session_id) DO NOTHING
  RETURNING id INTO v_recap_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'session_closed',
    'Session ended — recap on the way',
    'Tap to reflect on the moments and earn XP.',
    '/reflection/' || p_session_id, p_session_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN auth.role() = 'service_role' THEN 'system'
         WHEN p_staff_pin_id IS NOT NULL    THEN 'staff'
         ELSE 'customer' END,
    'session.complete', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', 'completed', 'total_xp_pool', v_pool,
                       'reflection_deadline', v_deadline)
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'recap_id', v_recap_id,
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $$;
