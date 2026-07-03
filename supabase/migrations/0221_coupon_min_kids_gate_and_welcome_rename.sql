-- BIG BUG: the multi-kid coupons (ZENA/RAFI/GERRY/WILDPACK) had min_order ₹0 and
-- no server-side kid-count check, so e.g. GERRY (₹400, meant for 4 kids) could be
-- applied to a single 1-kid session. The "N kids" rule only lived in the app UI.
-- Add a min_kids gate enforced server-side in coupon_validate AND session_create.
-- Also rename the first-session welcome coupon back ELLIE -> WELCOME100 so it reads
-- clearly as the welcome offer (distinct from the multi-kid hero coupons).

ALTER TABLE coupons ADD COLUMN IF NOT EXISTS min_kids integer NOT NULL DEFAULT 1;

UPDATE coupons SET code='WELCOME100' WHERE upper(code)='ELLIE';
UPDATE coupons SET min_kids=2 WHERE upper(code)='ZENA';
UPDATE coupons SET min_kids=3 WHERE upper(code)='RAFI';
UPDATE coupons SET min_kids=4 WHERE upper(code)='GERRY';
UPDATE coupons SET min_kids=5 WHERE upper(code)='WILDPACK';

-- ---- coupon_validate: reject when fewer kids than the coupon requires ----
DROP FUNCTION IF EXISTS public.coupon_validate(text, integer);
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

-- ---- welcome_offer_for_session: welcome coupon is WELCOME100 again ----
CREATE OR REPLACE FUNCTION public.welcome_offer_for_session(p_family_id uuid, p_venue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_family    families%ROWTYPE;
  v_coupon    coupons%ROWTYPE;
  v_config    venue_config%ROWTYPE;
  v_has_played BOOLEAN;
  v_used      BOOLEAN;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_family FROM families WHERE id = p_family_id;
  IF NOT FOUND OR v_family.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('type', 'none');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM sessions
     WHERE family_id = p_family_id
       AND status IN ('active','grace','completed','auto_closed')
  ) INTO v_has_played;

  IF v_has_played THEN
    RETURN jsonb_build_object('type', 'none');
  END IF;

  IF v_family.referrer_family_id IS NOT NULL THEN
    SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
    RETURN jsonb_build_object(
      'type', 'referral',
      'credit_paise', COALESCE(v_config.referral_new_family_credit_paise, 0)
    );
  END IF;

  SELECT * INTO v_coupon FROM coupons WHERE upper(code) = 'WELCOME100';
  IF NOT FOUND
     OR NOT v_coupon.is_active
     OR v_coupon.valid_from > now()
     OR (v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < now())
     OR (v_coupon.max_uses IS NOT NULL AND v_coupon.uses_count >= v_coupon.max_uses) THEN
    RETURN jsonb_build_object('type', 'none');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM coupon_redemptions
     WHERE coupon_id = v_coupon.id AND family_id = p_family_id
  ) INTO v_used;
  IF v_used THEN
    RETURN jsonb_build_object('type', 'none');
  END IF;

  RETURN jsonb_build_object(
    'type', 'discount',
    'code', v_coupon.code,
    'value_paise', v_coupon.value,
    'min_order_paise', v_coupon.min_order_paise
  );
END $function$;
