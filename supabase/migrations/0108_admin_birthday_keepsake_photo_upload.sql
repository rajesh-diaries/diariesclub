-- 0108 — admin uploads the "little memory" keepsake photo.
--
-- After admin marks a party completed, they need to share one keepsake
-- photo with the family. This migration adds:
--   * admin_birthday_keepsake_upload — inserts the photo row + publishes
--   * admin_birthday_keepsake_delete — removes the photo, reverts album_ready_at
--   * Storage RLS allowing active admins to upload + delete in birthday-photos
--   * Softer notification copy on birthday_album_publish ("A little memory...")

CREATE POLICY birthday_photos_admin_write
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'birthday-photos'
    AND is_active_admin()
  );

CREATE POLICY birthday_photos_admin_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'birthday-photos'
    AND is_active_admin()
  );

CREATE POLICY birthday_photos_admin_read
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'birthday-photos'
    AND is_active_admin()
  );

CREATE OR REPLACE FUNCTION public.admin_birthday_keepsake_upload(
  p_reservation_id UUID,
  p_storage_path   TEXT,
  p_caption        TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res   birthday_reservations%ROWTYPE;
  v_admin admin_users%ROWTYPE;
  v_photo birthday_party_photos%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  SELECT * INTO v_admin FROM admin_users WHERE auth_user_id = auth.uid();
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_res.status <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state — party must be marked completed first';
  END IF;

  DELETE FROM birthday_party_photos WHERE reservation_id = p_reservation_id;

  INSERT INTO birthday_party_photos(
    reservation_id, photo_url, uploaded_by_admin, is_in_album, caption
  ) VALUES (
    p_reservation_id, p_storage_path, v_admin.id, TRUE, p_caption
  ) RETURNING * INTO v_photo;

  PERFORM birthday_album_publish(p_reservation_id, v_admin.id, NULL);

  RETURN jsonb_build_object(
    'success', true,
    'photo_id', v_photo.id,
    'photo_url', v_photo.photo_url
  );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_birthday_keepsake_upload(UUID, TEXT, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_birthday_keepsake_delete(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  DELETE FROM birthday_party_photos WHERE reservation_id = p_reservation_id;
  UPDATE birthday_reservations
     SET album_ready_at = NULL
   WHERE id = p_reservation_id;

  RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_birthday_keepsake_delete(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.birthday_album_publish(
  p_reservation_id UUID,
  p_admin_id UUID,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_photo_count INTEGER;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state_for_album';
  END IF;

  IF v_res.album_ready_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'idempotent', true,
      'album_ready_at', v_res.album_ready_at
    );
  END IF;

  SELECT COUNT(*) INTO v_photo_count FROM birthday_party_photos
    WHERE reservation_id = p_reservation_id;
  IF v_photo_count = 0 THEN RAISE EXCEPTION 'no_photos'; END IF;

  UPDATE birthday_reservations SET album_ready_at = now()
    WHERE id = p_reservation_id;

  INSERT INTO notifications(
    family_id, type, title, body, deep_link, reference_id
  ) VALUES (
    v_res.family_id, 'birthday_album_ready',
    'A little memory from us',
    'A small keepsake from your celebration is ready — tap to open.',
    '/birthday/album/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_admin_id, 'admin', 'birthday.album_publish', 'birthday_reservation',
    v_res.id, v_res.venue_id, jsonb_build_object('photo_count', v_photo_count)
  );

  RETURN jsonb_build_object('success', true, 'photo_count', v_photo_count);
END $$;
