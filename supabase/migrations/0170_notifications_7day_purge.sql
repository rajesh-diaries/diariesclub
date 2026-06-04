-- ===========================================================================
-- Migration 0170 — 7-day auto-purge for notifications
-- ===========================================================================
-- Privacy Policy §2.3 and §6 commit to "Push notification dispatch records
-- auto-purged after 7 days". Until this migration that was only true at
-- the FCM/APNs push-delivery layer (carriers drop undelivered pushes after
-- the per-message ttl_seconds window — see migration 0165). The
-- notifications table itself accumulated forever.
--
-- This migration:
--   * adds purge_old_notifications() — deletes rows where created_at is
--     older than 7 days
--   * schedules pg_cron to run it nightly at 02:30 UTC (08:00 IST)
--
-- The cleanup window is keyed off `created_at`, not `delivered_at`, to
-- guarantee the policy promise — every record disappears 7 days after we
-- created it, whether or not it was successfully pushed to the device.
--
-- Idempotent: unschedule + reschedule on every apply.
-- ===========================================================================

CREATE OR REPLACE FUNCTION purge_old_notifications()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM notifications
  WHERE created_at < now() - INTERVAL '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END $$;

COMMENT ON FUNCTION purge_old_notifications() IS
  'Deletes notifications older than 7 days. Scheduled nightly via pg_cron. Honours Privacy Policy §2.3 retention promise.';

-- Unschedule any prior version, then reschedule. Safe to re-apply.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-old-notifications') THEN
    PERFORM cron.unschedule('purge-old-notifications');
  END IF;
END $$;

SELECT cron.schedule(
  'purge-old-notifications',
  '30 2 * * *',                              -- 02:30 UTC = 08:00 IST daily
  $$SELECT purge_old_notifications();$$
);
