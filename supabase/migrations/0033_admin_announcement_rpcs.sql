-- ===========================================================================
--  Migration 0033 — admin_announcement_{create,update,delete} (Module 2.3)
--
--  Three RPCs for the admin Announcements UI. SECURITY DEFINER, audit-
--  logged, gated on _assert_active_admin() (helper from 0031).
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION admin_announcement_create(
  p_venue_id      UUID,
  p_title         TEXT,
  p_body          TEXT,
  p_type          TEXT,
  p_cta_label     TEXT,
  p_cta_route     TEXT,
  p_photo_url     TEXT,
  p_visible_from  TIMESTAMPTZ,
  p_visible_until TIMESTAMPTZ,
  p_is_published  BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      announcements%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();

  IF p_type NOT IN ('workshop','general','event','promo','closure') THEN
    RAISE EXCEPTION 'invalid_type';
  END IF;
  IF p_visible_until IS NOT NULL AND p_visible_until <= COALESCE(p_visible_from, now()) THEN
    RAISE EXCEPTION 'visible_until_before_from';
  END IF;

  INSERT INTO announcements(
    venue_id, title, body, type,
    cta_label, cta_route, photo_url,
    visible_from, visible_until, is_published, created_by
  ) VALUES (
    p_venue_id, p_title, p_body, p_type,
    p_cta_label, p_cta_route, p_photo_url,
    COALESCE(p_visible_from, now()), p_visible_until,
    COALESCE(p_is_published, TRUE),
    auth.uid()
  ) RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'announcement.create', 'announcement',
    v_row.id, p_venue_id,
    jsonb_build_object('title', p_title, 'type', p_type, 'is_published', v_row.is_published)
  );

  RETURN jsonb_build_object('success', true, 'announcement_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_announcement_create(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_announcement_create(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_announcement_update(
  p_id            UUID,
  p_title         TEXT,
  p_body          TEXT,
  p_type          TEXT,
  p_cta_label     TEXT,
  p_cta_route     TEXT,
  p_photo_url     TEXT,
  p_visible_from  TIMESTAMPTZ,
  p_visible_until TIMESTAMPTZ,
  p_is_published  BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      announcements%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();

  SELECT * INTO v_row FROM announcements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'announcement_not_found'; END IF;

  IF p_type NOT IN ('workshop','general','event','promo','closure') THEN
    RAISE EXCEPTION 'invalid_type';
  END IF;

  UPDATE announcements SET
    title = p_title,
    body = p_body,
    type = p_type,
    cta_label = p_cta_label,
    cta_route = p_cta_route,
    photo_url = p_photo_url,
    visible_from = COALESCE(p_visible_from, v_row.visible_from),
    visible_until = p_visible_until,
    is_published = COALESCE(p_is_published, v_row.is_published),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'announcement.update', 'announcement',
    v_row.id, v_row.venue_id,
    jsonb_build_object('title', p_title, 'type', p_type, 'is_published', v_row.is_published)
  );

  RETURN jsonb_build_object('success', true, 'announcement_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_announcement_update(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_announcement_update(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
  TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_announcement_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_row      announcements%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM announcements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'announcement_not_found'; END IF;
  IF NOT v_row.is_published THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  UPDATE announcements SET is_published = FALSE, updated_at = now() WHERE id = p_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (v_admin_id, 'admin', 'announcement.unpublish', 'announcement', p_id, v_row.venue_id);

  RETURN jsonb_build_object('success', true, 'announcement_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_announcement_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_announcement_delete(UUID) TO authenticated, service_role;

COMMIT;
