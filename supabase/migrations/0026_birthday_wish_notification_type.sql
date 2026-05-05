-- ===========================================================================
--  Migration 0026 — Add 'birthday_wish' to notifications.type CHECK
--
--  FEATURE-001 introduces a universal birthday wish that fires for every
--  active child on their DOB, regardless of whether the family has a
--  birthday_reservation. The journey-cron's existing 'birthday_d_zero'
--  type is owned by the funnel (interested → confirmed); FEATURE-001's
--  wish is universal and uses a distinct type so audit/analytics can
--  split which cron sent which message.
--
--  Reservations resolution: with FEATURE-001 owning day-0, the
--  birthday-journey-cron drops the 0-day touchpoint entirely — its new
--  cadence (BUG-009) is [28, 14, 7, 3]. The discovery-page timeline
--  still shows a "Today!" dot as a UI element; that's purely visual.
--
--  Reversibility:
--    UPDATE notifications SET type='birthday_d_zero' WHERE type='birthday_wish';
--    ALTER TABLE notifications DROP CONSTRAINT notifications_type_check;
--    -- re-add the original list from 0001_initial_schema.sql:816
-- ===========================================================================

BEGIN;

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IN (
    'session_started','hydration_nudge','healthy_bite_earned',
    'grace_started','extend_nudge','session_closed','recap_ready',
    'reflection_prompt','reflection_auto_split',
    'order_confirmed','order_ready',
    'hero_card_received','stage_transition_imminent','stage_transition_revealed','level_up',
    'birthday_d_minus_90','birthday_d_minus_60','birthday_d_minus_30',
    'birthday_d_minus_14','birthday_d_minus_7','birthday_d_minus_3',
    'birthday_d_minus_1','birthday_d_zero',
    'birthday_d_plus_1','birthday_album_ready',
    'birthday_hero_progression_trigger',
    'birthday_wish',                       -- FEATURE-001 (new)
    'referral_reward','first_referral_brave_boost',
    'wallet_topup','wallet_low_balance',
    'visit_milestone','streak_milestone',
    'refund_processed','reactivation_welcome',
    'workshop_reminder','workshop_cancelled',
    'pre_booking_reminder','pre_booking_expired',
    'while_you_wait_food'
  ));

COMMIT;
