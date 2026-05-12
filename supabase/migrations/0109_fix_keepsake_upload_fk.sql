-- 0109 — birthday_party_photos.uploaded_by_admin FKs auth.users(id),
-- not admin_users(id). The 0108 upload RPC inserted v_admin.id which
-- broke the FK ("violates foreign key constraint
-- birthday_party_photos_uploaded_by_admin_fkey"). Use auth.uid() instead.
-- The birthday_album_publish call still gets admin_users.id for audit
-- logging because that audit_log column expects the admin row id.

CREATE OR REPLACE FUNCTION public.admin_birthday_keepsake_upload(
  p_reservation_id UUID,
  p_storage_path   TEXT,
  p_caption        TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res     birthday_reservations%ROWTYPE;
  v_admin   admin_users%ROWTYPE;
  v_photo   birthday_party_photos%ROWTYPE;
  v_auth_uid UUID := auth.uid();
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  SELECT * INTO v_admin FROM admin_users WHERE auth_user_id = v_auth_uid;
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_res.status <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state — party must be marked completed first';
  END IF;

  DELETE FROM birthday_party_photos WHERE reservation_id = p_reservation_id;

  INSERT INTO birthday_party_photos(
    reservation_id, photo_url, uploaded_by_admin, is_in_album, caption
  ) VALUES (
    p_reservation_id, p_storage_path, v_auth_uid, TRUE, p_caption
  ) RETURNING * INTO v_photo;

  PERFORM birthday_album_publish(p_reservation_id, v_admin.id, NULL);

  RETURN jsonb_build_object(
    'success', true,
    'photo_id', v_photo.id,
    'photo_url', v_photo.photo_url
  );
END $$;
