-- 0165 — Per-type push TTL.
--
-- Without an explicit TTL FCM holds undelivered pushes ~4 weeks (default)
-- and APNs queues priority-10 alerts indefinitely. A session_started
-- delivered 30 min late is noise; a workshop_starting_soon delivered
-- after the workshop ends is worse. This migration adds a per-type TTL
-- so send-push v14 sets android.ttl + apns-expiration accordingly and
-- the carrier-level retries are bounded to the relevant window.
--
-- Founder note 2026-05-18: chose values for the urgent types only.
-- NULL means "no TTL header" → FCM/APNs defaults apply (~4 weeks).

ALTER TABLE notification_templates
  ADD COLUMN IF NOT EXISTS ttl_seconds INTEGER;

COMMENT ON COLUMN notification_templates.ttl_seconds IS
  'Seconds the push may be held by FCM/APNs for an offline device. '
  'NULL = no explicit TTL (carrier default ~4 weeks). Send-push '
  'translates this into android.ttl + apns-expiration.';

UPDATE notification_templates SET ttl_seconds = 300       WHERE type = 'session_started';
UPDATE notification_templates SET ttl_seconds = 300       WHERE type = 'grace_started';
UPDATE notification_templates SET ttl_seconds = 600       WHERE type = 'extend_nudge';
UPDATE notification_templates SET ttl_seconds = 1800      WHERE type = 'session_closed';
UPDATE notification_templates SET ttl_seconds = 900       WHERE type = 'hydration_nudge';
UPDATE notification_templates SET ttl_seconds = 1800      WHERE type = 'healthy_bite_earned';
UPDATE notification_templates SET ttl_seconds = 3600      WHERE type = 'workshop_starting_soon';
UPDATE notification_templates SET ttl_seconds = 1800      WHERE type = 'workshop_started';
UPDATE notification_templates SET ttl_seconds = 86400     WHERE type = 'workshop_attended';
UPDATE notification_templates SET ttl_seconds = 86400     WHERE type = 'workshop_thanks';
UPDATE notification_templates SET ttl_seconds = 604800    WHERE type = 'workshop_registered';
UPDATE notification_templates SET ttl_seconds = 86400     WHERE type = 'birthday_wish';
UPDATE notification_templates SET ttl_seconds = 43200     WHERE type IN ('birthday_lead_d_minus_30','birthday_lead_d_minus_15');
UPDATE notification_templates SET ttl_seconds = 604800    WHERE type LIKE 'birthday_d_%';
UPDATE notification_templates SET ttl_seconds = 604800    WHERE type IN ('workshop_reminder','workshop_cancelled','announcement_published');
UPDATE notification_templates SET ttl_seconds = 604800    WHERE type IN ('wallet_topup','wallet_low_balance','refund_processed');
