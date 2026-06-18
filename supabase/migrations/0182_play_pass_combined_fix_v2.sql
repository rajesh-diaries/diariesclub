-- Combined fix: play_passes table + wallet enum + fixed functions + 1hr restriction
-- Run this in Supabase Dashboard SQL Editor

-- ===========================================================================
-- 1. Play Passes table
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.play_passes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  total_passes int NOT NULL CHECK (total_passes > 0),
  used_passes int NOT NULL DEFAULT 0 CHECK (used_passes >= 0),
  expires_at timestamptz NOT NULL,
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_play_passes_family ON public.play_passes(family_id);
CREATE INDEX IF NOT EXISTS idx_play_passes_active ON public.play_passes(family_id, expires_at)
  WHERE used_passes < total_passes;

ALTER TABLE public.play_passes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'play_passes'
      AND policyname = 'play_passes_family_select'
  ) THEN
    CREATE POLICY "play_passes_family_select"
      ON public.play_passes
      FOR SELECT TO authenticated
      USING (family_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'play_passes'
      AND policyname = 'play_passes_family_insert'
  ) THEN
    CREATE POLICY "play_passes_family_insert"
      ON public.play_passes
      FOR INSERT TO authenticated
      WITH CHECK (family_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'play_passes'
      AND policyname = 'play_passes_family_update'
  ) THEN
    CREATE POLICY "play_passes_family_update"
      ON public.play_passes
      FOR UPDATE TO authenticated
      USING (family_id = auth.uid())
      WITH CHECK (family_id = auth.uid());
  END IF;
END $$;

-- ===========================================================================
-- 2. Safari Club notice banner config
-- ===========================================================================
ALTER TABLE public.venue_config
ADD COLUMN IF NOT EXISTS safari_notice_title TEXT,
ADD COLUMN IF NOT EXISTS safari_notice_body TEXT,
ADD COLUMN IF NOT EXISTS safari_notice_enabled BOOLEAN NOT NULL DEFAULT FALSE;

-- ===========================================================================
-- 3. Widen wallet_transactions.type enum
-- ===========================================================================
DO $$
BEGIN
  ALTER TABLE public.wallet_transactions
    DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

  ALTER TABLE public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN (
      'topup','bonus','session_debit','extension_debit',
      'order_debit','workshop_debit','birthday_deposit_debit','birthday_balance_debit',
      'refund','coins_credit','coins_debit',
      'reactivation_credit','visit_bonus','streak_milestone',
      'manual_credit','manual_debit','play_pass_purchase'
    ));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not alter wallet_transactions.type check: %', SQLERRM;
END $$;

-- ===========================================================================
-- 4. Fixed play_pass_purchase function
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.play_pass_purchase(
  p_family_id uuid,
  p_pass_type text,
  p_idempotency_key text DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_total int;
  v_days int;
  v_price_paise int;
  v_pass_id uuid;
  v_existing play_passes%ROWTYPE;
  v_balance int;
  v_new_balance int;
BEGIN
  IF p_family_id IS NULL THEN RAISE EXCEPTION 'family_id_required'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF auth.uid() <> p_family_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM play_passes
    WHERE idempotency_key = p_idempotency_key AND family_id = p_family_id;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'pass_id', v_existing.id,
        'total_passes', v_existing.total_passes,
        'used_passes', v_existing.used_passes,
        'expires_at', v_existing.expires_at,
        'idempotent', true
      );
    END IF;
  END IF;

  CASE p_pass_type
    WHEN '5'  THEN v_total := 5;  v_days := 30; v_price_paise := 350000;
    WHEN '10' THEN v_total := 10; v_days := 45; v_price_paise := 650000;
    WHEN '15' THEN v_total := 15; v_days := 60; v_price_paise := 900000;
    ELSE RAISE EXCEPTION 'invalid_pass_type';
  END CASE;

  SELECT COALESCE(SUM(amount_paise), 0) INTO v_balance
  FROM wallet_transactions
  WHERE family_id = p_family_id;

  IF v_balance < v_price_paise THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
  END IF;

  v_new_balance := v_balance - v_price_paise;

  INSERT INTO wallet_transactions (
    family_id, type, amount_paise, balance_after_paise,
    payment_method, reference_type, idempotency_key
  ) VALUES (
    p_family_id, 'play_pass_purchase', -v_price_paise, v_new_balance,
    'wallet', 'play_pass', p_idempotency_key
  );

  INSERT INTO play_passes (family_id, total_passes, used_passes, expires_at, idempotency_key)
  VALUES (p_family_id, v_total, 0, now() + (v_days || ' days')::interval, p_idempotency_key)
  RETURNING id INTO v_pass_id;

  RETURN jsonb_build_object(
    'success', true,
    'pass_id', v_pass_id,
    'total_passes', v_total,
    'used_passes', 0,
    'expires_at', now() + (v_days || ' days')::interval,
    'new_balance_paise', v_new_balance
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) TO authenticated;

-- ===========================================================================
-- 5. play_pass_redeem function
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.play_pass_redeem(
  p_pass_id uuid,
  p_family_id uuid
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pass play_passes%ROWTYPE;
  v_remaining int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF auth.uid() <> p_family_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_pass FROM play_passes
  WHERE id = p_pass_id AND family_id = p_family_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'pass_not_found'; END IF;
  IF v_pass.expires_at < now() THEN RAISE EXCEPTION 'pass_expired'; END IF;
  IF v_pass.used_passes >= v_pass.total_passes THEN RAISE EXCEPTION 'pass_exhausted'; END IF;

  UPDATE play_passes
  SET used_passes = used_passes + 1
  WHERE id = p_pass_id;

  v_remaining := v_pass.total_passes - v_pass.used_passes - 1;

  RETURN jsonb_build_object(
    'success', true,
    'remaining', v_remaining,
    'total', v_pass.total_passes,
    'used', v_pass.used_passes + 1
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.play_pass_redeem(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.play_pass_redeem(uuid, uuid) TO authenticated;

-- ===========================================================================
-- 6. session_create with play_pass support + 1-hour-only restriction
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

  -- Play Pass is 1-hour only.
  IF p_payment_method = 'play_pass' AND p_duration_minutes <> 60 THEN
    RAISE EXCEPTION 'play_pass_1hr_only';
  END IF;

  -- Coupon validation — play_pass does NOT allow coupons.
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
    is_guest, guest_phone, pre_booking_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method, v_status,
    v_started_at, v_expires_at, v_grace_at,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key
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

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'status', v_session.status,
    'expires_at', v_session.expires_at,
    'amount_paise', v_session.amount_paise
  );
END;
$function$;
