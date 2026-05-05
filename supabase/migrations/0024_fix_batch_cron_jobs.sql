-- ===========================================================================
--  Migration 0024 — pg_cron schedules for fix-batch new Edge Functions
--
--  Apply this AFTER the Edge Functions exist:
--    * child-birthday-wishes-cron      (FEATURE-001, daily 00:30 UTC)
--    * session-autocancel-pending-cron (BUG-004, every 1 minute)
--
--  Re-uses the cron_invoke_function() helper installed in
--  0018_session_13_setup.sql (reads the service-role key from
--  vault.decrypted_secrets at fire-time, never crashes if vault is
--  empty — just logs a NOTICE and skips).
--
--  Reversibility:
--    SELECT cron.unschedule('child-birthday-wishes');
--    SELECT cron.unschedule('session-autocancel-pending');
-- ===========================================================================

BEGIN;

-- 1. Daily birthday wish at 00:30 UTC = 06:00 IST. The Edge Function does
--    its own per-venue time check so admins can override the venue
--    config field child_birthday_wish_time without us re-scheduling cron.
DO $$
BEGIN
  -- Defensive: drop existing schedule with this name before re-adding,
  -- so re-running this migration is idempotent.
  PERFORM cron.unschedule('child-birthday-wishes')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'child-birthday-wishes');
EXCEPTION WHEN undefined_function OR undefined_table THEN
  NULL; -- pg_cron not installed in this env; skip.
END $$;

SELECT cron.schedule(
  'child-birthday-wishes',
  '30 0 * * *',
  $$ SELECT cron_invoke_function('child-birthday-wishes-cron') $$
);

-- 2. Auto-cancel pending sessions every minute. Sweep window is short so
--    the customer experience matches the countdown UI closely.
DO $$
BEGIN
  PERFORM cron.unschedule('session-autocancel-pending')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'session-autocancel-pending');
EXCEPTION WHEN undefined_function OR undefined_table THEN
  NULL;
END $$;

SELECT cron.schedule(
  'session-autocancel-pending',
  '* * * * *',
  $$ SELECT cron_invoke_function('session-autocancel-pending-cron') $$
);

COMMIT;
