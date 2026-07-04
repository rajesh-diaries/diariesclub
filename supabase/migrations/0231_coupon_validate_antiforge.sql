-- 0231 — coupon_validate: match session_create's anti-forge + percent clamp
--
-- coupon_validate is the client-side preview for a coupon. It gated min_kids on
-- the client-supplied p_kid_count only, and its percent_off branch had no lower
-- clamp — so the preview could say "valid, ₹X off" for a coupon that
-- session_create (0230) now rejects, or show a >100% discount. Bring it in line
-- so the preview matches what will actually be charged.

CREATE OR REPLACE FUNCTION public.coupon_validate(p_code text, p_amount_paise integer, p_kid_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id UUID := auth.uid();
  v_coupon coupons%ROWTYPE;
  v_normalized TEXT := upper(trim(p_code));
  v_discount INTEGER := 0;
  v_family_uses INTEGER;
  v_family_kids INTEGER;
BEGIN
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_amount_paise IS NULL OR p_amount_paise <= 0 THEN
    RETURN jsonb_build_object('valid', false, 'message', 'No amount to apply to.');
  END IF;

  SELECT * INTO v_coupon FROM coupons WHERE upper(code) = v_normalized;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'message', 'That coupon code doesn''t exist.');
  END IF;

  IF NOT v_coupon.is_active THEN
    RETURN jsonb_build_object('valid', false, 'message', 'This coupon is no longer active.');
  END IF;

  IF v_coupon.valid_from > now() THEN
    RETURN jsonb_build_object('valid', false, 'message', 'This coupon isn''t active yet.');
  END IF;

  IF v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < now() THEN
    RETURN jsonb_build_object('valid', false, 'message', 'This coupon has expired.');
  END IF;

  IF v_coupon.max_uses IS NOT NULL AND v_coupon.uses_count >= v_coupon.max_uses THEN
    RETURN jsonb_build_object('valid', false, 'message', 'This coupon has been fully redeemed.');
  END IF;

  SELECT COUNT(*) INTO v_family_uses
    FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND family_id = v_caller_id;
  IF v_family_uses >= v_coupon.max_per_family THEN
    RETURN jsonb_build_object('valid', false, 'message', 'You''ve already used this coupon.');
  END IF;

  IF v_coupon.min_kids > COALESCE(p_kid_count, 1) THEN
    RETURN jsonb_build_object(
      'valid', false,
      'message', 'This code needs ' || v_coupon.min_kids || ' kids in one booking.'
    );
  END IF;

  -- Server anti-forge: match session_create — require the family to actually
  -- have >= min_kids registered children (p_kid_count alone is client-supplied).
  SELECT count(*) INTO v_family_kids
    FROM children WHERE family_id = v_caller_id AND deleted_at IS NULL;
  IF v_coupon.min_kids > v_family_kids THEN
    RETURN jsonb_build_object(
      'valid', false,
      'message', 'This code needs ' || v_coupon.min_kids || ' kids in one booking.'
    );
  END IF;

  IF p_amount_paise < v_coupon.min_order_paise THEN
    RETURN jsonb_build_object(
      'valid', false,
      'message', 'Minimum order ₹' || (v_coupon.min_order_paise / 100)::TEXT || ' required.'
    );
  END IF;

  IF v_coupon.type = 'percent_off' THEN
    v_discount := (p_amount_paise * v_coupon.value) / 100;
    IF v_coupon.max_discount_paise IS NOT NULL AND v_discount > v_coupon.max_discount_paise THEN
      v_discount := v_coupon.max_discount_paise;
    END IF;
    v_discount := LEAST(v_discount, p_amount_paise);
  ELSIF v_coupon.type = 'flat_off' THEN
    v_discount := LEAST(v_coupon.value, p_amount_paise);
  ELSIF v_coupon.type = 'free_session' THEN
    v_discount := p_amount_paise;
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'coupon_id', v_coupon.id,
    'code', v_coupon.code,
    'type', v_coupon.type,
    'discount_paise', v_discount,
    'final_amount_paise', p_amount_paise - v_discount,
    'description', v_coupon.description
  );
END $function$;
