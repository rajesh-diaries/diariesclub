-- 0224_healthy_bite_eligibility_fix.sql
--
-- BUG: real (app) families never earned a Healthy Bite.
--
-- `_healthy_bite_eligibility_sweep()` runs every 5 min (pg_cron job
-- "healthy-bite-eligibility", jobid 8) and is meant to flip
-- sessions.healthy_bite_earned = true in the last 10 minutes of an active
-- session. That earned flag is what (a) surfaces the snack on the staff
-- Healthy Bites screen (its query is earned OR distributed OR declined, and
-- is_guest = false) and (b) triggers the "{{child}} deserves a Healthy Bite"
-- push to the parent.
--
-- The WHERE clause required `family_id IS NULL`. But real app sessions ALWAYS
-- have a family_id — only walk-in guests are null, and guests have no child
-- profile, no hero card, and no app to receive the push (the staff screen
-- also filters is_guest = false, so guest rows never show there anyway).
-- Net effect: the sweep matched ~nothing, so NO real family ever earned a
-- healthy bite via the cron. The staff screen stayed empty and the push never
-- fired. Flip the condition to `family_id IS NOT NULL`.
--
-- Also fixes a latent column/value mismatch in the error-path audit_log INSERT
-- (6 columns, 7 values — the venue_id column was missing from the list), which
-- would itself raise inside the EXCEPTION handler.
--
-- Idempotent CREATE OR REPLACE. No schema change, no data migration.

CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
  v_session_ids UUID[];
BEGIN
  FOR r IN
    UPDATE sessions SET healthy_bite_earned = true
    WHERE status='active' AND child_id IS NOT NULL AND family_id IS NOT NULL
      AND healthy_bite_earned = false
      AND expires_at > now() AND expires_at <= now() + interval '10 minutes'
    RETURNING id, family_id, child_id, venue_id
  LOOP
    v_count := v_count + 1;
    v_session_ids := v_session_ids || r.id;
  END LOOP;
  FOR r IN
    SELECT s.family_id, array_agg(DISTINCT COALESCE(c.name,'your kid')) AS names
    FROM sessions s
    JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
    LEFT JOIN children c ON c.id = s.child_id
    GROUP BY s.family_id
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id => r.family_id,
        p_type => 'healthy_bite_earned',
        p_args => jsonb_build_object('child_name', _format_name_list(r.names)),
        p_reference_id => gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
      VALUES (NULL, 'system', 'healthy_bite.notify_failed', 'session', NULL, NULL,
              jsonb_build_object('error', SQLERRM, 'family_id', r.family_id));
    END;
  END LOOP;
  RETURN v_count;
END $function$
;
