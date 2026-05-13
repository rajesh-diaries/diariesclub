-- 0139 — retire Welcome cards.
--
-- Founder's call: drop the Welcome card concept entirely. Reverts the
-- first-session welcome-grant block we added in 0134 (back to the
-- original session_complete shape) AND deactivates existing Welcome
-- hero_card_definitions so they stop appearing in the customer
-- collection (sealed-but-coming-soon would still take a tile).
--
-- Already-granted hero_card_collection rows are LEFT IN PLACE — kids
-- who happened to receive a Welcome card during testing keep it. No
-- surprise loss of a "won" card.

CREATE OR REPLACE FUNCTION public.session_complete(
  p_session_id   UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_config  venue_config%ROWTYPE;
  v_pool    INTEGER;
  v_recap_id UUID;
  v_deadline TIMESTAMPTZ;
  v_old_status TEXT;
  v_family families%ROWTYPE;
  v_is_first_session_for_family BOOLEAN;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF auth.role() <> 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);
  END IF;

  IF v_session.status IN ('completed','auto_closed','void') THEN
    SELECT id INTO v_recap_id FROM hero_recaps WHERE session_id = p_session_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', p_session_id,
      'recap_id', v_recap_id,
      'status', v_session.status
    );
  END IF;

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
      BEGIN
        PERFORM referral_convert(
          v_family.referrer_family_id,
          v_session.family_id,
          p_session_id
        );
      EXCEPTION WHEN OTHERS THEN
        INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
        VALUES (
          NULL, 'system', 'referral.convert_failed', 'family',
          v_session.family_id, v_session.venue_id,
          jsonb_build_object('error', SQLERRM, 'session_id', p_session_id)
        );
      END;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'recap_id', v_recap_id,
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $$;

UPDATE hero_card_definitions
SET is_active = false
WHERE unlock_method = 'stage' AND unlock_stage = 'welcome';
