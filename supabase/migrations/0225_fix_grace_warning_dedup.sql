-- 0225 — Fix "Session ending soon" push spam (one per minute)
--
-- Bug: send_session_expiry_warnings() (last rewritten in 0206 for per-family
-- batching) dedupes with
--     NOT EXISTS (SELECT 1 FROM notifications n
--                  WHERE n.reference_id = s.id AND n.type = 'grace_started')
-- but the INSERT writes  reference_id = gen_random_uuid()  — a value that can
-- never equal a session id. So no session is ever recorded as "warned", every
-- expiring session re-qualifies on every run, and the force-close-grace-sessions
-- cron (schedule '* * * * *') fires a fresh "Session ending soon" push EVERY
-- MINUTE for the entire grace window (5–170 min in prod → dozens of dupes).
-- Confirmed in prod: one family received 5 identical pushes across 5 minutes.
--
-- Fix: stop keying dedup off the notification's own reference_id. Mark the
-- session instead, exactly like the working _hydration_reminder_sweep() does
-- with hydration_reminded_at. We reuse the existing sessions.grace_started_at
-- column: it is currently populated on 0 rows (declared in 0001, only ever
-- reset to NULL by session_extend), its name already means "grace warning
-- fired", and the extend-resets-to-NULL behaviour is exactly what we want —
-- an extended session that expires again correctly re-arms for one more warning.

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
           array_agg(s.id) AS session_ids,
           count(*) AS session_count
      FROM sessions s
      LEFT JOIN children c ON c.id = s.child_id
     WHERE s.status = 'active'
       AND s.expires_at IS NOT NULL
       AND now() >= s.expires_at
       AND s.grace_force_close_at IS NOT NULL
       AND now() < s.grace_force_close_at
       AND s.grace_started_at IS NULL          -- dedup: only sessions not yet warned
     GROUP BY s.family_id
     LIMIT 200
  LOOP
    BEGIN
      -- Mark the sessions as warned in the SAME sub-block as the INSERT. If the
      -- INSERT raises, the exception handler rolls back this mark too (implicit
      -- savepoint), so the family re-qualifies next run instead of being lost.
      UPDATE sessions
         SET grace_started_at = now()
       WHERE id = ANY(v_row.session_ids);

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
