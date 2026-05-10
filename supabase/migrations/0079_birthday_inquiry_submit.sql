-- 0079 — birthday_inquiry_submit RPC
--
-- The old birthday_reservation_create RPC took preferred_month +
-- preferred_window (free-form text) and split guest count into kids
-- + adults. The simplified inquiry model uses:
--   * specific date (defaults to kid's next birthday in the UI)
--   * morning/evening slot
--   * single guest count
--   * special requests
-- Validation now uses min_guests / max_guests on the package.

DROP FUNCTION IF EXISTS public.birthday_reservation_create(
  uuid, uuid, uuid, uuid, text, text, integer, integer, text, text, text
);

CREATE OR REPLACE FUNCTION public.birthday_inquiry_submit(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_package_id UUID,
  p_slot_date DATE,
  p_slot TEXT,
  p_guest_count INTEGER,
  p_special_requests TEXT DEFAULT NULL,
  p_triggered_by TEXT DEFAULT 'manual',
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
  v_res birthday_reservations%ROWTYPE;
  v_birthday_year INTEGER;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_slot IS NULL OR p_slot NOT IN ('morning','evening') THEN
    RAISE EXCEPTION 'invalid_slot';
  END IF;
  IF p_guest_count IS NULL OR p_guest_count <= 0 THEN
    RAISE EXCEPTION 'invalid_guest_count';
  END IF;
  IF p_slot_date IS NULL THEN
    RAISE EXCEPTION 'invalid_slot_date';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations
     WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'reservation_id', v_existing.id
      );
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages
   WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  -- Reasonable upper bound. We DON'T hard-fail on min_guests since the
  -- founder will guide them on the call-back; just store what they asked.
  IF v_pkg.max_guests IS NOT NULL AND p_guest_count > v_pkg.max_guests THEN
    RAISE EXCEPTION 'invalid_guest_count'
      USING DETAIL = format('max for this package is %s', v_pkg.max_guests);
  END IF;

  -- Block duplicate inquiries for the same child within a year (same as
  -- old RPC). Prevents accidental double-submits.
  IF EXISTS (
    SELECT 1 FROM birthday_reservations
     WHERE child_id = p_child_id
       AND status IN ('interested','admin_contacted','confirmed')
       AND created_at > now() - INTERVAL '1 year'
  ) THEN
    RAISE EXCEPTION 'reservation_exists';
  END IF;

  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    slot_date, slot, special_requests,
    num_kids, num_adults,
    package_price_paise, balance_paise,
    triggered_by, idempotency_key, status
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_package_id,
    p_slot_date, p_slot, p_special_requests,
    p_guest_count, 0,
    COALESCE(v_pkg.price_per_pax_veg_paise, v_pkg.price_paise),
    0,
    p_triggered_by, p_idempotency_key, 'interested'
  ) RETURNING * INTO v_res;

  v_birthday_year := EXTRACT(YEAR FROM p_slot_date)::INTEGER;
  INSERT INTO birthday_journey_state(child_id, reservation_id, birthday_year, arc_type)
  VALUES (p_child_id, v_res.id, v_birthday_year, 'reserved')
  ON CONFLICT (child_id) DO UPDATE
    SET reservation_id = EXCLUDED.reservation_id,
        arc_type = 'reserved',
        updated_at = now();

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    p_family_id, 'birthday_d_minus_90',
    'Got it! Inquiry submitted.',
    'Our team will reach out within 4 hours to plan the details.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_family_id, 'customer', 'birthday.inquiry_submit', 'birthday_reservation',
    v_res.id, p_venue_id,
    jsonb_build_object(
      'package_id', p_package_id,
      'package_name', v_pkg.name,
      'slot_date', p_slot_date,
      'slot', p_slot,
      'guest_count', p_guest_count,
      'special_requests', p_special_requests,
      'triggered_by', p_triggered_by
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.birthday_inquiry_submit(
  uuid, uuid, uuid, uuid, date, text, integer, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.birthday_inquiry_submit(
  uuid, uuid, uuid, uuid, date, text, integer, text, text, text
) TO authenticated;
