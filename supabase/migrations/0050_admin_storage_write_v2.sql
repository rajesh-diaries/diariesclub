-- ===========================================================================
--  Migration 0050 — admin storage write policies, v2 (SECURITY DEFINER fn)
--
--  0049 added admin-write storage policies using
--    EXISTS (SELECT 1 FROM admin_users ...)
--  inline. PostgreSQL stripped the `public.` schema prefix during DDL
--  (because public is in the default search_path), so the stored
--  policy text just says `FROM admin_users`. Supabase storage's policy
--  evaluator runs with a non-public search_path, so the lookup failed
--  and any upload returned
--    StorageException: DatabaseInvalidObjectDefinition (503)
--    "The database schema is invalid or incompatible."
--
--  Fix: hide the admin-table reference behind a SECURITY DEFINER
--  function `public.is_active_admin()`. Function call references keep
--  their qualified name in storage's policy parser, AND the function
--  body runs with `SET search_path = public` regardless of caller
--  search_path. Same pattern the codebase already uses for
--  `auth_family_id()`, `_is_active_tablet_for_venue()`, etc.
--
--  Cleanup: drops the 0049 inline policies and recreates them via the
--  function. Same intent, different shape.
--
--  Reversibility:
--    DROP POLICY {bucket}_admin_write ON storage.objects;  -- ×4
--    DROP FUNCTION public.is_active_admin();
-- ===========================================================================

-- 1. Helper: is the current authenticated user an active admin?
CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
     WHERE auth_user_id = auth.uid()
       AND is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_admin()
  TO authenticated, service_role;

-- 2. Drop the broken 0049 policies.
DROP POLICY IF EXISTS workshop_photos_admin_write ON storage.objects;
DROP POLICY IF EXISTS menu_photos_admin_write     ON storage.objects;
DROP POLICY IF EXISTS package_photos_admin_write  ON storage.objects;
DROP POLICY IF EXISTS hero_cards_admin_write      ON storage.objects;

-- 3. Recreate using public.is_active_admin().

CREATE POLICY workshop_photos_admin_write ON storage.objects
  FOR ALL TO authenticated
  USING       (bucket_id = 'workshop-photos' AND public.is_active_admin())
  WITH CHECK  (bucket_id = 'workshop-photos' AND public.is_active_admin());

CREATE POLICY menu_photos_admin_write ON storage.objects
  FOR ALL TO authenticated
  USING       (bucket_id = 'menu-photos' AND public.is_active_admin())
  WITH CHECK  (bucket_id = 'menu-photos' AND public.is_active_admin());

CREATE POLICY package_photos_admin_write ON storage.objects
  FOR ALL TO authenticated
  USING       (bucket_id = 'package-photos' AND public.is_active_admin())
  WITH CHECK  (bucket_id = 'package-photos' AND public.is_active_admin());

CREATE POLICY hero_cards_admin_write ON storage.objects
  FOR ALL TO authenticated
  USING       (bucket_id = 'hero-cards' AND public.is_active_admin())
  WITH CHECK  (bucket_id = 'hero-cards' AND public.is_active_admin());
