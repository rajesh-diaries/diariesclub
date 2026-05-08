-- 0057_hydration_reminder.sql
--
-- Hydration nudge during active play. At the 20-minute mark of any
-- active session, fire one push notification + flag the session so the
-- in-app banner shows. One reminder per session, idempotent.
--
-- Notification type 'hydration_nudge' already exists in the existing
-- notifications.type CHECK constraint — no constraint rewrite needed.
--
-- Threshold (20 min) is hard-coded for now. Move to venue_config later
-- if the founder wants to tune.

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS hydration_reminded_at TIMESTAMPTZ;

COMMENT ON COLUMN sessions.hydration_reminded_at IS
  'Set when the 20-minute hydration nudge fires. NULL = not yet sent. Idempotency guard for the sweep cron.';

-- ===========================================================================
-- _hydration_reminder_sweep()
--   For each active session whose started_at is older than 20 minutes
--   and hasn't been reminded yet, insert one notification row (which
--   triggers FCM via notify_push_after_insert) and set
--   hydration_reminded_at. SECURITY DEFINER so cron (service_role)
--   can call it without RLS issues.
-- ===========================================================================
CREATE OR REPLACE FUNCTION _hydration_reminder_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER := 0;
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT id, family_id, child_id
      FROM sessions
     WHERE status = 'active'
       AND started_at <= v_now - INTERVAL '20 minutes'
       AND hydration_reminded_at IS NULL
  LOOP
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_row.family_id,
      'hydration_nudge',
      'Hydration check 💧',
      'Time for a sip of water — keeps the play going strong.',
      '/home',
      v_row.id
    );

    UPDATE sessions
       SET hydration_reminded_at = v_now
     WHERE id = v_row.id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END $$;

REVOKE EXECUTE ON FUNCTION _hydration_reminder_sweep() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _hydration_reminder_sweep() TO service_role;

-- ===========================================================================
-- pg_cron schedule — every minute. Cheap (one indexed scan), and the
-- sweep is idempotent thanks to the hydration_reminded_at IS NULL guard.
-- ===========================================================================
DO $$
BEGIN
  PERFORM cron.unschedule('hydration-reminder-sweep')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'hydration-reminder-sweep');
EXCEPTION WHEN undefined_function OR undefined_table THEN
  NULL;
END $$;

SELECT cron.schedule(
  'hydration-reminder-sweep',
  '* * * * *',
  $$ SELECT public._hydration_reminder_sweep() $$
);

CREATE INDEX IF NOT EXISTS idx_sessions_active_hydration
  ON sessions(started_at)
  WHERE status = 'active' AND hydration_reminded_at IS NULL;
