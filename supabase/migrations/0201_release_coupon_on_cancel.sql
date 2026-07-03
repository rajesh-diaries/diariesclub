-- ===========================================================================
-- Migration 0201 — Release coupon redemption when a session is cancelled
--
-- session_create records a coupon_redemptions row when a coupon is used.
-- If the parent cancels the session before scanning, the coupon should be
-- reusable (just like wallet/Play Pass are refunded). This migration adds
-- a DELETE for that session's coupon redemption inside session_cancel_pending.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.session_cancel_pending(
  p_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_actor   TEXT;
  v_actor_id UUID;
  v_wallet  wallets%ROWTYPE;
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

  -- Release any coupon redemption tied to this session so the family can
  -- use the coupon again.
  DELETE FROM coupon_redemptions WHERE session_id = p_session_id;

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
      'play_pass_refunded', v_session.payment_method = 'play_pass'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'status', 'cancelled_pre_scan',
    'amount_released_paise', CASE
      WHEN v_session.paid_via_order_id IS NULL THEN v_session.amount_paise
      ELSE 0
    END
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.session_cancel_pending(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.session_cancel_pending(UUID) TO authenticated, service_role;
