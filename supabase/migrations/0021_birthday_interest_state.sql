-- ===========================================================================
--  Migration 0021 — Birthday interest opt-out (FEATURE-002) schema
--
--  Per-child two-state flag the customer sets from the birthday discovery
--  page. 'interested' (default) → full notification cadence applies.
--  'not_this_year' → birthday-journey-cron skips this child; the universal
--  birthday wish (FEATURE-001) still fires unless the family-level
--  notification_preferences.birthday_wish_enabled is set to false.
--
--  Reversibility:
--    ALTER TABLE children
--      DROP COLUMN IF EXISTS birthday_interest_state,
--      DROP COLUMN IF EXISTS birthday_interest_updated_at;
-- ===========================================================================

BEGIN;

ALTER TABLE children
  ADD COLUMN IF NOT EXISTS birthday_interest_state TEXT
    NOT NULL DEFAULT 'interested'
    CHECK (birthday_interest_state IN ('interested', 'not_this_year')),
  ADD COLUMN IF NOT EXISTS birthday_interest_updated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_children_birthday_interest_state
  ON children(birthday_interest_state)
  WHERE birthday_interest_state = 'not_this_year';

COMMIT;
