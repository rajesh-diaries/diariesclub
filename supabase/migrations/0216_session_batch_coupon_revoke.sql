-- Close the multi-kid coupon loophole: a group discount (e.g. 2KIDS) that is
-- applied to session 0 of a batch must be revoked if any sibling session in
-- the same batch is cancelled, otherwise a family can start N sessions, cancel
-- N-1, and keep the full group discount on a single leftover session.

-- 1) Batch linkage so cancel can see the whole group.
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS batch_id uuid;
CREATE INDEX IF NOT EXISTS idx_sessions_batch_id ON sessions(batch_id) WHERE batch_id IS NOT NULL;

-- 2) session_create: accept + persist p_batch_id. Drop old signature first so
--    the appended DEFAULT param does not create an ambiguous overload.
DROP FUNCTION IF EXISTS public.session_create(uuid,uuid,uuid,integer,text,uuid,boolean,text,uuid,text,text);

CREATE OR REPLACE FUNCTION public.session_create(
  p_venue_id uuid, p_family_id uuid, p_child_id uuid, p_duration_minutes integer,
  p_payment_method text, p_staff_pin_id uuid DEFAULT NULL::uuid, p_is_guest boolean DEFAULT false,
  p_guest_phone text DEFAULT NULL::text, p_pre_booking_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text,
  p_batch_id uuid DEFAULT NULL::uuid)
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
    play_pass_id, batch_id
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method, v_status,
    v_started_at, v_expires_at, v_grace_at,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key,
    v_pass.id, p_batch_id
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

-- 3) session_cancel_pending: revoke a group coupon when a sibling is cancelled.
CREATE OR REPLACE FUNCTION public.session_cancel_pending(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session      sessions%ROWTYPE;
  v_actor        TEXT;
  v_actor_id     UUID;
  v_wallet       wallets%ROWTYPE;
  v_redemption   coupon_redemptions%ROWTYPE;
  v_disc_session sessions%ROWTYPE;
  v_discount     INTEGER := 0;
  v_coupon_reversed BOOLEAN := false;
BEGIN
  SELECT * INTO v_session FROM sessions
   WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.status != 'pending' THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', v_session.id, 'status', v_session.status
    );
  END IF;

  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, NULL);
    v_actor    := 'customer';
    v_actor_id := v_session.family_id;
  ELSE
    v_actor    := 'system';
    v_actor_id := NULL;
  END IF;

  -- Refund wallet balance for direct session_create flows.
  IF v_session.payment_method = 'wallet'
     AND v_session.paid_via_order_id IS NULL THEN
    UPDATE wallets
       SET balance_paise = balance_paise + v_session.amount_paise,
           updated_at = now()
     WHERE family_id = v_session.family_id
     RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_type, reference_id
    ) VALUES (
      v_session.family_id, 'refund', v_session.amount_paise,
      v_wallet.balance_paise, 'wallet', 'session', v_session.id
    );
  END IF;

  -- Refund Play Pass if one was consumed for this session.
  IF v_session.payment_method = 'play_pass'
     AND v_session.play_pass_id IS NOT NULL THEN
    UPDATE play_passes
       SET used_passes = GREATEST(used_passes - 1, 0)
     WHERE id = v_session.play_pass_id;
  END IF;

  -- Coupon handling.
  SELECT * INTO v_redemption FROM coupon_redemptions WHERE session_id = p_session_id;
  IF FOUND THEN
    -- Case 1: cancelling the discounted session itself. Its own (discounted)
    -- amount was just refunded; simply release the coupon so it can be reused.
    -- Any remaining sibling sessions were always full price, so nothing to claw back.
    DELETE FROM coupon_redemptions WHERE id = v_redemption.id;
    UPDATE coupons SET uses_count = GREATEST(uses_count - 1, 0) WHERE id = v_redemption.coupon_id;
    v_coupon_reversed := true;
  ELSIF v_session.batch_id IS NOT NULL THEN
    -- Case 2: cancelling a full-price sibling out of a discounted group. The
    -- group condition (all kids play) is now broken, so revoke the discount:
    -- charge the still-live discounted session back to full price and free the coupon.
    SELECT r.* INTO v_redemption
      FROM coupon_redemptions r
      JOIN sessions s ON s.id = r.session_id
     WHERE s.batch_id = v_session.batch_id
       AND s.id <> p_session_id
       AND s.status IN ('pending','active')
     LIMIT 1;
    IF FOUND THEN
      v_discount := v_redemption.discount_paise;
      SELECT * INTO v_disc_session FROM sessions WHERE id = v_redemption.session_id FOR UPDATE;

      IF v_disc_session.payment_method = 'wallet'
         AND v_disc_session.paid_via_order_id IS NULL THEN
        UPDATE wallets
           SET balance_paise = balance_paise - v_discount,
               updated_at = now()
         WHERE family_id = v_disc_session.family_id
         RETURNING * INTO v_wallet;

        INSERT INTO wallet_transactions(
          family_id, type, amount_paise, balance_after_paise,
          payment_method, reference_type, reference_id
        ) VALUES (
          v_disc_session.family_id, 'session_debit', -v_discount,
          v_wallet.balance_paise, 'wallet', 'session', v_disc_session.id
        );
      END IF;

      -- Restore the discounted session to full price (cash flows collect the
      -- difference at the desk; wallet flows were just debited above).
      UPDATE sessions
         SET amount_paise = amount_paise + v_discount
       WHERE id = v_disc_session.id;

      DELETE FROM coupon_redemptions WHERE id = v_redemption.id;
      UPDATE coupons SET uses_count = GREATEST(uses_count - 1, 0) WHERE id = v_redemption.coupon_id;
      v_coupon_reversed := true;
    END IF;
  END IF;

  UPDATE sessions
     SET status = 'cancelled_pre_scan',
         completed_at = now()
   WHERE id = p_session_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_actor_id, v_actor,
    'session.cancel_pending', 'session', v_session.id, v_session.venue_id,
    jsonb_build_object(
      'amount_released_paise', CASE
        WHEN v_session.paid_via_order_id IS NULL THEN v_session.amount_paise
        ELSE 0
      END,
      'payment_method', v_session.payment_method,
      'paid_via_order_id', v_session.paid_via_order_id,
      'play_pass_refunded', v_session.payment_method = 'play_pass',
      'coupon_reversed', v_coupon_reversed,
      'coupon_discount_reclaimed_paise', v_discount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'status', 'cancelled_pre_scan',
    'amount_released_paise', CASE
      WHEN v_session.paid_via_order_id IS NULL THEN v_session.amount_paise
      ELSE 0
    END,
    'coupon_reversed', v_coupon_reversed
  );
END $function$;
