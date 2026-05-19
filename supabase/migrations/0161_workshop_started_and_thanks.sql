-- 0161 — Workshop "starts now" + "thanks for joining" pushes.
--
-- New pushes wired into the existing workshop-lifecycle-cron tick:
--
--   workshop_started   fires when scheduled_at <= now() — to every
--                      non-cancelled registration. Replaces the implicit
--                      "show up because the reminder said so" with an
--                      explicit "we're starting now". Dedup column:
--                      workshop_registrations.started_notified_at.
--
--   workshop_thanks    fires 20 min after scheduled_at + duration_minutes
--                      — to every ATTENDED registration (so families
--                      who registered but no-showed don't get a misleading
--                      thank-you). Dedup column:
--                      workshop_registrations.thanks_notified_at.

-- ── Schema additions ────────────────────────────────────────────────────
ALTER TABLE workshop_registrations
  ADD COLUMN IF NOT EXISTS started_notified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS thanks_notified_at  TIMESTAMPTZ;

-- ── Expand notifications.type CHECK ─────────────────────────────────────
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'session_started','hydration_nudge','healthy_bite_earned',
    'grace_started','extend_nudge','session_closed','recap_ready',
    'reflection_prompt','reflection_auto_split',
    'order_confirmed','order_ready',
    'hero_card_received','stage_transition_imminent',
    'stage_transition_revealed','level_up',
    'birthday_d_minus_90','birthday_d_minus_60','birthday_d_minus_30',
    'birthday_d_minus_14','birthday_d_minus_7','birthday_d_minus_3',
    'birthday_d_minus_1','birthday_d_zero','birthday_d_plus_1',
    'birthday_album_ready','birthday_hero_progression_trigger',
    'birthday_wish','referral_reward','first_referral_brave_boost',
    'wallet_topup','wallet_low_balance','visit_milestone',
    'streak_milestone','refund_processed','reactivation_welcome',
    'workshop_reminder','workshop_cancelled',
    'workshop_registered','workshop_starting_soon','workshop_attended',
    'workshop_started','workshop_thanks',
    'pre_booking_reminder','pre_booking_expired','while_you_wait_food',
    'announcement_published','hero_within_unlocked'
  ])
);

-- ── Templates ───────────────────────────────────────────────────────────
INSERT INTO notification_templates(
  type, category, enabled, title, body, deep_link_template,
  variables, preference_key
) VALUES (
  'workshop_started',
  'workshop',
  true,
  'Starts now! 🎬',
  '{{title}} is starting. Have a great time, {{child_name}}!',
  '/club/workshops',
  '["title","child_name","workshop_id"]'::jsonb,
  'workshop_reminders'
)
ON CONFLICT (type) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  title   = EXCLUDED.title,
  body    = EXCLUDED.body,
  deep_link_template = EXCLUDED.deep_link_template,
  preference_key = EXCLUDED.preference_key,
  variables = EXCLUDED.variables;

INSERT INTO notification_templates(
  type, category, enabled, title, body, deep_link_template,
  variables, preference_key
) VALUES (
  'workshop_thanks',
  'workshop',
  true,
  'Thanks for joining! 💖',
  'Hope {{child_name}} had a great time at {{title}}. See you next time!',
  '/club/workshops',
  '["title","child_name","workshop_id"]'::jsonb,
  'workshop_reminders'
)
ON CONFLICT (type) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  title   = EXCLUDED.title,
  body    = EXCLUDED.body,
  deep_link_template = EXCLUDED.deep_link_template,
  preference_key = EXCLUDED.preference_key,
  variables = EXCLUDED.variables;

-- ── workshop_send_started_nudges ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.workshop_send_started_nudges()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
BEGIN
  -- A registration is "due for the started nudge" when the workshop's
  -- scheduled_at has just passed (or equals now) and we haven't sent
  -- the nudge yet. Cap the window at 10 min so we don't backfill a
  -- nudge for a workshop that's been running for 45 min already (the
  -- thanks push handles late discovery).
  FOR r IN
    SELECT wr.id AS registration_id,
           wr.family_id, wr.child_id,
           w.id AS wid, w.title,
           c.name AS child_name
      FROM workshop_registrations wr
      JOIN workshops w ON w.id = wr.workshop_id
      LEFT JOIN children c ON c.id = wr.child_id
     WHERE w.status = 'upcoming'
       AND w.scheduled_at <= now()
       AND w.scheduled_at > now() - INTERVAL '10 minutes'
       AND wr.cancelled_at IS NULL
       AND wr.started_notified_at IS NULL
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => r.family_id,
        p_type         => 'workshop_started',
        p_args         => jsonb_build_object(
          'title',       r.title,
          'child_name',  COALESCE(r.child_name, 'your kid'),
          'workshop_id', r.wid::TEXT
        ),
        p_reference_id => r.wid
      );
      UPDATE workshop_registrations
         SET started_notified_at = now()
       WHERE id = r.registration_id;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'workshop.started.notify_failed',
              'workshop_registration', r.registration_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;

  RETURN jsonb_build_object('started_nudged_count', v_count);
END $function$;

-- ── workshop_send_thanks ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.workshop_send_thanks()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
BEGIN
  -- Thanks push fires 20 min after the workshop's scheduled end time —
  -- only for registrations the staff marked attended. No-shows are
  -- excluded so they don't get a misleading thank-you. Cap the look-
  -- back to 24h to avoid flooding past attendees if the cron was
  -- offline for a while.
  FOR r IN
    SELECT wr.id AS registration_id,
           wr.family_id, wr.child_id,
           w.id AS wid, w.title,
           c.name AS child_name
      FROM workshop_registrations wr
      JOIN workshops w ON w.id = wr.workshop_id
      LEFT JOIN children c ON c.id = wr.child_id
     WHERE wr.attended = TRUE
       AND wr.cancelled_at IS NULL
       AND wr.thanks_notified_at IS NULL
       AND w.scheduled_at + ((w.duration_minutes + 20) || ' minutes')::INTERVAL <= now()
       AND w.scheduled_at + ((w.duration_minutes + 20) || ' minutes')::INTERVAL > now() - INTERVAL '24 hours'
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => r.family_id,
        p_type         => 'workshop_thanks',
        p_args         => jsonb_build_object(
          'title',       r.title,
          'child_name',  COALESCE(r.child_name, 'your kid'),
          'workshop_id', r.wid::TEXT
        ),
        p_reference_id => r.wid
      );
      UPDATE workshop_registrations
         SET thanks_notified_at = now()
       WHERE id = r.registration_id;
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'workshop.thanks.notify_failed',
              'workshop_registration', r.registration_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;

  RETURN jsonb_build_object('thanks_sent_count', v_count);
END $function$;
