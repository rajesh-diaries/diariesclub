-- 0082 — admin RPCs to edit + cancel a birthday inquiry
--
-- After a customer submits an inquiry, founder calls them and may need
-- to revise: change the package, push the date, switch slot, change
-- guest count, add admin notes. The existing 'contact' / 'confirm' /
-- 'complete' RPCs only flip status; this adds the missing edit path.
--
-- Cancel is a separate explicit transition with a reason captured in
-- cancelled_reason (existing column).

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_edit(
  p_reservation_id UUID,
  p_package_id UUID DEFAULT NULL,
  p_slot_date DATE DEFAULT NULL,
  p_slot TEXT DEFAULT NULL,
  p_guest_count INTEGER DEFAULT NULL,
  p_special_requests TEXT DEFAULT NULL,
  p_admin_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  IF p_slot IS NOT NULL AND p_slot NOT IN ('morning','evening') THEN
    RAISE EXCEPTION 'invalid_slot';
  END IF;
  IF p_guest_count IS NOT NULL AND p_guest_count <= 0 THEN
    RAISE EXCEPTION 'invalid_guest_count';
  END IF;

  UPDATE birthday_reservations SET
    package_id       = COALESCE(p_package_id, package_id),
    slot_date        = COALESCE(p_slot_date, slot_date),
    slot             = COALESCE(p_slot, slot),
    num_kids         = COALESCE(p_guest_count, num_kids),
    special_requests = COALESCE(p_special_requests, special_requests),
    admin_notes      = COALESCE(p_admin_notes, admin_notes)
  WHERE id = p_reservation_id
  RETURNING * INTO v_res;

  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'birthday.edit', 'birthday_reservations', p_reservation_id,
    jsonb_build_object(
      'package_id', p_package_id, 'slot_date', p_slot_date,
      'slot', p_slot, 'guest_count', p_guest_count,
      'special_requests', p_special_requests, 'admin_notes', p_admin_notes
    )
  );

  RETURN to_jsonb(v_res);
END $$;

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_cancel(
  p_reservation_id UUID,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  UPDATE birthday_reservations SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_reason = p_reason
  WHERE id = p_reservation_id
    AND status IN ('interested','admin_contacted','confirmed')
  RETURNING * INTO v_res;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_cancellable';
  END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'birthday.cancel', 'birthday_reservations', p_reservation_id,
    jsonb_build_object('reason', p_reason)
  );

  -- Acknowledge to family.
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_90',
    'Inquiry update',
    'Your birthday inquiry was cancelled. Reach us to discuss alternatives.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  RETURN to_jsonb(v_res);
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_birthday_reservation_edit(
  uuid, uuid, date, text, integer, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_birthday_reservation_edit(
  uuid, uuid, date, text, integer, text, text
) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_birthday_reservation_cancel(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_birthday_reservation_cancel(uuid, text)
  TO authenticated;
