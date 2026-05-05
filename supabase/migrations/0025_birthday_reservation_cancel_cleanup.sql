-- ===========================================================================
--  Migration 0025 — birthday_reservation_cancel cleanup (BUG-013 follow-up)
--
--  Two related fixups, applied here because 0023 introduced a v2 of
--  birthday_reservation_cancel that needs supporting state changes:
--
--    1. Extend birthday_reservations.status CHECK to allow
--       'cancelled_by_customer'. The 0014 RPC used the generic 'cancelled'
--       status; the new BUG-013 spec wants 'cancelled_by_customer' to
--       distinguish customer-initiated from admin/system cancellations
--       in analytics + admin reports.
--
--    2. Drop the 0014 birthday_reservation_cancel(UUID, TEXT) overload.
--       The 0023 version is 1-arg (no free-text reason) and hardcodes
--       cancelled_reason='customer_initiated'. Without this drop, PostgREST
--       hits the same overload-ambiguity issue we saw in BUG-010.
--
--  Reversibility:
--    -- Re-add the old overload from 0014 line 403 if needed (paste body).
--    ALTER TABLE birthday_reservations DROP CONSTRAINT birthday_reservations_status_check;
--    ALTER TABLE birthday_reservations ADD CONSTRAINT birthday_reservations_status_check
--      CHECK (status IN ('interested','admin_contacted','confirmed','completed','cancelled','no_show'));
-- ===========================================================================

BEGIN;

ALTER TABLE birthday_reservations DROP CONSTRAINT IF EXISTS birthday_reservations_status_check;
ALTER TABLE birthday_reservations
  ADD CONSTRAINT birthday_reservations_status_check
  CHECK (status IN (
    'interested',
    'admin_contacted',
    'confirmed',
    'completed',
    'cancelled',              -- legacy / admin-cancel; kept for back-compat
    'cancelled_by_customer',  -- BUG-013 customer self-cancel (new)
    'no_show'
  ));

DROP FUNCTION IF EXISTS birthday_reservation_cancel(UUID, TEXT);

COMMIT;
