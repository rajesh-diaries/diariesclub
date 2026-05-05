-- ===========================================================================
--  Migration 0022 — Hold-then-charge session architecture (BUG-004) schema
--
--  Replaces the immediate-debit model for customer-initiated wallet
--  sessions with a hold-then-charge flow:
--    1. Customer creates a session in the app → session.status='pending',
--       wallet.held_paise += amount (balance untouched).
--    2. Staff scans QR at counter → qr_scan_validate flips status='active',
--       converts hold to debit (held_paise -= amount, balance_paise -=
--       amount, wallet_transactions session_debit row inserted).
--    3. If 15 minutes pass without a scan → session_cancel_pending fires
--       from a cron, releases the hold (held_paise -= amount), sets
--       status='cancelled_pre_scan'. No transaction recorded — no debit
--       ever happened.
--
--  Cash sessions and staff-counter-initiated sessions are unchanged
--  (immediate active+debit). The pending state is exclusively for the
--  customer→QR→scan flow, which is the only path with the "I created it
--  but didn't actually show up" risk.
--
--  Reversibility:
--    ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_status_check;
--    ALTER TABLE sessions
--      ADD CONSTRAINT sessions_status_check
--      CHECK (status IN ('active','grace','completed','void','auto_closed'));
--    ALTER TABLE wallets DROP COLUMN IF EXISTS held_paise;
--    ALTER TABLE venue_config DROP COLUMN IF EXISTS session_pre_scan_timeout_minutes;
-- ===========================================================================

BEGIN;

-- 1. Wallet holds. Held amount cannot be re-spent until released or
--    converted to a debit. Invariant: balance_paise - held_paise >= 0
--    at all times (RPCs check this before holding).
ALTER TABLE wallets
  ADD COLUMN IF NOT EXISTS held_paise INTEGER NOT NULL DEFAULT 0
  CHECK (held_paise >= 0);

COMMENT ON COLUMN wallets.held_paise IS
  'Soft-reserved paise for pending sessions. balance_paise - held_paise = spendable. Decremented when session moves pending→active (debit recorded) or pending→cancelled_pre_scan (hold released).';

-- 2. Extend sessions.status to allow the new states. Old data unaffected
--    because existing values stay valid in the expanded list.
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_status_check;
ALTER TABLE sessions
  ADD CONSTRAINT sessions_status_check
  CHECK (status IN (
    'pending',              -- created from customer app, awaiting staff QR scan
    'active',               -- scanned + running
    'grace',                -- past expires_at, within grace window
    'completed',            -- naturally ended
    'auto_closed',          -- force-closed via grace cron
    'void',                 -- admin-voided
    'cancelled_pre_scan'    -- hit timeout before scan, hold released
  ));

-- 3. Index for the autocancel cron — sweeps pending sessions older than the
--    timeout. Partial index keeps it small (most sessions are not pending).
CREATE INDEX IF NOT EXISTS idx_sessions_pending_created
  ON sessions(created_at)
  WHERE status = 'pending';

-- 4. Per-venue timeout knob. Keep it tunable per venue without a code
--    change; default 15 minutes is the BUG-004 spec.
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS session_pre_scan_timeout_minutes INTEGER NOT NULL DEFAULT 15
  CHECK (session_pre_scan_timeout_minutes BETWEEN 1 AND 120);

COMMIT;
