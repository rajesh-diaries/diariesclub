-- 0228 — Wallet top-up double-credit (P0) + refund over-refund cap
--
-- P0 (CRITICAL, live customer path): a customer can replay their own valid
-- razorpay-topup `confirm` to credit the wallet N times for one payment.
-- The confirm signature HMAC(order_id|payment_id) is stable/replayable, the
-- client controls `idempotency_key` (null when omitted), and wallet_topup
-- dedups on idempotency_key ONLY — `wallet_transactions.razorpay_payment_id`
-- has only a NON-unique partial index. So null/varying keys → N credits.
--
-- Fix: wallet_topup also returns idempotent when a txn already exists for the
-- same razorpay_payment_id, and a partial UNIQUE index on razorpay_payment_id
-- makes a concurrent double physically impossible (DB backstop). A razorpay
-- payment id is captured once, so it is the true idempotency key here.
--
-- Also (HIGH, staff-gated): refund_issue never checked the original charge or
-- prior refunds, so repeat/over-refund could exceed what was paid. Add an
-- aggregate cap for session/order references.

-- --- DB backstop: one wallet credit per razorpay payment ------------------
-- Safe to add: prod has zero duplicate razorpay_payment_id rows (verified).
CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_razorpay_payment_id_key
  ON public.wallet_transactions (razorpay_payment_id)
  WHERE razorpay_payment_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.wallet_topup(
  p_family_id uuid, p_amount_paise integer, p_bonus_paise integer DEFAULT 0,
  p_razorpay_payment_id text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_wallet wallets%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_bonus_paise  <  0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  -- Dedup on the client-supplied idempotency key (if any).
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions
      WHERE idempotency_key = p_idempotency_key LIMIT 1;
    IF FOUND THEN
      SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id;
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_balance_paise', v_wallet.balance_paise
      );
    END IF;
  END IF;

  -- Dedup on the razorpay payment id — the true, non-forgeable idempotency
  -- key for a captured payment. This is what closes the confirm-replay mint:
  -- a replay carries the same payment id, so the second call returns here
  -- instead of crediting again, regardless of the client key.
  IF p_razorpay_payment_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions
      WHERE razorpay_payment_id = p_razorpay_payment_id LIMIT 1;
    IF FOUND THEN
      SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id;
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_balance_paise', v_wallet.balance_paise
      );
    END IF;
  END IF;

  INSERT INTO wallets (family_id) VALUES (p_family_id)
    ON CONFLICT (family_id) DO NOTHING;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;

  UPDATE wallets SET
    balance_paise = balance_paise + p_amount_paise + p_bonus_paise,
    updated_at = now()
  WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise,
    payment_method, razorpay_payment_id, idempotency_key
  ) VALUES (
    p_family_id, 'topup', p_amount_paise,
    v_wallet.balance_paise - p_bonus_paise,
    'razorpay', p_razorpay_payment_id, p_idempotency_key
  );

  IF p_bonus_paise > 0 THEN
    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method
    ) VALUES (
      p_family_id, 'bonus', p_bonus_paise, v_wallet.balance_paise, 'system'
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (NULL, 'system', 'wallet.topup', 'family', p_family_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'bonus_paise', p_bonus_paise,
                             'razorpay_payment_id', p_razorpay_payment_id));

  RETURN jsonb_build_object(
    'success', true,
    'new_balance_paise', v_wallet.balance_paise,
    'amount_credited',  p_amount_paise + p_bonus_paise
  );
END $function$;

-- --- Refund cap: never refund more than was charged -----------------------
CREATE OR REPLACE FUNCTION public.refund_issue(
  p_family_id uuid, p_reference_id uuid, p_reference_type text, p_amount_paise integer,
  p_destination text, p_reason text, p_staff_pin_id uuid, p_venue_id uuid,
  p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_existing refunds%ROWTYPE;
  v_refund refunds%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_auto_approve BOOLEAN;
  v_wallet wallets%ROWTYPE;
  v_original INTEGER;
  v_already  INTEGER;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_reference_type NOT IN ('session','order','workshop','birthday','manual') THEN
    RAISE EXCEPTION 'invalid_reference_type';
  END IF;
  IF p_destination NOT IN ('wallet','razorpay') THEN RAISE EXCEPTION 'invalid_destination'; END IF;

  IF NOT EXISTS(SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM refunds WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'refund_id', v_existing.id, 'status', v_existing.status
      );
    END IF;
  END IF;

  -- Cap total refunds at the original charge so repeat/over-refund can't
  -- exceed what was paid (the source amount is server-authoritative).
  IF p_reference_type = 'session' THEN
    SELECT amount_paise INTO v_original FROM sessions WHERE id = p_reference_id;
  ELSIF p_reference_type = 'order' THEN
    SELECT total_paise INTO v_original FROM orders WHERE id = p_reference_id;
  ELSE
    v_original := NULL;  -- workshop/birthday/manual: no single canonical source here
  END IF;

  IF v_original IS NOT NULL THEN
    SELECT COALESCE(SUM(amount_paise), 0) INTO v_already FROM refunds
      WHERE reference_id = p_reference_id
        AND reference_type = p_reference_type
        AND status IN ('pending','approved','completed');
    IF (v_already + p_amount_paise) > v_original THEN
      RAISE EXCEPTION 'refund_exceeds_charge'
        USING DETAIL = format('original=%s already=%s requested=%s',
                              v_original, v_already, p_amount_paise);
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_auto_approve := (p_amount_paise <= v_config.staff_refund_cap_paise);

  INSERT INTO refunds(
    family_id, reference_id, reference_type, amount_paise, destination,
    initiated_by, staff_pin_id, status, reason, approved_by, approved_at, idempotency_key
  ) VALUES (
    p_family_id, p_reference_id, p_reference_type, p_amount_paise, p_destination,
    'staff', p_staff_pin_id,
    CASE WHEN v_auto_approve THEN 'approved' ELSE 'pending' END,
    p_reason,
    CASE WHEN v_auto_approve THEN p_staff_pin_id ELSE NULL END,
    CASE WHEN v_auto_approve THEN now() ELSE NULL END,
    p_idempotency_key
  ) RETURNING * INTO v_refund;

  IF v_auto_approve AND p_destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + p_amount_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'refund', p_amount_paise, v_wallet.balance_paise, 'system',
      v_refund.id, 'refund', p_idempotency_key
    );

    UPDATE refunds SET status = 'completed' WHERE id = v_refund.id;

    PERFORM public._send_notification(
      p_family_id, 'refund_processed',
      jsonb_build_object('amount_rupees', (p_amount_paise / 100)::TEXT),
      NULL, v_refund.id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'refund.issue', 'refund', v_refund.id, p_venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'destination', p_destination,
                             'auto_approved', v_auto_approve, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true, 'refund_id', v_refund.id,
    'status', CASE WHEN v_auto_approve AND p_destination = 'wallet' THEN 'completed'
                   WHEN v_auto_approve THEN 'approved' ELSE 'pending' END,
    'auto_approved', v_auto_approve
  );
END $function$;
