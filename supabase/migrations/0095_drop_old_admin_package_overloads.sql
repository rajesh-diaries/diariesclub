-- 0095 — drop the stale admin_package_create / admin_package_update
-- overloads left behind by 0081 + 0085 + 0087 (each migration added
-- new params at the tail, but the older signatures persisted).
-- PostgREST couldn't pick between three signatures and the Flutter
-- admin form's RPC call would fail. With these dropped, only the
-- latest signature (with p_experience_inclusions + p_category) remains.

DROP FUNCTION IF EXISTS public.admin_package_create(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, integer,
  text, integer, integer, integer, integer, text
);
DROP FUNCTION IF EXISTS public.admin_package_create(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, integer,
  text, integer, integer, integer, integer, text, jsonb
);

DROP FUNCTION IF EXISTS public.admin_package_update(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, boolean, integer,
  text, integer, integer, integer, integer, text
);
DROP FUNCTION IF EXISTS public.admin_package_update(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, boolean, integer,
  text, integer, integer, integer, integer, text, jsonb
);
