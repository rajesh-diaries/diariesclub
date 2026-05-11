-- 0086 — extensibility hooks for future offering types
--
-- Adds a `category` column so birthday_packages can later host other
-- offerings (snack & play, weekly events, etc.) without a schema
-- rename. Existing rows default to 'birthday'. Customer queries are
-- updated to filter category='birthday' so birthday-only surfaces
-- stay clean even when new categories are added.
--
-- Also drops the tier CHECK constraint so the admin form can switch
-- to a free-text field — founder no longer needs a migration to
-- introduce new tiers ('snack_play', 'weekly_once', etc.).

ALTER TABLE birthday_packages
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'birthday';

CREATE INDEX IF NOT EXISTS idx_birthday_packages_category
  ON birthday_packages(category) WHERE is_active = true;

ALTER TABLE birthday_packages DROP CONSTRAINT IF EXISTS birthday_packages_tier_check;
