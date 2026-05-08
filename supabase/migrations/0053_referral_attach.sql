-- 0053_referral_attach.sql
--
-- Completes the referral redemption path. Existing wiring:
--   * families.referral_code (each family has a unique 8-char code to share)
--   * referral_convert RPC (service-role; credits both wallets after a session)
--   * referral_conversions (tracks who-referred-whom on first session)
--
-- Missing piece: the new family had no way to *enter* a referrer's code.
-- This migration adds:
--   * families.referrer_family_id — nullable FK; set when new family redeems a code
--   * referral_attach(p_code TEXT) RPC — caller-invoked, validates and stores
--
-- Credit timing stays the same: both wallets get credited only after the
-- new family's first paid session (existing referral_convert logic).
-- This RPC just stores the link.

ALTER TABLE families
  ADD COLUMN IF NOT EXISTS referrer_family_id UUID REFERENCES families(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_families_referrer ON families(referrer_family_id);

-- ===========================================================================
-- referral_attach: caller (the new family) supplies a referrer's code.
-- Validates and stores the link on their families row.
--
-- Errors:
--   'invalid_code'            — code doesn't match any family
--   'self_referral'           — caller's own code
--   'already_attached'        — caller already has a referrer set
--   'already_converted'       — caller already played a session (too late)
-- ===========================================================================
CREATE OR REPLACE FUNCTION referral_attach(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_referrer  families%ROWTYPE;
  v_caller    families%ROWTYPE;
  v_normalized TEXT := upper(trim(p_code));
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_caller FROM families WHERE id = v_caller_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'family_not_found';
  END IF;

  IF v_caller.referrer_family_id IS NOT NULL THEN
    RAISE EXCEPTION 'already_attached';
  END IF;

  -- If the caller has already had a referral_convert run (e.g. via a prior
  -- bug or manual fix), block it here too.
  IF EXISTS (SELECT 1 FROM referral_conversions WHERE new_family_id = v_caller_id) THEN
    RAISE EXCEPTION 'already_converted';
  END IF;

  SELECT * INTO v_referrer FROM families WHERE referral_code = v_normalized;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_code';
  END IF;

  IF v_referrer.id = v_caller_id THEN
    RAISE EXCEPTION 'self_referral';
  END IF;

  UPDATE families
    SET referrer_family_id = v_referrer.id, updated_at = now()
    WHERE id = v_caller_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  SELECT v_caller_id, 'customer', 'referral.attach', 'family', v_caller_id, v.id,
         jsonb_build_object('referrer_family_id', v_referrer.id, 'code', v_normalized)
    FROM venues v
    LIMIT 1;

  RETURN jsonb_build_object(
    'success', true,
    'referrer_family_id', v_referrer.id,
    'message', 'Referral code applied. Credits land after your first session.'
  );
END $$;

REVOKE EXECUTE ON FUNCTION referral_attach(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION referral_attach(TEXT) TO authenticated;

COMMENT ON FUNCTION referral_attach(TEXT) IS
  'Caller-invoked: attaches a referrer to the caller''s family. Credit fires later via referral_convert after first session.';
