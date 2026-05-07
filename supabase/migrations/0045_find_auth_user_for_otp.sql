-- =============================================================
--  find_auth_user_for_otp(p_phone)
--
--  Looks up an existing auth.users row by either:
--    * its phone column (digits, no leading +), or
--    * its synthetic email <digits>@phone.diariesclub.local
--
--  Used by the auth-otp Edge Function during verify so we can
--  reliably resolve an existing customer to their user_id, even
--  when the auth.users table grows past one page. We previously
--  tried filtering via GoTrue's /admin/users REST endpoint with
--  ?phone= and ?email= query params — neither is honoured;
--  GoTrue silently ignores both and returns the first 50 users
--  ordered by created_at desc. Once auth.users grew past page 1
--  (currently ~33 rows), the fallback `users.find(...)` started
--  returning undefined for older customers, so re-login broke.
--
--  SECURITY DEFINER + service_role-only EXECUTE: clients must
--  not be able to call this (would let an unauthenticated caller
--  enumerate accounts by phone).
-- =============================================================

CREATE OR REPLACE FUNCTION public.find_auth_user_for_otp(p_phone TEXT)
RETURNS TABLE(id UUID, email TEXT, phone TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT u.id, u.email::TEXT, u.phone::TEXT
  FROM auth.users u
  WHERE u.phone = REPLACE(p_phone, '+', '')
     OR u.email = (REPLACE(p_phone, '+', '') || '@phone.diariesclub.local')
  ORDER BY u.created_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_auth_user_for_otp(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_auth_user_for_otp(TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.find_auth_user_for_otp(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_auth_user_for_otp(TEXT) TO service_role;
