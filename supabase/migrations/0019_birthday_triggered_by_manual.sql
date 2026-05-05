-- ===========================================================================
--  Migration 0019 — birthday_reservations.triggered_by: allow 'manual'
--
--  The CHECK constraint defined in 0001_initial_schema.sql line 687 was
--  never updated when 0014_birthday_funnel.sql introduced 'manual' as the
--  default value for the birthday_reservation_create RPC's p_triggered_by
--  parameter (see 0014 line 151). Net effect: every app-originated
--  reservation that wasn't deep-linked from a funnel touchpoint failed
--  with 23514 violates check constraint birthday_reservations_triggered_by_check.
--
--  Semantics of 'manual':
--    User opened the app and reserved a package without arriving from a
--    specific funnel touchpoint (no ?trigger= query param). Distinct from:
--      'home_card'        — landed via home discovery card
--      'day_minus_*'      — landed via a D-N notification deep link
--      'hero_progression' — landed via a hero card unlock
--      'manual_admin'     — admin created on customer's behalf
--
--  Surfaced as BUG-010 during Phase 1A web testing.
-- ===========================================================================

ALTER TABLE birthday_reservations
  DROP CONSTRAINT IF EXISTS birthday_reservations_triggered_by_check;

ALTER TABLE birthday_reservations
  ADD CONSTRAINT birthday_reservations_triggered_by_check
  CHECK (triggered_by IN (
    'home_card',
    'day_minus_90', 'day_minus_60', 'day_minus_30',
    'day_minus_14', 'day_minus_7',  'day_minus_3',
    'hero_progression',
    'manual',
    'manual_admin'
  ));
