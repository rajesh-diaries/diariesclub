-- ===========================================================================
--  Migration 0020 — Universal child birthday wishes (FEATURE-001) schema
--
--  Adds per-venue copy + enable toggle, per-family preference key, and the
--  child_birthday_wishes_sent ledger that gives the cron its idempotency
--  guarantee. The cron itself is registered in migration 0024 once the
--  Edge Function is deployed.
--
--  Reversibility (drop script):
--    DROP TABLE IF EXISTS child_birthday_wishes_sent;
--    UPDATE families
--      SET notification_preferences = notification_preferences - 'birthday_wish_enabled';
--    ALTER TABLE families ALTER COLUMN notification_preferences SET DEFAULT '{
--        "session_reminders": true, "hero_progression": true,
--        "birthday_reminders": true, "order_status": true,
--        "wallet_alerts": true, "marketing": false,
--        "streaks_milestones": true, "workshop_reminders": true
--      }'::jsonb;
--    ALTER TABLE venue_config
--      DROP COLUMN IF EXISTS child_birthday_wish_enabled,
--      DROP COLUMN IF EXISTS child_birthday_wish_time,
--      DROP COLUMN IF EXISTS child_birthday_wish_copy_celebrating,
--      DROP COLUMN IF EXISTS child_birthday_wish_copy_default;
-- ===========================================================================

BEGIN;

-- 1. Venue-level toggle + copy + send time. Copy fields are TEXT so admin
--    can edit later via the venue_config admin page (Session 11 admin web).
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS child_birthday_wish_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS child_birthday_wish_time TIME NOT NULL DEFAULT '00:30:00',
  ADD COLUMN IF NOT EXISTS child_birthday_wish_copy_celebrating TEXT NOT NULL DEFAULT
    'Happy birthday {child}! 🎂 Thank you for celebrating with your Play Diaries family today. May your day be filled with joy ✨',
  ADD COLUMN IF NOT EXISTS child_birthday_wish_copy_default TEXT NOT NULL DEFAULT
    'Happy birthday {child}! 🎂 Wishing you joy and lots of laughter today, from your Play Diaries family ✨';

-- 2. Per-family preference key. Existing rows have notification_preferences
--    set; we only need to add the new key with a default of true. We bump
--    the table-level default to include the new key for any future families.
UPDATE families
   SET notification_preferences = notification_preferences || jsonb_build_object('birthday_wish_enabled', TRUE)
 WHERE NOT (notification_preferences ? 'birthday_wish_enabled');

ALTER TABLE families
  ALTER COLUMN notification_preferences SET DEFAULT '{
    "session_reminders": true,
    "hero_progression": true,
    "birthday_reminders": true,
    "order_status": true,
    "wallet_alerts": true,
    "marketing": false,
    "streaks_milestones": true,
    "workshop_reminders": true,
    "birthday_wish_enabled": true
  }'::jsonb;

-- 3. Idempotency + audit ledger for wishes. UNIQUE(child_id, year) is what
--    the cron checks before sending — even if it runs twice in the same
--    day, the second insert raises 23505 and the cron skips.
CREATE TABLE IF NOT EXISTS child_birthday_wishes_sent (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id        UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  year            INTEGER NOT NULL,
  sent_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  was_celebrating BOOLEAN NOT NULL DEFAULT FALSE,
  channel         TEXT NOT NULL CHECK (channel IN ('push','sms','push+sms','none')),
  UNIQUE (child_id, year)
);
CREATE INDEX IF NOT EXISTS idx_birthday_wishes_year_sent
  ON child_birthday_wishes_sent(year, sent_at DESC);

-- RLS: family members can read their own children's wish history; only
-- service_role writes (the cron is the only writer).
ALTER TABLE child_birthday_wishes_sent ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "family reads own child wishes" ON child_birthday_wishes_sent;
CREATE POLICY "family reads own child wishes"
  ON child_birthday_wishes_sent FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM children c
      WHERE c.id = child_birthday_wishes_sent.child_id
        AND c.family_id = auth.uid()
    )
  );

COMMIT;
