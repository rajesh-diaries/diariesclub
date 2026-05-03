-- ===========================================================================
--  Diaries Club v1.5 — 0002_security_hardening.sql
--  Address advisor warnings from 0001:
--    1. Pin search_path = public on functions that don't already set it.
--       Mitigates lint 0011 (function_search_path_mutable).
--    2. Revoke EXECUTE on create_wallet_for_family() from PUBLIC/anon/
--       authenticated. It's a trigger function and must NOT be reachable
--       via the REST /rpc/ surface. Trigger invocations are unaffected
--       (triggers run as the table owner regardless of EXECUTE grants).
--       Mitigates lints 0028/0029.
--
--  Idempotent. ALTER FUNCTION ... SET and REVOKE are both safe to re-run.
-- ===========================================================================

-- 1) Pin search_path = public on the four flagged functions.
ALTER FUNCTION public.auth_family_id()           SET search_path = public;
ALTER FUNCTION public.set_updated_at()           SET search_path = public;
ALTER FUNCTION public.validate_phone_e164()      SET search_path = public;
ALTER FUNCTION public.create_wallet_for_family() SET search_path = public;

-- 2) Revoke RPC access to the wallet-creation trigger function.
REVOKE EXECUTE ON FUNCTION public.create_wallet_for_family() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_wallet_for_family() FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_wallet_for_family() FROM authenticated;
