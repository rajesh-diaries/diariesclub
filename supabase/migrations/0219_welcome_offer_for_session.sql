-- Decides the first-session welcome treatment for a family (mutually exclusive):
--   * referred family (has referrer_family_id) -> they already get the referral
--     ₹100 wallet credit after their first play, so NO welcome discount.
--   * non-referred genuine first-timer -> auto-applied WELCOME100 (₹100 off).
--   * everyone else (has already played, or already used WELCOME100) -> none.
-- Read-only; the caller must be the family itself.
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

  -- Genuine first-timer? No session that ever reached the floor (scanned in or
  -- completed). Pending/cancelled sessions don't count as "played".
  SELECT EXISTS(
    SELECT 1 FROM sessions
     WHERE family_id = p_family_id
       AND status IN ('active','grace','completed','auto_closed')
  ) INTO v_has_played;

  IF v_has_played THEN
    RETURN jsonb_build_object('type', 'none');
  END IF;

  -- Referred families get the referral credit after their first play, so they
  -- do NOT also get the WELCOME100 discount (mutually exclusive).
  IF v_family.referrer_family_id IS NOT NULL THEN
    SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
    RETURN jsonb_build_object(
      'type', 'referral',
      'credit_paise', COALESCE(v_config.referral_new_family_credit_paise, 0)
    );
  END IF;

  -- Non-referred first-timer: offer WELCOME100 if it is still available to them.
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
