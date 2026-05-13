-- 0140 — fix combo-with-session double-charge (BUG-050).
--
-- BUG: combo_purchase_sheet used to call session_create THEN order_place
-- for combos that bundled a play session. session_create added the
-- session price to wallet.held_paise; order_place independently debited
-- the FULL combo price (food + session value) from wallet.balance_paise.
-- When staff later scanned the QR, qr_scan_validate converted the hold
-- to a second balance debit — the customer paid the session price twice.
--
-- FIX: stop calling session_create from the customer side. order_place
-- now atomically creates the session row when a combo line has
-- session_minutes, linked back to the order via sessions.paid_via_order_id.
--
-- qr_scan_validate and session_cancel_pending check paid_via_order_id and
-- skip the wallet held→debit / hold-release paths — the money has already
-- moved through order_place, so the session "scan" is just a status flip
-- from pending → active. amount_paise on the session row is kept at the
-- session's GST-inclusive price for accounting / UI display, but is no
-- longer used as the basis for any wallet movement at scan time.
--
-- Reversibility:
--   ALTER TABLE sessions DROP COLUMN IF EXISTS paid_via_order_id;
--   DROP FUNCTION IF EXISTS public.order_place(
--     uuid, uuid, jsonb, text, text, uuid, uuid, uuid, text, text);
--   (then restore the 0102 signature)

BEGIN;

-- 1. New nullable link from session → order. NULL for direct session_create
--    flows (the usual path); non-NULL only when order_place created the
--    session as part of a combo purchase.
ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS paid_via_order_id UUID
  REFERENCES orders(id) ON DELETE SET NULL;

COMMENT ON COLUMN sessions.paid_via_order_id IS
  'When non-NULL, this session was created by order_place as part of a combo. '
  'qr_scan_validate and session_cancel_pending skip wallet movement for these '
  'sessions — order_place already charged the customer; the session row is '
  'just for QR-scan lifecycle tracking.';

-- 2. order_place v2 — accept p_child_id and emit a session row for any
--    combo line that has session_minutes.
DROP FUNCTION IF EXISTS public.order_place(
  uuid, uuid, jsonb, text, text, uuid, uuid, text, text
);

