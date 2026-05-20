-- Block new workshop registrations more than 10 minutes after the
-- workshop's scheduled start time. Without this guard a customer could
-- still register for a session that's already underway (or finished),
-- giving an awkward in-app experience and a no-show on the staff side.
--
-- Behaviour change:
--   workshop_register raises 'workshop_registration_closed' once
--   now() > scheduled_at + 10 minutes. The exception rolls back the
--   spots_remaining decrement automatically, so capacity stays
--   accurate.
--
-- The client maps this exception to a friendly message and disables
-- the Register button when the same condition is true locally
-- (lib/features/club/workshop_detail_screen.dart).

CREATE OR REPLACE FUNCTION public.workshop_register(
  p_workshop_id uuid,
  p_family_id uuid,
  p_child_id uuid,
  p_payment_method text,
  p_idempotency_key text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_wshop workshops%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_existing workshop_registrations%ROWTYPE;
  v_reg workshop_registrations%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_pricing JSONB;
  v_subtotal INTEGER;
  v_gst INTEGER;
  v_child_name TEXT;
  v_scheduled_date TEXT;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash','razorpay') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM workshop_registrations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'registration_id', v_existing.id,
        'amount_paise', v_existing.amount_paise,
        'subtotal_paise', v_existing.subtotal_paise,
        'gst_paise', v_existing.gst_paise
      );
    END IF;
  END IF;

  UPDATE workshops SET spots_remaining = spots_remaining - 1
    WHERE id = p_workshop_id AND spots_remaining > 0 AND status = 'upcoming'
    RETURNING * INTO v_wshop;
  IF NOT FOUND THEN RAISE EXCEPTION 'workshop_full'; END IF;

  -- Time-based registration cutoff: 10 minutes after scheduled start.
  -- RAISE EXCEPTION rolls back the spots_remaining decrement above.
  IF v_wshop.scheduled_at IS NOT NULL
     AND now() > v_wshop.scheduled_at + INTERVAL '10 minutes' THEN
    RAISE EXCEPTION 'workshop_registration_closed';
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_wshop.venue_id;
  v_pricing  := compute_pricing(v_wshop.price_paise, v_config.gst_percent);
  v_subtotal := (v_pricing->>'subtotal_paise')::INTEGER;
  v_gst      := (v_pricing->>'gst_paise')::INTEGER;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_wshop.price_paise THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET balance_paise = balance_paise - v_wshop.price_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'workshop_debit', -v_wshop.price_paise, v_wallet.balance_paise, 'wallet',
      p_workshop_id, 'workshop', p_idempotency_key
    );
  END IF;

  INSERT INTO workshop_registrations(
    workshop_id, family_id, child_id, payment_method,
    amount_paise, subtotal_paise, gst_paise, idempotency_key
  ) VALUES (
    p_workshop_id, p_family_id, p_child_id, p_payment_method,
    v_wshop.price_paise, v_subtotal, v_gst, p_idempotency_key
  ) RETURNING * INTO v_reg;

  SELECT name INTO v_child_name FROM children WHERE id = p_child_id;
  v_scheduled_date := to_char(
    (v_wshop.scheduled_at AT TIME ZONE 'Asia/Kolkata'),
    'Dy DD Mon · HH12:MI AM'
  );
  BEGIN
    PERFORM public._send_notification(
      p_family_id    => p_family_id,
      p_type         => 'workshop_registered',
      p_args         => jsonb_build_object(
        'child_name',     COALESCE(v_child_name, 'your kid'),
        'title',          v_wshop.title,
        'scheduled_date', v_scheduled_date,
        'workshop_id',    p_workshop_id::text
      ),
      p_reference_id => v_reg.id
    );
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'workshop.register.notify_failed', 'workshop_registration', v_reg.id, v_wshop.venue_id,
            jsonb_build_object('error', SQLERRM));
  END;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'workshop.register', 'workshop_registration', v_reg.id,
          v_wshop.venue_id,
          jsonb_build_object('workshop_id', p_workshop_id,
                             'amount_paise', v_wshop.price_paise,
                             'subtotal_paise', v_subtotal,
                             'gst_paise', v_gst,
                             'payment_method', p_payment_method));

  RETURN jsonb_build_object(
    'success', true,
    'registration_id', v_reg.id,
    'amount_paise', v_wshop.price_paise,
    'subtotal_paise', v_subtotal,
    'gst_paise', v_gst
  );
END $function$;
