-- 0196 — order preview: compute totals without creating an order or touching wallets.
-- Mirrors order_place pricing pass exactly so the customer sees the same
-- GST split and grand total that order_place will charge.

CREATE OR REPLACE FUNCTION public.order_preview(
  p_venue_id UUID,
  p_family_id UUID,
  p_items JSONB,
  p_child_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_config venue_config%ROWTYPE;

  v_food_taxable   INTEGER := 0;
  v_session_value  INTEGER := 0;

  v_food_gst       INTEGER;
  v_session_taxable INTEGER;
  v_session_gst    INTEGER;
  v_grand_total_raw INTEGER;
  v_grand_total    INTEGER;
  v_rounding       INTEGER;
  v_coins          INTEGER := 0;

  v_item       JSONB;
  v_type       TEXT;
  v_qty        INTEGER;
  v_menu_item  menu_items%ROWTYPE;
  v_combo      combos%ROWTYPE;
  v_combo_session_minutes INTEGER;
  v_session_price INTEGER;
  v_combo_food_portion INTEGER;
  v_fit_priced JSONB;
  v_unit_price INTEGER;
  v_combo_fit_upcharge INTEGER;
  v_combo_session_required_minutes INTEGER := NULL;
BEGIN
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'invalid_items';
  END IF;

  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_type := COALESCE(v_item->>'type', 'menu_item');
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

    IF v_type = 'menu_item' THEN
      SELECT * INTO v_menu_item FROM menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID;
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

      IF v_combo.fit_template_id IS NOT NULL THEN
        IF v_item->'fit_selections' IS NULL THEN
          RAISE EXCEPTION 'combo_fit_selections_required';
        END IF;
        v_fit_priced := _fit_validate_and_price(
          v_combo.fit_template_id,
          v_item->'fit_selections'
        );
        v_combo_fit_upcharge := (v_fit_priced->>'total_upcharge_paise')::INTEGER;
        v_food_taxable := v_food_taxable + (v_combo_fit_upcharge * v_qty);
      END IF;

      IF v_combo_session_minutes IS NOT NULL AND v_combo_session_minutes > 0 THEN
        IF p_child_id IS NULL THEN
          RAISE EXCEPTION 'combo_requires_child';
        END IF;
        IF v_combo_session_required_minutes IS NULL THEN
          v_combo_session_required_minutes := v_combo_session_minutes;
        END IF;
        IF v_combo_session_required_minutes IS NOT NULL AND v_qty > 1 THEN
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

  IF v_combo_session_required_minutes IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM children
       WHERE id = p_child_id AND family_id = p_family_id
    ) THEN
      RAISE EXCEPTION 'child_not_in_family';
    END IF;
  END IF;

  v_food_gst := ROUND(v_food_taxable * COALESCE(v_config.food_gst_percent, 5)::NUMERIC / 100)::INTEGER;
  v_session_taxable := CASE WHEN v_session_value > 0
    THEN ROUND(v_session_value * 100::NUMERIC / (100 + COALESCE(v_config.gst_percent, 18)))::INTEGER
    ELSE 0 END;
  v_session_gst := v_session_value - v_session_taxable;

  v_grand_total_raw := v_food_taxable + v_food_gst + v_session_value;
  v_grand_total     := (ROUND(v_grand_total_raw::NUMERIC / 100) * 100)::INTEGER;
  v_rounding        := v_grand_total - v_grand_total_raw;

  v_coins := (v_food_taxable * v_config.cashback_percent / 100 / 100)::INTEGER;

  RETURN jsonb_build_object(
    'success', true,
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

REVOKE EXECUTE ON FUNCTION public.order_preview(UUID, UUID, JSONB, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.order_preview(UUID, UUID, JSONB, UUID) TO authenticated, service_role;
