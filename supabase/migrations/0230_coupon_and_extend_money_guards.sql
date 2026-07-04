-- 0230 — Coupon anti-forge + percent clamp; extend cash policy + held_paise
--
-- session_create:
--   (a) The sibling-coupon kid gate trusted the client-supplied p_kid_count
--       only, so a forged p_kid_count:5 unlocked a 5-kid coupon on a 1-kid
--       booking. Add a server-authoritative check: min_kids must not exceed
--       the family's real registered children count (can't be forged).
--   (b) percent_off had no lower clamp — a >100% coupon (admin misconfig with
--       no max_discount_paise) produced a discount > base → negative charge →
--       wallet CREDIT. Clamp discount to the base amount.
--
-- session_extend:
--   (c) Cash path did no debit and no pending/scan gate, so a parent could
--       self-extend for free ("Cash at desk"). Cash is a staff-collected
--       action — reject parent-initiated cash extends (wallet-only for
--       self-serve; staff_on_behalf cash still allowed at the desk).
--   (d) Wallet check ignored held_paise; align with session_create by checking
--       spendable (balance - held). Latent today (holds unused) but correct.
--
-- Both functions are otherwise reproduced verbatim from the live def.

CREATE OR REPLACE FUNCTION public.session_create(
  p_venue_id uuid, p_family_id uuid, p_child_id uuid, p_duration_minutes integer,
  p_payment_method text, p_staff_pin_id uuid DEFAULT NULL::uuid, p_is_guest boolean DEFAULT false,
  p_guest_phone text DEFAULT NULL::text, p_pre_booking_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text,
  p_batch_id uuid DEFAULT NULL::uuid, p_kid_count integer DEFAULT 1)
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
  v_family_kids INTEGER;
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
    -- Kid-count gate: a multi-kid coupon needs at least min_kids in the booking.
    IF v_coupon.min_kids > COALESCE(p_kid_count, 1) THEN
      RAISE EXCEPTION 'coupon_requires_more_kids'
        USING DETAIL = format('needs %s kids', v_coupon.min_kids);
    END IF;
    -- Server anti-forge: p_kid_count is client-supplied. Also require the
    -- family to actually have >= min_kids registered children, so a forged
    -- p_kid_count cannot unlock a sibling coupon on a solo booking.
    SELECT count(*) INTO v_family_kids
      FROM children WHERE family_id = p_family_id AND deleted_at IS NULL;
    IF v_coupon.min_kids > v_family_kids THEN
      RAISE EXCEPTION 'coupon_requires_more_kids'
        USING DETAIL = format('needs %s kids', v_coupon.min_kids);
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
      -- Never discount below a zero charge (guards a misconfigured >100% coupon).
      v_coupon_discount := LEAST(v_coupon_discount, v_base_amount);
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

CREATE OR REPLACE FUNCTION public.session_extend(
  p_session_id uuid, p_duration_minutes integer, p_payment_method text,
  p_initiated_by text DEFAULT 'parent'::text, p_staff_pin_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session   sessions%ROWTYPE;
  v_wallet    wallets%ROWTYPE;
  v_config    venue_config%ROWTYPE;
  v_amount    INTEGER;
  v_new_exp   TIMESTAMPTZ;
  v_existing  session_extensions%ROWTYPE;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_initiated_by NOT IN ('parent','staff_on_behalf') THEN RAISE EXCEPTION 'invalid_initiator'; END IF;

  -- Cash is a staff-collected action. A parent self-extending "cash at desk"
  -- got free play time (no debit, no scan gate). Route self-serve extends
  -- through the wallet; only staff can extend on cash (they collect it).
  IF p_payment_method = 'cash' AND p_initiated_by = 'parent' THEN
    RAISE EXCEPTION 'cash_extend_requires_staff';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM session_extensions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_expires_at', v_existing.new_expires_at,
        'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  SELECT (value->>'price_paise')::INTEGER INTO v_amount
    FROM jsonb_array_elements(v_config.session_extension_options)
   WHERE (value->>'minutes')::INTEGER = p_duration_minutes
   LIMIT 1;
  IF v_amount IS NULL OR v_amount <= 0 THEN RAISE EXCEPTION 'invalid_duration'; END IF;

  v_new_exp := v_session.expires_at + (p_duration_minutes || ' minutes')::INTERVAL;

  IF v_new_exp <= now() THEN
    RAISE EXCEPTION 'extension_too_short'
      USING DETAIL = format(
        'session already %s min past expiry; %s-min extension does not move expiry forward',
        EXTRACT(EPOCH FROM (now() - v_session.expires_at))::INTEGER / 60,
        p_duration_minutes
      );
  END IF;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = v_session.family_id FOR UPDATE;
    IF (v_wallet.balance_paise - v_wallet.held_paise) < v_amount THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET balance_paise = balance_paise - v_amount, updated_at = now()
      WHERE family_id = v_session.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_id, reference_type, idempotency_key
    ) VALUES (
      v_session.family_id, 'extension_debit', -v_amount, v_wallet.balance_paise,
      'wallet', p_session_id, 'session_extension', p_idempotency_key
    );
  END IF;

  UPDATE sessions SET
    expires_at = v_new_exp,
    grace_force_close_at = v_new_exp + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL,
    status = 'active',
    grace_started_at = NULL
  WHERE id = p_session_id;

  INSERT INTO session_extensions(
    session_id, duration_minutes, amount_paise, payment_method, new_expires_at,
    staff_pin_id, initiated_by, idempotency_key
  ) VALUES (
    p_session_id, p_duration_minutes, v_amount, p_payment_method, v_new_exp,
    p_staff_pin_id, p_initiated_by, p_idempotency_key
  );

  IF p_initiated_by = 'staff_on_behalf' THEN
    PERFORM public._send_notification(
      p_family_id    => v_session.family_id,
      p_type         => 'extend_nudge',
      p_args         => jsonb_build_object('duration_minutes', p_duration_minutes::text),
      p_reference_id => p_session_id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.extend', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('duration_minutes', p_duration_minutes, 'amount_paise', v_amount,
                       'initiated_by', p_initiated_by, 'new_expires_at', v_new_exp)
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_expires_at', v_new_exp,
    'amount_paise', v_amount
  );
END $function$;
