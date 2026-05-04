-- ===========================================================================
--  Migration 0017 — notifications → push trigger (Session 12)
--
--  Status: trigger function defined here, attached to the notifications
--  table in migration 0018 (which also schedules the cron jobs).
--
--  Originally this migration set ALTER DATABASE GUCs to hand the bearer
--  token + function URL to the trigger — but Supabase managed projects
--  deny the role needed to ALTER DATABASE. Switched to:
--    * URL hardcoded as a CONSTANT in the function body (project ref
--      doesn't change without a much bigger migration anyway).
--    * service-role key read from Supabase Vault at runtime via
--      vault.decrypted_secrets.
--
--  Enable steps:
--    1. Deploy supabase/functions/send-push/index.ts (Session 13).
--    2. Add `service_role_key` to Supabase Vault:
--       Studio → Database → Vault → New secret
--       Name: service_role_key
--       Value: paste the service-role key from Settings → API
--    3. Apply migration 0018 (attaches the trigger + schedules crons).
--    4. Insert a test notifications row and confirm:
--         (a) push arrives on the test device, and
--         (b) the row has push_status='queued' immediately, then
--             'sent' or 'failed' after the function callback updates it.
--
--  Why a Postgres trigger and not the Flutter app inserting + then
--  invoking the function? Two reasons:
--    1. Some notifications come from server-side flows (cron, Edge
--       Functions calling other Edge Functions) where there is no app
--       to invoke. The trigger handles those uniformly.
--    2. Atomicity. If the app inserts the row successfully but crashes
--       before invoking, the user gets the in-app inbox entry but no
--       push. With the trigger, every persisted row attempts a push.
-- ===========================================================================

-- 1. Extension. pg_net is the Supabase-recommended way to make outbound
--    HTTP calls from inside a transaction. Already used by other parts
--    of Supabase infra; adding it here is idempotent.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 2. Function. Defined now so Session 13 only has to flip the trigger on.
--    Send-push Edge Function URL is hardcoded — it never changes for a
--    given Supabase project (changing the project ref means a much
--    bigger migration anyway). The service-role bearer comes from
--    Supabase Vault: paste the key into Studio → Database → Vault →
--    New secret with name 'service_role_key'. ALTER DATABASE GUCs were
--    the original plan but Supabase managed projects deny the role
--    needed to set them.
CREATE OR REPLACE FUNCTION notify_push_dispatch() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_url CONSTANT TEXT := 'https://stpxtenyatjwcazuxhtu.supabase.co/functions/v1/send-push';
  v_key TEXT;
BEGIN
  -- Pull service-role key from Supabase Vault. If absent (vault entry not
  -- yet created), log + skip — never crash the notifications.INSERT.
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets
   WHERE name = 'service_role_key'
   LIMIT 1;

  IF v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE 'notify_push_dispatch: vault.service_role_key missing; skipping push for notification %', NEW.id;
    RETURN NEW;
  END IF;

  -- Async fire-and-forget. pg_net.http_post returns the request id; we
  -- ignore it. The Edge Function callbacks UPDATE notifications.push_status
  -- once it knows the FCM result.
  PERFORM net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'notification_id', NEW.id,
      'family_id',       NEW.family_id,
      'type',            NEW.type,
      'title',           NEW.title,
      'body',            NEW.body,
      'deep_link',       NEW.deep_link,
      'reference_id',    NEW.reference_id,
      'metadata',        NEW.metadata
    ),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type',  'application/json'
    )
  );

  -- Mark optimistically so the admin audit page shows progress before
  -- the callback lands.
  UPDATE notifications
     SET push_status  = 'queued',
         push_sent_at = now()
   WHERE id = NEW.id;

  RETURN NEW;
END $$;

REVOKE EXECUTE ON FUNCTION notify_push_dispatch() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION notify_push_dispatch() TO service_role;

-- 3. Trigger (DISABLED).
--    Uncomment in Session 13 after the send-push Edge Function is
--    deployed and the GUC config is in place. Until then, notifications
--    insert without firing pg_net.
--
-- CREATE TRIGGER notify_push_after_insert
--   AFTER INSERT ON notifications
--   FOR EACH ROW EXECUTE FUNCTION notify_push_dispatch();
--
-- DROP TRIGGER IF EXISTS notify_push_after_insert ON notifications;