CREATE OR REPLACE FUNCTION public.order_place(
  p_venue_id UUID,
  p_family_id UUID,
  p_items JSONB,
  p_fulfillment_mode TEXT,
  p_payment_method TEXT,
  p_combo_id UUID DEFAULT NULL,
  p_staff_pin_id UUID DEFAULT NULL,
  p_child_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL,
  p_customer_gstin TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order      orders%ROWTYPE;
  v_existing   orders%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_invoice    TEXT;

  v_food_taxable   INTEGER := 0;
  v_session_value  INTEGER := 0;

  v_food_gst       INTEGER;
  v_session_taxable INTEGER;
  v_session_gst    INTEGER;
  v_grand_total_raw INTEGER;
  v_grand_total    INTEGER;
  v_rounding       INTEGER;

  v_coins      INTEGER := 0;
  v_item       JSONB;
  v_type       TEXT;
  v_qty        INTEGER;
  v_menu_item  menu_items%ROWTYPE;
  v_combo      combos%ROWTYPE;
  v_combo_session_minutes INTEGER;
  v_session_price INTEGER;
  v_combo_food_portion INTEGER;
  v_fit_priced JSONB;
  v_fit_id     UUID;
  v_brand      TEXT;
  v_unit_price INTEGER;

  -- Tracking for combo-with-session emission. We emit at most one
  -- session per order_place call: the first combo with session_minutes
  -- defines the session minutes. If the cart has multiple combos with
  -- session_minutes for the same child, that's a UX problem the client
  -- should prevent (you can't be playing two sessions at once).
  v_combo_session_required_minutes INTEGER := NULL;
  v_session_row sessions%ROWTYPE;
  v_session_expires_at TIMESTAMPTZ;
  v_session_grace_at   TIMESTAMPTZ;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash','razorpay') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_fulfillment_mode NOT IN ('dine_in','takeaway','table_service') THEN RAISE EXCEPTION 'invalid_fulfillment_mode'; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'invalid_items';
  END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM orders WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'order_id', v_existing.id,
        'total_paise', v_existing.total_paise,
        'invoice_number', v_existing.invoice_number
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_type := COALESCE(v_item->>'type', 'menu_item');
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

    IF v_type = 'menu_item' THEN
      SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
      IF NOT FOUND OR NOT v_menu_item.is_available
         OR NOT COALESCE(v_menu_item.is_published, TRUE) THEN
        RAISE EXCEPTION 'menu_item_unavailable';
      END IF;
      v_food_taxable := v_food_taxable + (v_menu_item.price_paise * v_qty);
    ELSIF v_type = 'combo' THEN
      SELECT * INTO v_combo FROM combos
        WHERE id = (v_item->>'combo_id')::UUID
          AND venue_id = p_venue_id AND is_active;
      IF NOT FOUND THEN RAISE EXCEPTION 'invalid_combo'; END IF;

      v_combo_session_minutes := (v_combo.inclusions->>'session_minutes')::INTEGER;
      v_session_price := CASE
        WHEN v_combo_session_minutes = 60  THEN v_config.session_1hr_price_paise
        WHEN v_combo_session_minutes = 120 THEN v_config.session_2hr_price_paise
        ELSE 0
      END;
      v_combo_food_portion := GREATEST(0, v_combo.price_paise - v_session_price);

      v_session_value := v_session_value + (v_session_price * v_qty);
      v_food_taxable  := v_food_taxable  + (v_combo_food_portion * v_qty);

      -- If this combo carries a session, remember the minutes — we'll
      -- emit one sessions row at the end of this transaction, linked
      -- back via paid_via_order_id. p_child_id is required.
      IF v_combo_session_minutes IS NOT NULL AND v_combo_session_minutes > 0 THEN
        IF p_child_id IS NULL THEN
          RAISE EXCEPTION 'combo_requires_child';
        END IF;
        IF v_combo_session_required_minutes IS NULL THEN
          v_combo_session_required_minutes := v_combo_session_minutes;
        END IF;
        -- Multiple session-bearing combos in one cart isn't supported
        -- — would create overlapping sessions for the same kid. The
        -- client gates this; raise here as a safety net.
        IF v_combo_session_required_minutes IS NOT NULL
           AND v_qty > 1 THEN
          RAISE EXCEPTION 'multiple_sessions_in_cart';
        END IF;
      END IF;
    ELSIF v_type = 'fit_meal' THEN
      v_fit_priced := _fit_validate_and_price(
        (v_item->>'template_id')::UUID,
        v_item->'selections'
      );
      v_unit_price := (v_fit_priced->>'final_price_paise')::INTEGER;
      v_food_taxable := v_food_taxable + (v_unit_price * v_qty);
    ELSE
      RAISE EXCEPTION 'invalid_line_type: %', v_type;
    END IF;
  END LOOP;

  -- Verify the child belongs to the family before we trust p_child_id.
  IF v_combo_session_required_minutes IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM children
       WHERE id = p_child_id AND family_id = p_family_id
    ) THEN
      RAISE EXCEPTION 'child_not_in_family';
    END IF;
  END IF;

  v_food_gst        := ROUND(v_food_taxable * COALESCE(v_config.food_gst_percent, 5)::NUMERIC / 100)::INTEGER;
  v_session_taxable := CASE WHEN v_session_value > 0
    THEN ROUND(v_session_value * 100::NUMERIC / (100 + COALESCE(v_config.gst_percent, 18)))::INTEGER
    ELSE 0 END;
  v_session_gst     := v_session_value - v_session_taxable;

  v_grand_total_raw := v_food_taxable + v_food_gst + v_session_value;
  v_grand_total     := (ROUND(v_grand_total_raw::NUMERIC / 100) * 100)::INTEGER;
  v_rounding        := v_grand_total - v_grand_total_raw;

  v_coins := (v_food_taxable * v_config.cashback_percent / 100 / 100)::INTEGER;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_grand_total THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_grand_total,
      coins_balance = coins_balance + v_coins,
      coins_lifetime = coins_lifetime + v_coins,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      coins_amount, payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'order_debit', -v_grand_total, v_wallet.balance_paise,
      0, 'wallet', 'order', p_idempotency_key
    );
    IF v_coins > 0 THEN
      INSERT INTO wallet_transactions(
        family_id, type, amount_paise, balance_after_paise,
        coins_amount, payment_method, reference_type
      ) VALUES (
        p_family_id, 'coins_credit', 0, v_wallet.balance_paise,
        v_coins, 'system', 'order'
      );
    END IF;
  END IF;

  v_invoice := _next_invoice_number();

  INSERT INTO orders(
    venue_id, family_id, staff_pin_id, fulfillment_mode, payment_method,
    subtotal_paise, gst_paise, combo_discount_paise, total_paise,
    food_taxable_paise, food_gst_paise,
    session_value_paise, session_taxable_paise, session_gst_paise,
    rounding_paise, invoice_number, customer_gstin,
    coins_earned, combo_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_staff_pin_id, p_fulfillment_mode, p_payment_method,
    v_food_taxable + v_session_taxable, v_food_gst + v_session_gst, 0, v_grand_total,
    v_food_taxable, v_food_gst,
    v_session_value, v_session_taxable, v_session_gst,
    v_rounding, v_invoice, p_customer_gstin,
    v_coins, NULL, p_idempotency_key
  ) RETURNING * INTO v_order;

  -- Emit the session row for combo-with-session. Wait-for-scan model
  -- mirrors session_create but with NO wallet movement (paid_via_order_id
  -- signals "already charged via order_place").
  IF v_combo_session_required_minutes IS NOT NULL THEN
    v_session_expires_at := now()
      + (v_config.session_pre_scan_timeout_minutes || ' minutes')::INTERVAL
      + (v_combo_session_required_minutes || ' minutes')::INTERVAL;
    v_session_grace_at := v_session_expires_at
      + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL;

    INSERT INTO sessions(
      venue_id, family_id, child_id,
      duration_minutes, amount_paise, payment_method, status,
      started_at, expires_at, grace_force_close_at,
      paid_via_order_id, idempotency_key
    ) VALUES (
      p_venue_id, p_family_id, p_child_id,
      v_combo_session_required_minutes, v_session_value, p_payment_method, 'pending',
      now(), v_session_expires_at, v_session_grace_at,
      v_order.id,
      -- Distinct idem key so the session row doesn't collide with the
      -- order's idempotency_key (which lives on a unique index too).
      COALESCE(p_idempotency_key, v_order.id::TEXT) || ':session'
    ) RETURNING * INTO v_session_row;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_type := COALESCE(v_item->>'type', 'menu_item');
    v_qty := (v_item->>'quantity')::INTEGER;

    IF v_type = 'menu_item' THEN
      SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
      SELECT brand INTO v_brand FROM menus WHERE id = v_menu_item.menu_id;
      INSERT INTO order_items(
        order_id, line_type, menu_item_id, brand, name_snapshot,
        quantity, unit_price_paise
      ) VALUES (
        v_order.id, 'menu_item', v_menu_item.id, v_brand, v_menu_item.name,
        v_qty, v_menu_item.price_paise
      );
    ELSIF v_type = 'combo' THEN
      SELECT * INTO v_combo FROM combos WHERE id = (v_item->>'combo_id')::UUID;
      INSERT INTO order_items(
        order_id, line_type, combo_id, brand, name_snapshot,
        quantity, unit_price_paise
      ) VALUES (
        v_order.id, 'combo', v_combo.id, 'combo', v_combo.name,
        v_qty, v_combo.price_paise
      );
    ELSIF v_type = 'fit_meal' THEN
      v_fit_priced := _fit_validate_and_price(
        (v_item->>'template_id')::UUID,
        v_item->'selections'
      );
      v_unit_price := (v_fit_priced->>'final_price_paise')::INTEGER;

      INSERT INTO fit_meal_orders(
        family_id, template_id,
        base_price_paise, total_upcharge_paise, final_price_paise,
        selections_jsonb, status, order_id
      ) VALUES (
        p_family_id, (v_item->>'template_id')::UUID,
        (v_fit_priced->>'base_price_paise')::INTEGER,
        (v_fit_priced->>'total_upcharge_paise')::INTEGER,
        v_unit_price,
        v_item->'selections', 'ordered', v_order.id
      ) RETURNING id INTO v_fit_id;

      INSERT INTO order_items(
        order_id, line_type, fit_meal_order_id, brand, name_snapshot,
        quantity, unit_price_paise, selections_jsonb
      ) VALUES (
        v_order.id, 'fit_meal', v_fit_id, 'fit',
        (SELECT name FROM fit_meal_templates WHERE id = (v_item->>'template_id')::UUID),
        v_qty, v_unit_price, v_item->'selections'
      );
    END IF;
  END LOOP;

  IF p_payment_method = 'wallet' THEN
    UPDATE wallet_transactions SET reference_id = v_order.id
      WHERE family_id = p_family_id
        AND type IN ('order_debit','coins_credit')
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'order.place', 'order', v_order.id, p_venue_id,
    jsonb_build_object(
      'invoice_number', v_invoice,
      'food_taxable_paise', v_food_taxable,
      'food_gst_paise', v_food_gst,
      'session_value_paise', v_session_value,
      'session_taxable_paise', v_session_taxable,
      'session_gst_paise', v_session_gst,
      'rounding_paise', v_rounding,
      'grand_total_paise', v_grand_total,
      'coins_earned', v_coins,
      'customer_gstin', p_customer_gstin,
      'line_count', jsonb_array_length(p_items),
      'session_id', v_session_row.id,
      'combo_session_minutes', v_combo_session_required_minutes
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'invoice_number', v_invoice,
    'total_paise', v_grand_total,
    'food_taxable_paise', v_food_taxable,
    'food_gst_paise', v_food_gst,
    'session_value_paise', v_session_value,
    'session_taxable_paise', v_session_taxable,
    'session_gst_paise', v_session_gst,
    'rounding_paise', v_rounding,
    'coins_earned', v_coins,
    'session_id', v_session_row.id
  );
