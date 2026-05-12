-- 0123 — extend xp_events.event_type check constraint.
--
-- Two newer RPCs feed xp_credit_with_split with event_types that
-- weren't in the original allowlist:
--   * log_parent_moment → 'parent_log_moment'
--   * admin_grant_xp     → 'admin_manual_grant'
--
-- Both were failing with "violates check constraint
-- xp_events_event_type_check" the moment the kid actually accumulated
-- XP from those paths. Drop and re-add the constraint with both types
-- whitelisted.

ALTER TABLE xp_events DROP CONSTRAINT IF EXISTS xp_events_event_type_check;
ALTER TABLE xp_events ADD CONSTRAINT xp_events_event_type_check
  CHECK (event_type IN (
    'play_session',
    'reflection_split',
    'auto_split',
    'healthy_bite',
    'workshop',
    'birthday_hosted',
    'birthday_guest',
    'first_session',
    'streak_bonus',
    'referral_bonus',
    'birthday_bonus',
    'visit_milestone',
    'manual_admin',
    'admin_manual_grant',
    'parent_log_moment'
  ));
