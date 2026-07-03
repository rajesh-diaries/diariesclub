-- Pay the referral reward when a referred family's first session is closed by
-- the auto-close cron too (previously only the manual wrap-up path paid it, so
-- a referred family that let its first session time out never triggered the
-- ₹100/₹100). Idempotent across both paths via the NOT EXISTS referral_conversions
-- guard; wrapped in a subtransaction so a referral failure can't abort the batch.
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
  v_family     families%ROWTYPE;
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

    -- Referral reward on the family's first played session (matches
    -- session_complete). The NOT EXISTS guard makes this idempotent across the
    -- manual and auto-close paths; best-effort so it never aborts the loop.
    SELECT * INTO v_family FROM families WHERE id = v_session.family_id;
    IF v_family.referrer_family_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM referral_conversions WHERE new_family_id = v_session.family_id)
    THEN
      BEGIN
        PERFORM referral_convert(
          v_family.referrer_family_id, v_session.family_id, v_session.id
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'referral_convert failed on auto-close for new_family % (session %): %',
          v_session.family_id, v_session.id, SQLERRM;
      END;
    END IF;

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
END $function$;
