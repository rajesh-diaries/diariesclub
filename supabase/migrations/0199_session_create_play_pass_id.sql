-- ===========================================================================
-- Migration 0199 — Ensure session_create records play_pass_id
--
-- session_cancel_pending refunds passes by decrementing used_passes on
-- sessions.play_pass_id. The column exists, but the deployed session_create
-- function was not populating it, so play-pass sessions had a NULL link and
-- cancellation could not refund them.
--
-- This migration recreates session_create with play_pass_id included in the
-- sessions INSERT. It is identical to the current function except for that
-- column and the v_pass local variable.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.session_create(
  p_venue_id uuid,
  p_family_id uuid,
  p_child_id uuid,
  p_duration_minutes integer,
  p_payment_method text,
  p_staff_pin_id uuid DEFAULT NULL::uuid,
  p_is_guest boolean DEFAULT false,
  p_guest_phone text DEFAULT NULL::text,
  p_pre_booking_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text,
  p_coupon_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_session     sessions%ROWTYPE;
  v_existing    sessions%ROWTYPE;
  v_wallet      wallets%ROWTYPE;
  v_config      venue_config%ROWTYPE;
  v_amount      INTEGER;
  v_base_amount INTEGER;
  v_pending_scan BOOLEAN;
  v_status      TEXT;
  v_started_at  TIMESTAMPTZ;
  v_expires_at  TIMESTAMPTZ;
  v_grace_at    TIMESTAMPTZ;
  v_coupon      coupons%ROWTYPE;
  v_normalized_code TEXT;
  v_coupon_discount INTEGER := 0;
  v_family_uses INTEGER;
  v_pass        play_passes%ROWTYPE;
  v_family_deleted BOOLEAN;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_payment_method NOT IN ('wallet','cash','play_pass') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  SELECT (deleted_at IS NOT NULL) INTO v_family_deleted
    FROM families WHERE id = p_family_id;
  IF v_family_deleted IS TRUE THEN RAISE EXCEPTION 'family_deleted'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id', v_existing.id, 'status', v_existing.status,
        'expires_at', v_existing.expires_at, 'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  v_base_amount := CASE WHEN p_duration_minutes = 60
                        THEN v_config.session_1hr_price_paise
                        ELSE v_config.session_2hr_price_paise END;

  IF p_payment_method = 'play_pass' AND p_duration_minutes <> 60 THEN
    RAISE EXCEPTION 'play_pass_1hr_only';
  END IF;

  IF p_coupon_code IS NOT NULL AND length(trim(p_coupon_code)) > 0 THEN
    IF p_payment_method = 'play_pass' THEN
      RAISE EXCEPTION 'coupons_not_allowed_with_play_pass';
    END IF;

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
    SELECT COUNT(*) INTO v_family_uses FROM coupon_redemptions
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
  v_pending_scan := (p_staff_pin_id IS NULL);

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
    IF (v_wallet.balance_paise - v_wallet.held_paise) < v_amount THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_amount,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'session_debit', -v_amount, v_wallet.balance_paise,
      'wallet', 'session', p_idempotency_key
    );
  ELSIF p_payment_method = 'play_pass' THEN
    SELECT * INTO v_pass FROM play_passes
    WHERE family_id = p_family_id
      AND expires_at > now()
      AND used_passes < total_passes
    ORDER BY expires_at ASC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'no_active_play_pass'; END IF;

    UPDATE play_passes
    SET used_passes = used_passes + 1
    WHERE id = v_pass.id;
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
    is_guest, guest_phone, pre_booking_id, idempotency_key,
    play_pass_id
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method, v_status,
    v_started_at, v_expires_at, v_grace_at,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key,
    v_pass.id
  ) RETURNING * INTO v_session;

  IF p_payment_method = 'wallet' THEN
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

  IF p_coupon_code IS NOT NULL AND length(trim(p_coupon_code)) > 0 THEN
    INSERT INTO coupon_redemptions (
      coupon_id, family_id, session_id, discount_paise
    ) VALUES (
      v_coupon.id, p_family_id, v_session.id, v_coupon_discount
    );
    UPDATE coupons SET uses_count = uses_count + 1 WHERE id = v_coupon.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'status', v_session.status,
    'expires_at', v_session.expires_at,
    'amount_paise', v_session.amount_paise
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.session_create(uuid, uuid, uuid, integer, text, uuid, boolean, text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_create(uuid, uuid, uuid, integer, text, uuid, boolean, text, uuid, text, text) TO authenticated, service_role;
