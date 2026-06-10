-- Play Pass membership system
-- Parents buy bulk session credits upfront at a discount

CREATE TABLE public.play_passes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  total_passes int NOT NULL CHECK (total_passes > 0),
  used_passes int NOT NULL DEFAULT 0 CHECK (used_passes >= 0),
  expires_at timestamptz NOT NULL,
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_play_passes_family ON public.play_passes(family_id);
CREATE INDEX idx_play_passes_active ON public.play_passes(family_id, expires_at)
  WHERE used_passes < total_passes AND expires_at > now();

-- RLS: families can only see their own passes
ALTER TABLE public.play_passes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "play_passes_family_select"
  ON public.play_passes
  FOR SELECT TO authenticated
  USING (family_id = auth.uid());

CREATE POLICY "play_passes_family_insert"
  ON public.play_passes
  FOR INSERT TO authenticated
  WITH CHECK (family_id = auth.uid());

CREATE POLICY "play_passes_family_update"
  ON public.play_passes
  FOR UPDATE TO authenticated
  USING (family_id = auth.uid())
  WITH CHECK (family_id = auth.uid());

-- ===========================================================================
-- play_pass_purchase(p_family_id, p_pass_type, p_idempotency_key)
--   Atomically deducts wallet balance and creates a play pass.
--   Idempotent on p_idempotency_key.
--   pass_type: '5' | '10' | '15'
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
BEGIN
  IF p_family_id IS NULL THEN RAISE EXCEPTION 'family_id_required'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF auth.uid() <> p_family_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  -- Idempotency: return existing pass if same key was used before.
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

  -- Check wallet balance.
  SELECT COALESCE(SUM(amount_paise), 0) INTO v_balance
  FROM wallet_transactions
  WHERE family_id = p_family_id;

  IF v_balance < v_price_paise THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
  END IF;

  -- Deduct from wallet.
  INSERT INTO wallet_transactions (family_id, amount_paise, type, description)
  VALUES (p_family_id, -v_price_paise, 'play_pass_purchase',
          'Play Pass ' || v_total || '-pack');

  -- Create the pass.
  INSERT INTO play_passes (family_id, total_passes, used_passes, expires_at, idempotency_key)
  VALUES (p_family_id, v_total, 0, now() + (v_days || ' days')::interval, p_idempotency_key)
  RETURNING id INTO v_pass_id;

  RETURN jsonb_build_object(
    'success', true,
    'pass_id', v_pass_id,
    'total_passes', v_total,
    'used_passes', 0,
    'expires_at', now() + (v_days || ' days')::interval,
    'new_balance_paise', v_balance - v_price_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.play_pass_purchase(uuid, text, text) TO authenticated;

-- ===========================================================================
-- play_pass_redeem(p_pass_id, p_family_id)
--   Atomically increments used_passes by 1.
--   Returns {success, remaining} or raises if expired/used up.
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
