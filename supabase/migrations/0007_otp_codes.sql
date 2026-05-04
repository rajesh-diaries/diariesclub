-- ===========================================================================
--  Diaries Club v1.5 — 0007_otp_codes.sql
--  Server-side OTP storage for the auth-otp Edge Function (Session 4).
--
--  Pattern B: the Edge Function owns OTP issuance + verification (not Supabase
--  Auth's built-in phone provider). The Edge Function runs as service_role,
--  so RLS doesn't apply to it; we still enable RLS to lock anon/authenticated
--  out of reading other people's pending codes.
--
--  Lifecycle:
--    * `send`   inserts a row with code_hash + expires_at
--    * `verify` reads the latest non-expired row, increments attempts on
--               wrong code, deletes the row on success (or attempts >= 3)
--    * a periodic cleanup deletes rows older than 1 hour (defensive)
--
--  Idempotent. Safe to re-run.
-- ===========================================================================

CREATE TABLE IF NOT EXISTS otp_codes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone       TEXT NOT NULL,                    -- E.164 (+91...)
  code_hash   TEXT NOT NULL,                    -- sha256 hex of the OTP
  expires_at  TIMESTAMPTZ NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lookups: latest unexpired code for a phone, and rate-limit window scan.
CREATE INDEX IF NOT EXISTS idx_otp_codes_phone_created
  ON otp_codes(phone, created_at DESC);

-- RLS: lock everyone out of the table. The Edge Function uses the service
-- role, which bypasses RLS — that's the only path that ever touches this.
ALTER TABLE otp_codes ENABLE ROW LEVEL SECURITY;

-- Drop+recreate so the migration is re-runnable.
DROP POLICY IF EXISTS otp_codes_no_anon  ON otp_codes;
DROP POLICY IF EXISTS otp_codes_no_authn ON otp_codes;

CREATE POLICY otp_codes_no_anon  ON otp_codes FOR ALL TO anon          USING (false) WITH CHECK (false);
CREATE POLICY otp_codes_no_authn ON otp_codes FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- Defensive cleanup of expired/abandoned rows. Edge Function calls this as a
-- best-effort housekeeping at the start of `send`. It's cheap.
CREATE OR REPLACE FUNCTION otp_codes_cleanup() RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM otp_codes
   WHERE created_at < now() - INTERVAL '1 hour'
      OR expires_at  < now() - INTERVAL '5 minutes';
$$;

REVOKE EXECUTE ON FUNCTION public.otp_codes_cleanup() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.otp_codes_cleanup() TO service_role;
