-- 0209_invoice_year_counters_rls_lockdown.sql
-- P0 SECURITY FIX — lock down the invoice sequence counter.
--
-- BACKGROUND
--   invoice_year_counters was created in 0100_gst_invoice_schema.sql with a plain
--   CREATE TABLE and never had RLS enabled. It therefore carries Supabase's default
--   public-schema privileges, so today:
--       anon          -> SELECT, INSERT
--       authenticated -> SELECT, UPDATE
--   i.e. any unauthenticated or logged-in client can read and TAMPER WITH the invoice
--   number sequence via PostgREST, corrupting invoice numbering (duplicates / skips).
--   (Flagged by the security advisor: rls_disabled_in_public — the only ERROR.)
--
-- WHY THIS IS SAFE (verified against live prod, read-only)
--   The counter is written by exactly one helper, _next_invoice_number(), which is
--   SECURITY INVOKER — but it is called by exactly one caller, order_place(), which is
--   SECURITY DEFINER and owned by `postgres`. Inside that definer context the whole call
--   (including the nested _next_invoice_number()) executes as `postgres`, the table owner,
--   which bypasses both RLS and table grants. No legitimate client path touches the table
--   directly, so enabling RLS + revoking client privileges does not break invoicing.
--
-- NOTE: this migration intentionally CHANGES prod behaviour (that is the P0 fix). It is
-- also safe to replay: ENABLE RLS and REVOKE are idempotent.

-- 1. Enable RLS. With no policies defined this is deny-all for anon/authenticated;
--    the table owner (postgres) and service_role still have full access.
ALTER TABLE public.invoice_year_counters ENABLE ROW LEVEL SECURITY;

-- 2. Belt-and-suspenders: strip the default client privileges outright.
REVOKE ALL ON TABLE public.invoice_year_counters FROM anon, authenticated;

-- 3. Defense in depth: the invoker helper is directly EXECUTE-able by clients today.
--    It must only ever run inside order_place(); block direct client calls.
--    NOTE: EXECUTE is held via the default PUBLIC grant (proacl `=X/postgres`), not a
--    direct anon/authenticated grant — so the revoke MUST target PUBLIC. postgres and
--    service_role keep their explicit grants, so order_place()'s definer path is intact.
REVOKE EXECUTE ON FUNCTION public._next_invoice_number() FROM PUBLIC;
