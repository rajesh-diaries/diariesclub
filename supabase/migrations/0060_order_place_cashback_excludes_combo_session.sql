-- 0060_order_place_cashback_excludes_combo_session.sql
--
-- Customers earn Diaries Coins on the FOOD portion of combos only —
-- the play-session portion is rewarded via XP at session_complete and
-- shouldn't double-earn through wallet cashback.
--
-- Per-line cashback-eligible amount (gross, GST-inclusive):
--   menu_item                : price_paise * qty
--   fit_meal                 : final_price_paise * qty
--   combo without session    : combo.price_paise * qty
--   combo with session       : MAX(0, combo.price_paise - session_price) * qty
--                              session_price from venue_config:
--                              60 min  → session_1hr_price_paise
--                              120 min → session_2hr_price_paise
--                              other   → 0
--
-- Cashback math then strips GST from the gross-eligible total and
-- applies cashback_percent (consistent with 0059's GST-inclusive rule).
--
-- Reversibility: re-deploy 0059_order_place_gst_inclusive.sql.

CREATE OR REPLACE FUNCTION order_place(
  p_venue_id UUID,
  p_family_id UUID,
  p_items JSONB,
  p_fulfillment_mode TEXT,
  p_payment_method TEXT,
  p_combo_id UUID DEFAULT NULL,
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order      orders%ROWTYPE;
  v_existing   orders%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_gross      INTEGER := 0;
  v_subtotal   INTEGER := 0;
  v_gst        INTEGER := 0;
  v_total      INTEGER;
  v_coins      INTEGER := 0;
  v_cashback_eligible_gross INTEGER := 0;
  v_cashback_eligible_net   INTEGER := 0;
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
        'total_paise', v_existing.total_paise
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
      v_gross := v_gross + (v_menu_item.price_paise * v_qty);
      v_cashback_eligible_gross := v_cashback_eligible_gross + (v_menu_item.price_paise * v_qty);
    ELSIF v_type = 'combo' THEN
      SELECT * INTO v_combo FROM combos
        WHERE id = (v_item->>'combo_id')::UUID
          AND venue_id = p_venue_id AND is_active;
      IF NOT FOUND THEN RAISE EXCEPTION 'invalid_combo'; END IF;
      v_gross := v_gross + (v_combo.price_paise * v_qty);

      v_combo_session_minutes := (v_combo.inclusions->>'session_minutes')::INTEGER;
      v_session_price := CASE
        WHEN v_combo_session_minutes = 60  THEN v_config.session_1hr_price_paise
        WHEN v_combo_session_minutes = 120 THEN v_config.session_2hr_price_paise
        ELSE 0
      END;
      v_combo_food_portion := GREATEST(0, v_combo.price_paise - v_session_price);
      v_cashback_eligible_gross := v_cashback_eligible_gross + (v_combo_food_portion * v_qty);
    ELSIF v_type = 'fit_meal' THEN
      v_fit_priced := _fit_validate_and_price(
        (v_item->>'template_id')::UUID,
        v_item->'selections'
      );
      v_unit_price := (v_fit_priced->>'final_price_paise')::INTEGER;
      v_gross := v_gross + (v_unit_price * v_qty);
      v_cashback_eligible_gross := v_cashback_eligible_gross + (v_unit_price * v_qty);
    ELSE
      RAISE EXCEPTION 'invalid_line_type: %', v_type;
    END IF;
  END LOOP;

  v_gst      := (v_gross * v_config.gst_percent / (100 + v_config.gst_percent))::INTEGER;
  v_subtotal := v_gross - v_gst;
  v_total    := v_gross;

  v_cashback_eligible_net :=
    (v_cashback_eligible_gross * 100 / (100 + v_config.gst_percent))::INTEGER;

  IF p_payment_method = 'wallet' THEN
    v_coins := (v_cashback_eligible_net * v_config.cashback_percent / 100)::INTEGER;

    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_total THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_total + v_coins,
      coins_lifetime = coins_lifetime + v_coins,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      coins_amount, payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'order_debit', -v_total + v_coins, v_wallet.balance_paise,
      v_coins, 'wallet', 'order', p_idempotency_key
    );
  END IF;

  INSERT INTO orders(
    venue_id, family_id, staff_pin_id, fulfillment_mode, payment_method,
    subtotal_paise, gst_paise, combo_discount_paise, total_paise,
    coins_earned, combo_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_staff_pin_id, p_fulfillment_mode, p_payment_method,
    v_subtotal, v_gst, 0, v_total,
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
        AND type = 'order_debit'
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'order.place', 'order', v_order.id, p_venue_id,
    jsonb_build_object(
      'gross_paise', v_gross,
      'net_subtotal_paise', v_subtotal,
      'gst_paise', v_gst,
      'cashback_eligible_gross_paise', v_cashback_eligible_gross,
      'cashback_eligible_net_paise', v_cashback_eligible_net,
      'coins_earned', v_coins,
      'total_paise', v_total,
      'line_count', jsonb_array_length(p_items)
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'total_paise', v_total,
    'coins_earned', v_coins
  );
END $$;
