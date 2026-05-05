-- ===========================================================================
--  Migration 0035 — Public buckets for marketing content
--
--  Storage bucket public/private split (ARCHITECTURE-001):
--
--    Public (set/keep public — promotional, no PII):
--      workshop-photos     ← flipped here
--      menu-photos         ← flipped here
--      package-photos      ← created here
--      hero-cards          (already public — rendered hero art)
--      hero-recaps         (already public — session recap social art)
--
--    Private (must remain private — user-uploaded sensitive content):
--      birthday-photos     (customer-uploaded kid photos)
--      child-photos        (per-child profile photos)
--      invoices            (financial documents)
--
--  Rationale: marketing content uses unguessable UUID filenames and is
--  meant to be linkable from anywhere (push deep-links, social shares,
--  WhatsApp). Setting public=true means getPublicUrl() returns a URL
--  that resolves without auth, eliminating per-module signed-URL
--  provider plumbing for promotional images.
--
--  RLS policies for write access stay the same (service_role only on
--  the marketing buckets). The bucket-level public=TRUE makes the read
--  side work via the storage HTTP gateway without going through RLS.
--
--  Reversibility:
--    UPDATE storage.buckets SET public = FALSE
--     WHERE id IN ('workshop-photos','menu-photos','package-photos');
--    DELETE FROM storage.buckets WHERE id = 'package-photos';
-- ===========================================================================

BEGIN;

-- 1. Flip existing buckets.
UPDATE storage.buckets
   SET public = TRUE
 WHERE id IN ('workshop-photos', 'menu-photos');

-- 2. Create package-photos as public from the start.
INSERT INTO storage.buckets (id, name, public)
VALUES ('package-photos', 'package-photos', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

-- RLS for package-photos: same shape as workshop-photos / menu-photos
-- (service-role writes; reads happen via the public URL path that
-- bypasses RLS once public=TRUE).
DROP POLICY IF EXISTS "package_photos_authenticated_read" ON storage.objects;
CREATE POLICY "package_photos_authenticated_read"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'package-photos');

DROP POLICY IF EXISTS "package_photos_service_role_write" ON storage.objects;
CREATE POLICY "package_photos_service_role_write"
  ON storage.objects FOR ALL
  TO service_role
  USING (bucket_id = 'package-photos')
  WITH CHECK (bucket_id = 'package-photos');

COMMIT;
