-- 0102 — give p_staff_pin_id a DEFAULT NULL so the customer-side
-- callers (cart_sheet, combo_purchase_sheet) don't have to pass it.
-- Same body as 0101, just adds DEFAULT NULL on p_staff_pin_id. To
-- avoid a duplicate-overload error we DROP the 0101 signature first.

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
      'line_count', jsonb_array_length(p_items)
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
    'coins_earned', v_coins
  );
END $$;
