-- 0152 — Session expiry warning push
--
-- Customer feedback (2026-05-17): "I didn't realise my session had ended;
-- it just auto-closed". The `grace_started` notification template was
-- defined in 0026/0051 but never wired to fire — sessions today go
-- straight from active → auto_closed without any heads-up.
--
-- This migration:
--   1. Sharpens the grace_started template copy to be actionable
--      ("tap to Wrap up or Extend") so parents act, not just acknowledge.
--   2. Adds send_session_expiry_warnings() RPC that finds sessions
--      whose expiry time has passed but force-close hasn't yet, fires
--      the push, and dedupes via the notifications table (so the cron
--      can run every minute without spamming).
--
-- The cron Edge Function force-close-grace-sessions is updated separately
-- to call this RPC alongside the existing force_close_grace_sessions().

UPDATE notification_templates
   SET title              = 'Session ending soon',
       body               = 'Time''s up for {{child_name}} — tap to Wrap up or Extend.',
       deep_link_template = '/home'
 WHERE type = 'grace_started';

CREATE OR REPLACE FUNCTION public.send_session_expiry_warnings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count      INTEGER := 0;
  v_session    sessions%ROWTYPE;
  v_child_name TEXT;
BEGIN
  FOR v_session IN
    SELECT s.* FROM sessions s
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
    LIMIT 200
  LOOP
    SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => v_session.family_id,
        p_type         => 'grace_started',
        p_args         => jsonb_build_object(
          'child_name', COALESCE(v_child_name, 'your kid'),
          'session_id', v_session.id::text
        ),
        p_reference_id => v_session.id
      );
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
      VALUES (NULL, 'system', 'session.expiry_warning.notify_failed', 'session', v_session.id, v_session.venue_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'warned_count', v_count);
END $function$;
