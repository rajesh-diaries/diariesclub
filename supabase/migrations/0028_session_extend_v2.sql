-- ===========================================================================
--  Migration 0028 — session_extend v2: JSONB-list pricing (BUG-017 fix)
--
--  Replaces the integer-division formula
--    v_amount := session_extension_per_hour_paise * (p_duration_minutes / 60)
--  which truncated 30/60 → 0 and raised 'invalid_duration' for any
--  duration < 60 minutes. The new body looks up p_duration_minutes in
--  venue_config.session_extension_options (added in 0027) and uses the
--  matching entry's explicit price_paise. Admin-editable, no formula.
--
--  Signature unchanged → no client breakage.
--
--  Reversibility: restore the body from 0003_rpc_functions.sql:401.
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION session_extend(
  p_session_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,
  p_initiated_by TEXT DEFAULT 'parent',
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  -- BUG-017 fix: look up the option in the JSONB list. NULL means the
  -- requested duration isn't enabled for this venue.
  SELECT (value->>'price_paise')::INTEGER
    INTO v_amount
    FROM jsonb_array_elements(v_config.session_extension_options)
   WHERE (value->>'minutes')::INTEGER = p_duration_minutes
   LIMIT 1;
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_duration';
  END IF;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = v_session.family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_amount THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

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

  v_new_exp := GREATEST(v_session.expires_at, now()) + (p_duration_minutes || ' minutes')::INTERVAL;

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
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'extend_nudge',
      'Session extended',
      'Staff extended your session by ' || p_duration_minutes || ' minutes.',
      '/home', p_session_id
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
END $$;

COMMIT;
