-- Fix play_pass_purchase so it actually deducts from wallets.balance_paise
-- instead of only inserting a wallet_transactions row.
--
-- The old implementation computed balance by SUM(wallet_transactions.amount_paise)
-- and never updated the wallets table. After switching the app to read
-- wallets.balance_paise directly, purchases looked like they were not deducted.
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
  v_wallet wallets%ROWTYPE;
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

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;

  IF (v_wallet.balance_paise - v_wallet.held_paise) < v_price_paise THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
  END IF;

  -- Create the pass first so we can reference it in the transaction.
  INSERT INTO play_passes (family_id, total_passes, used_passes, expires_at, idempotency_key)
  VALUES (p_family_id, v_total, 0, now() + (v_days || ' days')::interval, p_idempotency_key)
  RETURNING id INTO v_pass_id;

  -- Deduct from the actual wallet balance.
  UPDATE wallets
  SET balance_paise = balance_paise - v_price_paise,
      updated_at = now()
  WHERE family_id = p_family_id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    family_id, type, amount_paise, balance_after_paise,
    payment_method, reference_type, reference_id, idempotency_key
  ) VALUES (
    p_family_id, 'play_pass_purchase', -v_price_paise, v_wallet.balance_paise,
    'wallet', 'play_pass', v_pass_id, p_idempotency_key
  );

  RETURN jsonb_build_object(
    'success', true,
    'pass_id', v_pass_id,
    'total_passes', v_total,
    'used_passes', 0,
    'expires_at', now() + (v_days || ' days')::interval,
    'new_balance_paise', v_wallet.balance_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) TO authenticated;
