-- 0055_coupons_schema.sql
--
-- Coupon system for promo codes the founder/admin can hand out (social,
-- partner deals, refund-as-credit, etc). Independent of the referral
-- system — referrals are family-to-family and free, coupons are
-- admin-issued and configurable.
--
-- Two tables:
--   * coupons              — what's offered, by admin
--   * coupon_redemptions   — who used it, when, on what session
--
-- Three coupon types (room to add more later):
--   percent_off   — value=10 means 10% off, capped by max_discount_paise
--   flat_off      — value=100 means ₹100 off (in paise: value * 100)
--   free_session  — value ignored; price becomes 0 for the session
--
-- Single-use vs multi-use: max_uses NULL means unlimited; otherwise
-- redemptions cap at max_uses across all customers.
-- Per-family limit: max_per_family caps the same coupon being used
-- multiple times by one family.
--
-- Customers don't see this table directly — RLS denies SELECT for
-- authenticated. They interact only through coupon_validate / coupon_redeem
-- RPCs which run SECURITY DEFINER.

CREATE TABLE IF NOT EXISTS coupons (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                  TEXT NOT NULL UNIQUE,
  type                  TEXT NOT NULL CHECK (type IN ('percent_off', 'flat_off', 'free_session')),
  -- Value semantics depend on type:
  --   percent_off: 1-100 (percentage)
  --   flat_off:    discount amount in paise
  --   free_session: ignored (kept for schema simplicity, set 0)
  value                 INTEGER NOT NULL CHECK (value >= 0),
  -- Optional cap for percent_off so a 50%-off doesn't unbound on a
  -- party-package payment. Ignored for flat_off / free_session.
  max_discount_paise    INTEGER,
  -- Optional minimum cart amount for the coupon to apply (in paise).
  min_order_paise       INTEGER NOT NULL DEFAULT 0,
  -- NULL = unlimited total uses across all customers.
  max_uses              INTEGER,
  uses_count            INTEGER NOT NULL DEFAULT 0,
  -- NULL = unlimited per-family. 1 = single-use per family.
  max_per_family        INTEGER NOT NULL DEFAULT 1,
  valid_from            TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_until           TIMESTAMPTZ,
  is_active             BOOLEAN NOT NULL DEFAULT true,
  description           TEXT,
  created_by            UUID REFERENCES admin_users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coupons_code   ON coupons(upper(code));
CREATE INDEX IF NOT EXISTS idx_coupons_active ON coupons(is_active) WHERE is_active = true;

CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id         UUID NOT NULL REFERENCES coupons(id) ON DELETE RESTRICT,
  family_id         UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  session_id        UUID REFERENCES sessions(id) ON DELETE SET NULL,
  discount_paise    INTEGER NOT NULL,
  redeemed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon ON coupon_redemptions(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_family ON coupon_redemptions(family_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_session ON coupon_redemptions(session_id);

ALTER TABLE coupons              ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_redemptions   ENABLE ROW LEVEL SECURITY;

-- Admin sees everything; customers see nothing directly (must go via RPC).
DROP POLICY IF EXISTS coupons_admin_all ON coupons;
CREATE POLICY coupons_admin_all ON coupons
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

DROP POLICY IF EXISTS coupon_redemptions_admin_all ON coupon_redemptions;
CREATE POLICY coupon_redemptions_admin_all ON coupon_redemptions
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

DROP POLICY IF EXISTS coupon_redemptions_own ON coupon_redemptions;
CREATE POLICY coupon_redemptions_own ON coupon_redemptions
  FOR SELECT TO authenticated
  USING (family_id = auth.uid());

-- ===========================================================================
-- coupon_validate(p_code, p_amount_paise)
--   Returns {valid, discount_paise, type, code, message} without redeeming.
--   Used by the customer client to preview the discount before purchase.
-- ===========================================================================
CREATE OR REPLACE FUNCTION coupon_validate(
  p_code TEXT,
  p_amount_paise INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
END $$;

REVOKE EXECUTE ON FUNCTION coupon_validate(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION coupon_validate(TEXT, INTEGER) TO authenticated;

-- ===========================================================================
-- coupon_redeem(p_code, p_session_id, p_amount_paise)
--   Atomically: re-validates, increments uses_count, inserts redemption row.
--   Caller of session_create should call this AFTER session_create succeeds
--   and before showing the price to user (or call validate first to display
--   then redeem on confirmation).
--
--   Returns {success, discount_paise, redemption_id}.
-- ===========================================================================
CREATE OR REPLACE FUNCTION coupon_redeem(
  p_code TEXT,
  p_session_id UUID,
  p_amount_paise INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_coupon coupons%ROWTYPE;
  v_normalized TEXT := upper(trim(p_code));
  v_discount INTEGER := 0;
  v_family_uses INTEGER;
  v_redemption_id UUID;
  v_session sessions%ROWTYPE;
BEGIN
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.family_id <> v_caller_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT * INTO v_coupon FROM coupons WHERE upper(code) = v_normalized FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_code'; END IF;
  IF NOT v_coupon.is_active THEN RAISE EXCEPTION 'coupon_inactive'; END IF;
  IF v_coupon.valid_from > now() THEN RAISE EXCEPTION 'coupon_not_yet_active'; END IF;
  IF v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < now() THEN RAISE EXCEPTION 'coupon_expired'; END IF;
  IF v_coupon.max_uses IS NOT NULL AND v_coupon.uses_count >= v_coupon.max_uses THEN RAISE EXCEPTION 'coupon_exhausted'; END IF;

  SELECT COUNT(*) INTO v_family_uses
    FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND family_id = v_caller_id;
  IF v_family_uses >= v_coupon.max_per_family THEN RAISE EXCEPTION 'already_used_by_family'; END IF;

  IF p_amount_paise < v_coupon.min_order_paise THEN RAISE EXCEPTION 'min_order_not_met'; END IF;

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

  UPDATE coupons SET uses_count = uses_count + 1, updated_at = now()
    WHERE id = v_coupon.id;

  INSERT INTO coupon_redemptions(coupon_id, family_id, session_id, discount_paise)
    VALUES (v_coupon.id, v_caller_id, p_session_id, v_discount)
    RETURNING id INTO v_redemption_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_caller_id, 'customer', 'coupon.redeem', 'coupon', v_coupon.id, v_session.venue_id,
    jsonb_build_object(
      'code', v_coupon.code,
      'session_id', p_session_id,
      'discount_paise', v_discount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'redemption_id', v_redemption_id,
    'coupon_id', v_coupon.id,
    'discount_paise', v_discount
  );
END $$;

REVOKE EXECUTE ON FUNCTION coupon_redeem(TEXT, UUID, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION coupon_redeem(TEXT, UUID, INTEGER) TO authenticated;

COMMENT ON TABLE coupons IS 'Admin-issued promo codes. RLS: admin all, customers via RPC only.';
COMMENT ON TABLE coupon_redemptions IS 'Per-customer per-coupon usage log. RLS: admin all, customers see their own.';
