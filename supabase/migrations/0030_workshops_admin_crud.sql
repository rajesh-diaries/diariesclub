-- ===========================================================================
--  Migration 0030 — Workshops admin CRUD prep (Module 2.2)
--
--  Adds:
--    1. workshops.is_published BOOLEAN — separate from status. Lets admin
--       hide a workshop without using the 'cancelled' status (which
--       semantically means "this workshop won't run", not "this workshop
--       isn't published yet").
--    2. workshop-photos storage bucket — private, signed URLs only.
--       Customer reads via signed URL provider (same pattern as
--       child-photos). Admin uploads via service-role.
--
--  Reversibility:
--    DELETE FROM storage.buckets WHERE id = 'workshop-photos';
--    ALTER TABLE workshops DROP COLUMN IF EXISTS is_published;
-- ===========================================================================

BEGIN;

ALTER TABLE workshops
  ADD COLUMN IF NOT EXISTS is_published BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_workshops_published
  ON workshops(scheduled_at)
  WHERE is_published = TRUE AND status = 'upcoming';

INSERT INTO storage.buckets (id, name, public)
VALUES ('workshop-photos', 'workshop-photos', false)
ON CONFLICT (id) DO NOTHING;

-- RLS for the new bucket: authenticated users can SELECT (so the
-- customer app can fetch via signed URL); only service-role writes.
DROP POLICY IF EXISTS "workshop_photos_authenticated_read"
  ON storage.objects;
CREATE POLICY "workshop_photos_authenticated_read"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'workshop-photos');

DROP POLICY IF EXISTS "workshop_photos_service_role_write"
  ON storage.objects;
CREATE POLICY "workshop_photos_service_role_write"
  ON storage.objects FOR ALL
  TO service_role
  USING (bucket_id = 'workshop-photos')
  WITH CHECK (bucket_id = 'workshop-photos');

COMMIT;
