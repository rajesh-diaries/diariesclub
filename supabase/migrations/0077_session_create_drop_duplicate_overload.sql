-- 0077 — fix the duplicate session_create overload created by 0076.
--
-- 0076 used CREATE OR REPLACE FUNCTION but inadvertently changed the
-- argument order from the original (p_venue_id first) to a new order
-- (p_family_id first). PostgreSQL treats different argument orders as
-- different functions, so 0076 created a SECOND session_create instead
-- of replacing the first. PostgREST then could not disambiguate and
-- the app saw 'Couldn't start session. Please try again.'
--
-- Fix: drop the wrong-order overload and CREATE OR REPLACE with the
-- ORIGINAL signature, carrying the v_pending_scan logic forward so the
-- cash-must-scan behavior from 0076 is preserved.

DROP FUNCTION IF EXISTS public.session_create(
  p_family_id uuid, p_venue_id uuid, p_child_id uuid,
  p_duration_minutes integer, p_payment_method text,
  p_idempotency_key text, p_staff_pin_id uuid,
  p_is_guest boolean, p_guest_phone text,
  p_pre_booking_id uuid, p_coupon_code text
);

CREATE OR REPLACE FUNCTION public.session_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,
  p_staff_pin_id UUID DEFAULT NULL,
  p_is_guest BOOLEAN DEFAULT FALSE,
  p_guest_phone TEXT DEFAULT NULL,
  p_pre_booking_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL,
  p_coupon_code TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session    sessions%ROWTYPE;
  v_existing   sessions%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_amount     INTEGER;
  v_base_amount INTEGER;
  v_use_hold   BOOLEAN;
  v_pending_scan BOOLEAN;
  v_status     TEXT;
  v_started_at TIMESTAMPTZ;
  v_expires_at TIMESTAMPTZ;
  v_grace_at   TIMESTAMPTZ;
  v_coupon     coupons%ROWTYPE;
  v_normalized_code TEXT;
  v_coupon_discount INTEGER := 0;
  v_family_uses INTEGER;
  v_redemption_id UUID;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id',     v_existing.id,
        'status',         v_existing.status,
        'expires_at',     v_existing.expires_at,
        'amount_paise',   v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  v_base_amount := CASE WHEN p_duration_minutes = 60
                        THEN v_config.session_1hr_price_paise
                        ELSE v_config.session_2hr_price_paise END;

  IF p_coupon_code IS NOT NULL AND length(trim(p_coupon_code)) > 0 THEN
    v_normalized_code := upper(trim(p_coupon_code));

    SELECT * INTO v_coupon FROM coupons WHERE upper(code) = v_normalized_code FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'coupon_invalid_code'; END IF;
    IF NOT v_coupon.is_active THEN RAISE EXCEPTION 'coupon_inactive'; END IF;
    IF v_coupon.valid_from > now() THEN RAISE EXCEPTION 'coupon_not_yet_active'; END IF;
    IF v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < now() THEN
      RAISE EXCEPTION 'coupon_expired';
    END IF;
    IF v_coupon.max_uses IS NOT NULL AND v_coupon.uses_count >= v_coupon.max_uses THEN
      RAISE EXCEPTION 'coupon_exhausted';
    END IF;
    IF v_base_amount < v_coupon.min_order_paise THEN
      RAISE EXCEPTION 'coupon_min_order_not_met';
    END IF;

    SELECT COUNT(*) INTO v_family_uses
      FROM coupon_redemptions
      WHERE coupon_id = v_coupon.id AND family_id = p_family_id;
    IF v_family_uses >= v_coupon.max_per_family THEN
      RAISE EXCEPTION 'coupon_already_used_by_family';
    END IF;

    IF v_coupon.type = 'percent_off' THEN
      v_coupon_discount := (v_base_amount * v_coupon.value) / 100;
      IF v_coupon.max_discount_paise IS NOT NULL AND v_coupon_discount > v_coupon.max_discount_paise THEN
        v_coupon_discount := v_coupon.max_discount_paise;
      END IF;
    ELSIF v_coupon.type = 'flat_off' THEN
      v_coupon_discount := LEAST(v_coupon.value, v_base_amount);
    ELSIF v_coupon.type = 'free_session' THEN
      v_coupon_discount := v_base_amount;
    END IF;
  END IF;

  v_amount := v_base_amount - v_coupon_discount;

  v_use_hold := (p_payment_method = 'wallet' AND p_staff_pin_id IS NULL);
  v_pending_scan := (p_staff_pin_id IS NULL);

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;

    IF v_use_hold THEN
      IF (v_wallet.balance_paise - v_wallet.held_paise) < v_amount THEN
        RAISE EXCEPTION 'insufficient_balance';
      END IF;
      UPDATE wallets SET
        held_paise = held_paise + v_amount,
        updated_at = now()
      WHERE family_id = p_family_id;
    ELSE
      IF v_wallet.balance_paise < v_amount THEN RAISE EXCEPTION 'insufficient_balance'; END IF;
      UPDATE wallets SET
        balance_paise = balance_paise - v_amount, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;
      INSERT INTO wallet_transactions(
        family_id, type, amount_paise, balance_after_paise,
        payment_method, reference_type, idempotency_key
      ) VALUES (
        p_family_id, 'session_debit', -v_amount, v_wallet.balance_paise,
        'wallet', 'session', p_idempotency_key
      );
    END IF;
  END IF;

  IF v_pending_scan THEN
    v_status     := 'pending';
    v_started_at := now();
    v_expires_at := now() + (v_config.session_pre_scan_timeout_minutes || ' minutes')::INTERVAL
                          + (p_duration_minutes || ' minutes')::INTERVAL;
    v_grace_at   := v_expires_at + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL;
  ELSE
    v_status     := 'active';
    v_started_at := now();
    v_expires_at := now() + (p_duration_minutes || ' minutes')::INTERVAL;
    v_grace_at   := now() + ((p_duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL;
  END IF;

  INSERT INTO sessions(
    venue_id, family_id, child_id, staff_pin_id,
    duration_minutes, amount_paise, payment_method, status,
    started_at, expires_at, grace_force_close_at,
    is_guest, guest_phone, pre_booking_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method, v_status,
    v_started_at, v_expires_at, v_grace_at,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key
  ) RETURNING * INTO v_session;

  IF p_payment_method = 'wallet' AND NOT v_use_hold THEN
    UPDATE wallet_transactions SET reference_id = v_session.id
      WHERE family_id = p_family_id
        AND type = 'session_debit'
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  IF p_pre_booking_id IS NOT NULL THEN
    UPDATE session_pre_bookings SET
      status = 'redeemed', redeemed_session_id = v_session.id
    WHERE id = p_pre_booking_id AND status = 'reserved';
  END IF;

  IF v_coupon_discount > 0 THEN
    UPDATE coupons SET uses_count = uses_count + 1, updated_at = now()
      WHERE id = v_coupon.id;
    INSERT INTO coupon_redemptions(coupon_id, family_id, session_id, discount_paise)
      VALUES (v_coupon.id, p_family_id, v_session.id, v_coupon_discount)
      RETURNING id INTO v_redemption_id;
    UPDATE sessions SET coupon_redemption_id = v_redemption_id
      WHERE id = v_session.id;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.create', 'session', v_session.id, p_venue_id,
    jsonb_build_object(
      'child_id', p_child_id,
      'duration_minutes', p_duration_minutes,
      'base_amount_paise', v_base_amount,
      'coupon_discount_paise', v_coupon_discount,
      'amount_paise', v_amount,
      'coupon_code', CASE WHEN v_coupon_discount > 0 THEN v_coupon.code ELSE NULL END,
      'payment_method', p_payment_method,
      'status', v_status,
      'used_hold', v_use_hold,
      'pending_scan', v_pending_scan
    )
  );

  RETURN jsonb_build_object(
    'success',                true,
    'session_id',             v_session.id,
    'status',                 v_status,
    'expires_at',             v_session.expires_at,
    'grace_force_close_at',   v_session.grace_force_close_at,
    'amount_paise',           v_amount,
    'base_amount_paise',      v_base_amount,
    'coupon_discount_paise',  v_coupon_discount,
    'coupon_redemption_id',   v_redemption_id
  );
END $$;
