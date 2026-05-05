-- ===========================================================================
--  Migration 0029 — venue_config.birthday_home_card_threshold_days (BUG-018)
--
--  Threshold for switching the home-screen birthday card from "discovery"
--  to "rich active" mode. When a child has interest_state='interested'
--  and days_until_birthday <= this threshold, the card renders the rich
--  variant ("Plan the party →"); otherwise the discovery variant
--  ("Explore birthday packages →") shows.
--
--  Default 30 days (replaces the hardcoded 90-day prompting window in
--  the previous BirthdayCardList implementation).
--
--  Reversibility:
--    ALTER TABLE venue_config DROP COLUMN IF EXISTS birthday_home_card_threshold_days;
-- ===========================================================================

BEGIN;

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS birthday_home_card_threshold_days INTEGER
    NOT NULL DEFAULT 30
    CHECK (birthday_home_card_threshold_days BETWEEN 1 AND 365);

COMMIT;
