-- ===========================================================================
--  Migration 0018 — Session 13 Edge Function support
--
--  This migration:
--    1. Adds venue_config.birthday_interest_ttl_hours (default 72) so the
--       birthday-72h-autocancel cron reads the threshold from config.
--    2. ENABLES the notify_push_dispatch trigger that was deliberately
--       commented out in 0017 — Session 13 deploys send-push, so we can
--       safely flip it on now.
--    3. Creates pg_cron jobs for the five cron Edge Functions:
--         force-close-grace-sessions     — every minute
--         razorpay-reconcile             — every 15 min
--         reflection-auto-split-cron     — hourly
--         birthday-72h-autocancel        — hourly (offset 5 min)
--         birthday-journey-cron          — daily at 03:30 UTC (09:00 IST)
--    5. Each pg_cron job calls the function URL via pg_net.http_post with
--       the service-role bearer.
--
--  IMPORTANT — this migration assumes:
--    * The send-push Edge Function is deployed (see Session 13 deploy step).
--      If you run this migration BEFORE deploying send-push, the trigger
--      will fire but pg_net will get 404s on every notification insert.
--      Each 404 is logged but doesn't break the insert — defensive but
--      noisy. Defer this migration until send-push deploys cleanly.
--    * The service-role key is stored in Supabase Vault as `service_role_key`
--      BEFORE crons / trigger fire. Originally we tried `ALTER DATABASE
--      postgres SET app.service_role_key`, but Supabase managed projects
--      deny the role needed for ALTER DATABASE. Vault is the supported
--      pattern. Set via Studio → Database → Vault → New secret.
--      Without it, every cron + trigger tick logs a NOTICE and no-ops.
--
--  All cron jobs use the same auth pattern: pg_net.http_post with
--  Bearer ${SUPABASE_SERVICE_ROLE_KEY} pulled from Vault. Edge Functions
--  check this in their requireServiceRole() helper.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  1. venue_config.birthday_interest_ttl_hours
-- ---------------------------------------------------------------------------
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS birthday_interest_ttl_hours INTEGER NOT NULL DEFAULT 72;

COMMENT ON COLUMN venue_config.birthday_interest_ttl_hours IS
  'Hours after a birthday reservation request is submitted (status=interested) '
  'before the birthday-72h-autocancel cron flips status to cancelled. '
  'Default 72.';

-- ---------------------------------------------------------------------------
--  2. notifications.push_failure_reason (for send-push to record FCM error)
-- ---------------------------------------------------------------------------
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS push_failure_reason TEXT;

COMMENT ON COLUMN notifications.push_failure_reason IS
  'Last FCM error code when push_status=failed (e.g. UNREGISTERED, INVALID_ARGUMENT). '
  'Cleared on next dispatched.';

-- ---------------------------------------------------------------------------
--  3. Enable the notify_push_dispatch trigger
--
--  Created (but not attached) in migration 0017. Now that send-push
--  exists, attach the AFTER INSERT trigger.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS notify_push_after_insert ON notifications;
CREATE TRIGGER notify_push_after_insert
  AFTER INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION notify_push_dispatch();

-- ---------------------------------------------------------------------------
--  5. pg_cron jobs
--
--  pg_cron must be enabled. Already enabled by Supabase by default on
--  Pro plan; if not, the CREATE EXTENSION below is idempotent.
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Helper function so each cron job is one line. Service-role key comes
-- from Supabase Vault (`service_role_key`). Without it, the function
-- logs a NOTICE and returns NULL — cron tick is a no-op rather than an
-- error, so we don't fill cron.job_run_details with failures while
-- bootstrap is incomplete.
CREATE OR REPLACE FUNCTION cron_invoke_function(p_slug TEXT) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  v_base CONSTANT TEXT := 'https://stpxtenyatjwcazuxhtu.supabase.co/functions/v1/';
  v_key  TEXT;
  v_request_id BIGINT;
BEGIN
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
   WHERE name = 'service_role_key'
   LIMIT 1;

  IF v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE 'cron_invoke_function: vault.service_role_key missing; skipping % invocation', p_slug;
    RETURN NULL;
  END IF;

  SELECT INTO v_request_id net.http_post(
    url := v_base || p_slug,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type',  'application/json'
    )
  );
  RETURN v_request_id;
END $$;

REVOKE EXECUTE ON FUNCTION cron_invoke_function(TEXT) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION cron_invoke_function(TEXT) TO service_role;

-- Drop existing schedules so this migration is idempotent on re-run.
DO $$
DECLARE
  v_jobs TEXT[] := ARRAY[
    'force-close-grace-sessions',
    'razorpay-reconcile',
    'reflection-auto-split-cron',
    'birthday-72h-autocancel',
    'birthday-journey-cron'
  ];
  v_job TEXT;
BEGIN
  FOREACH v_job IN ARRAY v_jobs LOOP
    PERFORM cron.unschedule(v_job) WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = v_job
    );
  END LOOP;
END $$;

-- Schedule the five jobs.
SELECT cron.schedule(
  'force-close-grace-sessions',
  '* * * * *',           -- every minute
  $$SELECT cron_invoke_function('force-close-grace-sessions');$$
);

SELECT cron.schedule(
  'razorpay-reconcile',
  '*/15 * * * *',        -- every 15 minutes
  $$SELECT cron_invoke_function('razorpay-reconcile');$$
);

SELECT cron.schedule(
  'reflection-auto-split-cron',
  '0 * * * *',           -- top of every hour
  $$SELECT cron_invoke_function('reflection-auto-split-cron');$$
);

SELECT cron.schedule(
  'birthday-72h-autocancel',
  '5 * * * *',           -- 5 min past every hour (offset from reflection)
  $$SELECT cron_invoke_function('birthday-72h-autocancel');$$
);

SELECT cron.schedule(
  'birthday-journey-cron',
  '30 3 * * *',          -- 03:30 UTC = 09:00 IST daily
  $$SELECT cron_invoke_function('birthday-journey-cron');$$
);

-- ---------------------------------------------------------------------------
--  6. Bootstrap reminder — Supabase Vault
--
--  Before this migration's effects matter, store the service-role key
--  in Supabase Vault. ALTER DATABASE GUCs were the original plan but
--  Supabase managed projects deny that. Vault is the supported pattern.
--
--    1. Studio → Database → Vault → New secret
--    2. Name:  service_role_key
--    3. Value: paste from Project Settings → API → service_role key
--
--  Verify:
--    SELECT name FROM vault.decrypted_secrets WHERE name = 'service_role_key';
--
--  Without this entry, every cron tick + every notifications.INSERT
--  trigger logs NOTICE and short-circuits.
-- ---------------------------------------------------------------------------
