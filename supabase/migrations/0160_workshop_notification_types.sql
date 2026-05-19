-- 0160 — Add new workshop notification types to notifications.type CHECK.
--
-- Migrations 0153 (workshop_registered) and 0157 (workshop_starting_soon,
-- workshop_attended) added templates and patched RPCs to call
-- _send_notification with those types — but never updated the CHECK
-- constraint on notifications.type, so every insert silently failed:
--   "new row for relation \"notifications\" violates check constraint
--    \"notifications_type_check\""
-- Surfaced today (2026-05-18) during E2E: workshop registration confirmed
-- but parent never got the confirmation push; the cron tried to send the
-- 45-min reminder and audit-logged 'workshop.reminder.notify_failed'.

ALTER TABLE notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_type_check CHECK (
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
      'pre_booking_reminder','pre_booking_expired','while_you_wait_food',
      'announcement_published','hero_within_unlocked'
    ])
  );
