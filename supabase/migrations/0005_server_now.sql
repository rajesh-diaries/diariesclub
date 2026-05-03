-- ===========================================================================
--  Diaries Club v1.5 — 0005_server_now.sql
--
--  Tiny RPC the Flutter client calls on launch + every 5 minutes to compute
--  a server-clock offset. Used by the session timer so we never trust the
--  device clock for grace-period and OTP-expiry math.
--
--  STABLE so PostgREST can cache when called repeatedly in a transaction
--  (irrelevant for our single-call usage, but the right shape).
--  Open to anon + authenticated; nothing sensitive returned.
-- ===========================================================================
CREATE OR REPLACE FUNCTION server_now() RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('now', now()::text)
$$;

REVOKE EXECUTE ON FUNCTION public.server_now() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.server_now() TO anon, authenticated, service_role;
