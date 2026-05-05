-- ===========================================================================
--  Migration 0032 — Announcements schema (Module 2.3)
--
--  Multi-feed customer home, max 5 visible at a time. Type-priority
--  ordering: workshop > promo > event > general > closure. Auto-created
--  rows from workshops cascade-delete when the source workshop is
--  deleted; the customer-side query also auto-hides expired rows.
--
--  Reversibility:
--    DROP TRIGGER IF EXISTS trg_workshop_announcement_sync ON workshops;
--    DROP FUNCTION IF EXISTS workshop_announcement_sync();
--    DROP TABLE IF EXISTS announcements CASCADE;
-- ===========================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS announcements (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  body                TEXT,
  type                TEXT NOT NULL CHECK (type IN
    ('workshop','general','event','promo','closure')),
  cta_label           TEXT,
  cta_route           TEXT,
  photo_url           TEXT,
  visible_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  visible_until       TIMESTAMPTZ,
  is_published        BOOLEAN NOT NULL DEFAULT TRUE,
  source_workshop_id  UUID REFERENCES workshops(id) ON DELETE CASCADE,
  created_by          UUID REFERENCES auth.users(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partial index for the customer-side hot path: active rows.
CREATE INDEX IF NOT EXISTS idx_announcements_active
  ON announcements(venue_id, visible_from, visible_until)
  WHERE is_published = TRUE;

-- Workshop-sourced rows are unique per workshop — only one auto-created
-- announcement per workshop. Admin edits the row; doesn't duplicate.
CREATE UNIQUE INDEX IF NOT EXISTS idx_announcements_source_workshop
  ON announcements(source_workshop_id)
  WHERE source_workshop_id IS NOT NULL;

-- RLS
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "announcements_customer_read" ON announcements;
CREATE POLICY "announcements_customer_read"
  ON announcements FOR SELECT
  TO authenticated
  USING (
    is_published = TRUE
    AND visible_from <= now()
    AND (visible_until IS NULL OR visible_until > now())
  );

DROP POLICY IF EXISTS "announcements_admin_all" ON announcements;
CREATE POLICY "announcements_admin_all"
  ON announcements FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
       WHERE auth_user_id = auth.uid() AND is_active = TRUE
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
       WHERE auth_user_id = auth.uid() AND is_active = TRUE
    )
  );

-- Auto-sync trigger: when a workshop is published and starts within 14
-- days, mirror to an announcement (upsert by source_workshop_id). When
-- unpublished, the corresponding announcement is also unpublished.
CREATE OR REPLACE FUNCTION workshop_announcement_sync() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_within_14d BOOLEAN;
  v_body       TEXT;
BEGIN
  v_within_14d := NEW.scheduled_at <= now() + INTERVAL '14 days';

  IF NEW.is_published AND v_within_14d THEN
    v_body := COALESCE(LEFT(NEW.description, 100), '');
    IF length(COALESCE(NEW.description, '')) > 100 THEN
      v_body := v_body || '…';
    END IF;
    INSERT INTO announcements(
      venue_id, title, body, type,
      cta_label, cta_route,
      photo_url, visible_from, visible_until,
      source_workshop_id, is_published
    ) VALUES (
      NEW.venue_id,
      NEW.title || ' — ' || to_char(NEW.scheduled_at AT TIME ZONE 'Asia/Kolkata', 'Dy Mon DD'),
      v_body,
      'workshop',
      'Book your spot',
      '/club/workshops',
      NEW.cover_image_url,
      now(),
      NEW.scheduled_at + INTERVAL '1 hour',
      NEW.id,
      TRUE
    )
    ON CONFLICT (source_workshop_id) WHERE source_workshop_id IS NOT NULL
    DO UPDATE SET
      title = EXCLUDED.title,
      body = EXCLUDED.body,
      photo_url = EXCLUDED.photo_url,
      visible_until = EXCLUDED.visible_until,
      is_published = TRUE,
      updated_at = now();
  ELSIF NOT NEW.is_published THEN
    UPDATE announcements
       SET is_published = FALSE,
           updated_at = now()
     WHERE source_workshop_id = NEW.id;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_workshop_announcement_sync ON workshops;
CREATE TRIGGER trg_workshop_announcement_sync
  AFTER INSERT OR UPDATE OF is_published, title, description, scheduled_at, cover_image_url
  ON workshops
  FOR EACH ROW EXECUTE FUNCTION workshop_announcement_sync();

-- Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE announcements;

COMMIT;
