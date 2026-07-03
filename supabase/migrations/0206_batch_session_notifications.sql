-- Batch session-end notifications per family so parents get one push when
-- multiple sessions end together, instead of a separate push per child.

-- ===========================================================================
-- 1. session_complete — skip its per-session notification when called inside
--    a batch (session_complete_batch).
-- ===========================================================================
CREATE OR REPLACE FUNCTION session_complete(
  p_session_id UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
      INSERT INTO referral_conversions(new_family_id, referrer_family_id, converted_at, converted_session_id)
      VALUES (v_session.family_id, v_family.referrer_family_id, now(), p_session_id);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'status', 'completed',
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $$;

-- ===========================================================================
-- 2. session_complete_batch — complete multiple sessions in one go and emit
--    exactly one combined notification per family.
-- ===========================================================================
CREATE OR REPLACE FUNCTION session_complete_batch(
  p_session_ids UUID[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_family_id UUID;
  v_session_id UUID;
  v_names TEXT[];
  v_count INTEGER := 0;
BEGIN
  IF p_session_ids IS NULL OR array_length(p_session_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('success', true, 'completed_count', 0);
  END IF;

  -- Determine the family from the first session and verify authority.
  SELECT DISTINCT family_id INTO v_family_id
    FROM sessions WHERE id = ANY(p_session_ids);

  IF v_family_id IS NULL THEN RAISE EXCEPTION 'sessions_not_found'; END IF;
  IF auth.uid() IS NULL OR auth.uid() <> v_family_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  -- Guard against cross-family batches.
  IF EXISTS (
    SELECT 1 FROM sessions
     WHERE id = ANY(p_session_ids)
       AND family_id <> v_family_id
  ) THEN
    RAISE EXCEPTION 'mixed_families_in_batch';
  END IF;

  PERFORM set_config('app.suppress_session_notifications', 'true', true);

  FOREACH v_session_id IN ARRAY p_session_ids LOOP
    PERFORM session_complete(v_session_id);
    v_count := v_count + 1;
  END LOOP;

  PERFORM set_config('app.suppress_session_notifications', 'false', true);

  -- One combined close/reflection notification for the whole family.
  SELECT array_agg(DISTINCT c.name ORDER BY c.name) INTO v_names
    FROM sessions s
    JOIN children c ON c.id = s.child_id
   WHERE s.id = ANY(p_session_ids);

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_family_id,
    'session_closed',
    'That''s a wrap 🎬',
    'Tap to reflect on the moments and earn XP for ' || _format_name_list(v_names) || '.',
    '/home',
    gen_random_uuid()
  );

  RETURN jsonb_build_object(
    'success', true,
    'completed_count', v_count,
    'child_names', to_jsonb(v_names)
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.session_complete_batch(UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_complete_batch(UUID[]) TO authenticated, service_role;

-- ===========================================================================
-- 3. send_session_expiry_warnings — group expiring sessions by family and send
--    one "Session ending soon" notification per family.
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.send_session_expiry_warnings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT s.family_id,
           array_agg(DISTINCT COALESCE(c.name, 'your kid') ORDER BY COALESCE(c.name, 'your kid')) AS names,
           count(*) AS session_count
      FROM sessions s
      LEFT JOIN children c ON c.id = s.child_id
     WHERE s.status = 'active'
       AND s.expires_at IS NOT NULL
       AND now() >= s.expires_at
       AND s.grace_force_close_at IS NOT NULL
       AND now() < s.grace_force_close_at
       AND NOT EXISTS (
         SELECT 1 FROM notifications n
          WHERE n.reference_id = s.id
            AND n.type = 'grace_started'
       )
     GROUP BY s.family_id
     LIMIT 200
  LOOP
    BEGIN
      INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
      VALUES (
        v_row.family_id,
        'grace_started',
        'Session ending soon',
        CASE
          WHEN v_row.session_count = 1 THEN
            'Time''s up for ' || _format_name_list(v_row.names) || ' — tap to Wrap up or Extend.'
          ELSE
            'Time''s up for ' || _format_name_list(v_row.names) || ' — tap to Wrap up or Extend all sessions.'
        END,
        '/home',
        gen_random_uuid()
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'session.expiry_warning.notify_failed', 'session', NULL,
              jsonb_build_object('error', SQLERRM, 'family_id', v_row.family_id));
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'warned_count', v_count);
END $function$;
