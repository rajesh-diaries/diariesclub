-- session_complete referenced dead columns on referral_conversions
-- (converted_at / converted_session_id), so completing the FIRST session of a
-- referred family raised "column converted_at does not exist" and broke wrap-up
-- (session_complete_batch -> session_complete). It also meant referral rewards
-- were never actually applied. Replace the stale inline insert with a call to
-- referral_convert (the correct, complete conversion: credits both wallets + XP
-- + notifications + correct schema), wrapped best-effort so a referral failure
-- (e.g. referral_monthly_cap_paise reached -> monthly_cap_exceeded) can never
-- block session completion.
CREATE OR REPLACE FUNCTION public.session_complete(p_session_id uuid, p_staff_pin_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session sessions%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_pool INTEGER;
  v_deadline TIMESTAMPTZ;
  v_old_status TEXT;
  v_recap_id UUID;
  v_family families%ROWTYPE;
  v_is_first_session_for_family BOOLEAN;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.status IN ('completed','auto_closed','void') THEN
    RETURN jsonb_build_object('success', true, 'already_complete', true);
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

  -- Per-session close notification. Suppressed when session_complete_batch
  -- is running so we can send one combined push at the end.
  IF current_setting('app.suppress_session_notifications', true) IS DISTINCT FROM 'true' THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'session_closed',
      'Session ended — recap on the way',
      'Tap to reflect on the moments and earn XP.',
      '/reflection/' || p_session_id, p_session_id
    );
  END IF;

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

  SELECT * INTO v_family FROM families WHERE id = v_session.family_id;
  IF v_family.referrer_family_id IS NOT NULL THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM sessions
       WHERE family_id = v_session.family_id
         AND status = 'completed'
         AND id <> p_session_id
    ) INTO v_is_first_session_for_family;

    IF v_is_first_session_for_family AND NOT EXISTS (
      SELECT 1 FROM referral_conversions WHERE new_family_id = v_session.family_id
    ) THEN
      -- Best-effort: referral_convert credits both wallets + XP and writes the
      -- conversion row. It must NEVER block session completion (it raises
      -- monthly_cap_exceeded when the referrer has hit the monthly cap, etc.).
      BEGIN
        PERFORM referral_convert(
          v_family.referrer_family_id, v_session.family_id, p_session_id
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'referral_convert failed for new_family % (session %): %',
          v_session.family_id, p_session_id, SQLERRM;
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'status', 'completed',
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $function$;
