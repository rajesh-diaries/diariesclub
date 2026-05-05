-- ===========================================================================
--  Migration 0027 — venue_config.session_extension_options (BUG-017 prep)
--
--  Replaces the per-hour-rate formula in session_extend (which truncated
--  30/60 to 0 via integer division — see BUG-017) with an explicit list
--  of {minutes, price_paise, label} entries. Admin can edit this list
--  later via Phase 2 admin Config UI to add 90 / 120 / etc. without a
--  code change.
--
--  Defaults preserve current effective prices: 30min = ₹150, 60min = ₹300.
--  The legacy session_extension_per_hour_paise column is left in place
--  for back-compat with admin web's existing Config screen
--  (lib/admin/config/config_screen.dart). Cleanup deferred to Phase 2.
--
--  Reversibility:
--    ALTER TABLE venue_config DROP COLUMN IF EXISTS session_extension_options;
-- ===========================================================================

BEGIN;

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS session_extension_options JSONB NOT NULL DEFAULT
    '[{"minutes":30,"price_paise":15000,"label":"+30 min"},
      {"minutes":60,"price_paise":30000,"label":"+60 min"}]'::jsonb;
-- Future admin can extend with 90, 120 etc. via Phase 2 admin Config UI.

COMMIT;
