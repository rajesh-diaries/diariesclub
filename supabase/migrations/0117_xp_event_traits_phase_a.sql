-- 0117 — admin-configurable trait per XP event (Phase A).
--
-- Adds xp_<event>_trait columns to venue_config for every admin-defined
-- XP event. Workshop attendance is skipped — workshops carry their own
-- primary_trait column for per-workshop routing. Per-session-minute and
-- reflection_participation are customer-driven via moment taps and don't
-- need a fixed trait.
--
-- Wires the trait config into streak_update + birthday_complete. Other
-- events (healthy_bite, birthday_guest, birthday_bonus, first_session)
-- have no firing RPC today; their columns are added so the admin form
-- has somewhere to write — wiring follows when those events get built.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_healthy_bite_trait    TEXT NOT NULL DEFAULT 'ellie'
    CHECK (xp_healthy_bite_trait IN ('rafi','ellie','gerry','zena','split'));
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_birthday_hosted_trait TEXT NOT NULL DEFAULT 'split'
    CHECK (xp_birthday_hosted_trait IN ('rafi','ellie','gerry','zena','split'));
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_birthday_guest_trait  TEXT NOT NULL DEFAULT 'ellie'
    CHECK (xp_birthday_guest_trait IN ('rafi','ellie','gerry','zena','split'));
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_birthday_bonus_trait  TEXT NOT NULL DEFAULT 'split'
    CHECK (xp_birthday_bonus_trait IN ('rafi','ellie','gerry','zena','split'));
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_first_session_trait   TEXT NOT NULL DEFAULT 'rafi'
    CHECK (xp_first_session_trait IN ('rafi','ellie','gerry','zena','split'));
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS xp_streak_bonus_trait    TEXT NOT NULL DEFAULT 'split'
    CHECK (xp_streak_bonus_trait IN ('rafi','ellie','gerry','zena','split'));

-- streak_update routes the bonus via _xp_split_for_trait.
-- (Full body lives in DB; this migration applied directly via MCP.)

-- birthday_complete routes hosted XP via _xp_split_for_trait.
-- (Full body lives in DB; this migration applied directly via MCP.)

-- admin_set_venue_config allowlist extended with the new trait keys.
-- (Body in DB; this migration applied via MCP.)
