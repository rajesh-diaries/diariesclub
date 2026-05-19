-- 0164 — Birthday lead-generation track.
--
-- Founder decision 2026-05-18: separate marketing-driven reminder track
-- for families who have NOT inquired about a birthday yet. Two touches:
-- D-30 ("a month away") and D-15 ("15 days to go") with sales copy
-- pitching customised menus + venue celebration.
--
-- Mutually exclusive with the existing journey track (which is for
-- already-inquired/booked families): the cron skips any child whose
-- family has an active birthday_journey_state row for the current
-- birthday year.
--
-- Dedup via a new birthday_marketing_state table — one row per child
-- per birthday year, tracking which of the two nudges has fired.

-- ── New notification types in the CHECK constraint ──────────────────────
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
    'birthday_lead_d_minus_30','birthday_lead_d_minus_15',
    'pre_booking_reminder','pre_booking_expired','while_you_wait_food',
    'announcement_published','hero_within_unlocked'
  ])
);

-- ── Templates ───────────────────────────────────────────────────────────
INSERT INTO notification_templates(
  type, category, enabled, title, body, deep_link_template,
  variables, preference_key
) VALUES (
  'birthday_lead_d_minus_30',
  'birthday',
  true,
  '🎂 {{child_name}}''s big day is a month away',
  'Celebrate at Diaries Club — customised menus, themed parties, plans tailored to your kid. Tap to plan.',
  '/birthday',
  '["child_name"]'::jsonb,
  'birthday_reminders'
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
  'birthday_lead_d_minus_15',
  'birthday',
  true,
  '15 days to {{child_name}}''s birthday',
  'Let our team host — customised menu, themed decor, play, and food. Tap to plan a celebration they''ll remember.',
  '/birthday',
  '["child_name"]'::jsonb,
  'birthday_reminders'
)
ON CONFLICT (type) DO UPDATE SET
  enabled = EXCLUDED.enabled,
  title   = EXCLUDED.title,
  body    = EXCLUDED.body,
  deep_link_template = EXCLUDED.deep_link_template,
  preference_key = EXCLUDED.preference_key,
  variables = EXCLUDED.variables;

-- ── Marketing state dedup table ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS birthday_marketing_state (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id           UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  birthday_year      INTEGER NOT NULL,
  d_minus_30_sent_at TIMESTAMPTZ,
  d_minus_15_sent_at TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(child_id, birthday_year)
);

CREATE INDEX IF NOT EXISTS idx_birthday_marketing_state_child
  ON birthday_marketing_state(child_id, birthday_year);

ALTER TABLE birthday_marketing_state ENABLE ROW LEVEL SECURITY;
-- service_role only; no customer or admin direct read.
DROP POLICY IF EXISTS birthday_marketing_state_service_role ON birthday_marketing_state;
CREATE POLICY birthday_marketing_state_service_role ON birthday_marketing_state
  FOR ALL USING (auth.role() = 'service_role');