END $$;

-- 3. qr_scan_validate — skip wallet movement when the session was paid
--    via order_place. We re-declare just the wallet-movement branch by
--    finding it and patching; simpler to CREATE OR REPLACE the whole
--    function but the 0023 body is long. Use a thin wrapper trick:
--    add a guard so the body's "IF v_session.payment_method = 'wallet'"
--    block can be short-circuited by setting payment_method check to
--    also require paid_via_order_id IS NULL.
--
--    Implementation note: the 0023 function only references
--    v_session.payment_method = 'wallet' to gate the debit. We need to
--    also gate on paid_via_order_id IS NULL. Easiest robust fix is to
--    CREATE OR REPLACE the full function preserving 0023 semantics.
--    Inlined below.

CREATE OR REPLACE FUNCTION qr_scan_validate(
  p_qr_payload   TEXT,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet     tablet_devices%ROWTYPE;
  v_decoded    JSONB;
  v_session_id UUID;
  v_session    sessions%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_child_name TEXT;
  v_was_pending BOOLEAN;
  v_should_debit BOOLEAN;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = v_tablet.venue_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  BEGIN
    v_decoded := convert_from(
      decode(
        translate(p_qr_payload, '-_', '+/') ||
          repeat('=', (4 - length(p_qr_payload) % 4) % 4),
        'base64'
      ), 'UTF8'
    )::JSONB;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'qr_payload_invalid';
  END;

  v_session_id := (v_decoded->>'session_id')::UUID;
  IF v_session_id IS NULL THEN RAISE EXCEPTION 'qr_payload_invalid'; END IF;

  SELECT * INTO v_session FROM sessions WHERE id = v_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.venue_id != v_tablet.venue_id THEN
    RAISE EXCEPTION 'session_wrong_venue';
  END IF;

  IF v_session.status NOT IN ('pending','active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;
  IF v_session.staff_scanned_at IS NOT NULL THEN
    RAISE EXCEPTION 'qr_already_scanned';
  END IF;

  v_was_pending := (v_session.status = 'pending');
  -- Sessions paid via order_place already moved money; the scan is just
  -- a status flip. paid_via_order_id IS NOT NULL → no wallet debit here.
  v_should_debit := v_was_pending
    AND v_session.payment_method = 'wallet'
    AND v_session.paid_via_order_id IS NULL;

  IF v_was_pending THEN
    SELECT * INTO v_config FROM venue_config WHERE venue_id = v_tablet.venue_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

    IF v_should_debit THEN
      SELECT * INTO v_wallet FROM wallets
        WHERE family_id = v_session.family_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
      IF v_wallet.held_paise < v_session.amount_paise THEN
        RAISE EXCEPTION 'hold_lost';
      END IF;
      IF v_wallet.balance_paise < v_session.amount_paise THEN
        RAISE EXCEPTION 'insufficient_balance';
      END IF;

      UPDATE wallets SET
        held_paise    = held_paise    - v_session.amount_paise,
        balance_paise = balance_paise - v_session.amount_paise,
        updated_at    = now()
      WHERE family_id = v_session.family_id RETURNING * INTO v_wallet;

      INSERT INTO wallet_transactions(
        family_id, type, amount_paise, balance_after_paise,
        payment_method, reference_type, reference_id, idempotency_key
      ) VALUES (
        v_session.family_id, 'session_debit', -v_session.amount_paise, v_wallet.balance_paise,
        'wallet', 'session', v_session.id,
        COALESCE(v_session.idempotency_key, v_session.id::TEXT) || ':scan'
      );
    END IF;

    UPDATE sessions SET
      status               = 'active',
      started_at           = now(),
      expires_at           = now() + (v_session.duration_minutes || ' minutes')::INTERVAL,
      grace_force_close_at = now() + ((v_session.duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,
      staff_scanned_at     = now(),
      staff_pin_id         = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  ELSE
    UPDATE sessions SET
      staff_scanned_at = now(),
      staff_pin_id     = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  END IF;

  SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff',
    CASE WHEN v_was_pending THEN 'session.qr_scan_activate' ELSE 'session.qr_scan_revisit' END,
    'session', v_session.id, v_tablet.venue_id,
    jsonb_build_object(
      'was_pending', v_was_pending,
      'paid_via_order', v_session.paid_via_order_id,
      'amount_paise', v_session.amount_paise
    )
  );

  RETURN jsonb_build_object(
    'success',      true,
    'session_id',   v_session.id,
    'child_id',     v_session.child_id,
    'child_name',   v_child_name,
    'status',       v_session.status,
    'expires_at',   v_session.expires_at,
    'was_pending',  v_was_pending
  );
END $$;

REVOKE EXECUTE ON FUNCTION qr_scan_validate(TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION qr_scan_validate(TEXT, UUID) TO authenticated, service_role;

-- 4. session_cancel_pending — skip hold release for combo-paid sessions.
--    The autocancel cron will still cancel them (status='cancelled_pre_scan')
--    after the no-show timeout, but won't touch the wallet (no hold to
--    release — order_place already charged). Refunding a no-show combo
--    is admin-initiated.

CREATE OR REPLACE FUNCTION session_cancel_pending(
  p_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_actor   TEXT;
  v_actor_id UUID;
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

  -- Release wallet hold only for direct session_create flows.
  -- Combo-paid sessions (paid_via_order_id IS NOT NULL) never created
  -- a hold — order_place debited balance directly.
  IF v_session.payment_method = 'wallet'
     AND v_session.paid_via_order_id IS NULL THEN
    UPDATE wallets
       SET held_paise = GREATEST(held_paise - v_session.amount_paise, 0),
           updated_at = now()
     WHERE family_id = v_session.family_id;
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
      'paid_via_order_id', v_session.paid_via_order_id
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

REVOKE EXECUTE ON FUNCTION session_cancel_pending(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION session_cancel_pending(UUID) TO authenticated, service_role;

COMMIT;
