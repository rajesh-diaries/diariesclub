-- ===========================================================================
--  Diaries Club v1.5 — 0006_auth_rpcs.sql
--  Auth + onboarding RPCs (Session 4).
--
--  Conventions (see 0003 header for the canonical list):
--    * SECURITY DEFINER, search_path=public, LANGUAGE plpgsql
--    * auth.uid() is the family_id — these RPCs derive it from auth.uid()
--      rather than accepting it as a parameter (defence in depth: a caller
--      cannot ask the server to act on a different family's behalf).
--    * audit_log written for every state change
--    * Returns JSONB
--    * REVOKE EXECUTE FROM anon, PUBLIC; GRANT to authenticated.
--
--  Idempotent. Safe to re-run.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  family_create — called once per new auth user, after OTP verify.
--  The auth user already exists (created by the auth-otp Edge Function);
--  we INSERT the families row whose id matches auth.uid(). The wallets row
--  is auto-created by the families_create_wallet trigger from 0001.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION family_create(
  p_phone TEXT,
  p_name  TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_family families%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- E.164 sanity check (the families_validate_phone trigger will also
  -- enforce this, but a clearer error message helps the client).
  IF p_phone !~ '^\+91[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'invalid_phone' USING DETAIL = p_phone;
  END IF;

  IF char_length(coalesce(trim(p_name), '')) < 2 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;

  -- Idempotent on retry: if the row already exists for this auth user,
  -- update name/phone (in case the client retried after a partial failure)
  -- and return the existing row.
  INSERT INTO families (id, phone, name, last_active_at)
  VALUES (v_uid, p_phone, trim(p_name), now())
  ON CONFLICT (id) DO UPDATE
    SET phone          = EXCLUDED.phone,
        name           = EXCLUDED.name,
        last_active_at = now()
  RETURNING * INTO v_family;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_uid, 'customer', 'family.create', 'family', v_uid,
    jsonb_build_object('phone', p_phone, 'name', trim(p_name))
  );

  RETURN jsonb_build_object(
    'success',         true,
    'family_id',       v_family.id,
    'phone',           v_family.phone,
    'name',            v_family.name,
    'is_cafe_only',    v_family.is_cafe_only,
    'has_children',    v_family.has_children,
    'referral_code',   v_family.referral_code
  );
END $$;

-- ---------------------------------------------------------------------------
--  child_create — adds a child to the caller's family. Used in onboarding
--  step 3 and later from the Profile tab. Sets families.has_children = true.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION child_create(
  p_name             TEXT,
  p_dob              DATE,
  p_photo_url        TEXT DEFAULT NULL,
  p_favourite_hero   TEXT DEFAULT 'ellie',
  p_delivery_address TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_child children%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM families WHERE id = v_uid) THEN
    RAISE EXCEPTION 'family_not_found';
  END IF;

  IF char_length(coalesce(trim(p_name), '')) < 1 THEN
    RAISE EXCEPTION 'invalid_child_name';
  END IF;

  -- DOB must be in the past and within 14 years.
  IF p_dob IS NULL OR p_dob > current_date OR p_dob < current_date - INTERVAL '14 years' THEN
    RAISE EXCEPTION 'invalid_dob';
  END IF;

  IF p_favourite_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero' USING DETAIL = p_favourite_hero;
  END IF;

  INSERT INTO children (
    family_id, name, date_of_birth, photo_url, favourite_hero, delivery_address
  ) VALUES (
    v_uid, trim(p_name), p_dob, p_photo_url, p_favourite_hero, p_delivery_address
  )
  RETURNING * INTO v_child;

  -- Flip has_children once we know there's at least one.
  UPDATE families
     SET has_children   = true,
         is_cafe_only   = false,
         last_active_at = now()
   WHERE id = v_uid;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_uid, 'customer', 'child.create', 'child', v_child.id,
    jsonb_build_object(
      'name',           trim(p_name),
      'dob',            p_dob,
      'favourite_hero', p_favourite_hero,
      'has_photo',      p_photo_url IS NOT NULL
    )
  );

  RETURN jsonb_build_object(
    'success',        true,
    'child_id',       v_child.id,
    'name',           v_child.name,
    'date_of_birth',  v_child.date_of_birth,
    'favourite_hero', v_child.favourite_hero,
    'photo_url',      v_child.photo_url
  );
END $$;

-- ---------------------------------------------------------------------------
--  family_set_cafe_only — escape from onboarding for parents who only want
--  the cafe / cafe-only ordering. Flips is_cafe_only=true, has_children=false.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION family_set_cafe_only() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM families WHERE id = v_uid) THEN
    RAISE EXCEPTION 'family_not_found';
  END IF;

  -- A family that already has children cannot revert to cafe-only via this
  -- RPC; that's a Profile-tab concern (Session 5b — anonymisation).
  IF EXISTS (SELECT 1 FROM children WHERE family_id = v_uid) THEN
    RAISE EXCEPTION 'has_existing_children';
  END IF;

  UPDATE families
     SET is_cafe_only   = true,
         has_children   = false,
         last_active_at = now()
   WHERE id = v_uid;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_uid, 'customer', 'family.set_cafe_only', 'family', v_uid,
    jsonb_build_object('is_cafe_only', true)
  );

  RETURN jsonb_build_object('success', true, 'is_cafe_only', true);
END $$;

-- ---------------------------------------------------------------------------
--  family_touch_active — bump last_active_at on returning auth (re-OTP for
--  an already-onboarded family). Cheap; idempotent. No audit_log entry —
--  this would flood the table on every cold-start.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION family_touch_active() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE families SET last_active_at = now() WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);
END $$;

-- ---------------------------------------------------------------------------
--  Permissions: revoke the default PUBLIC grant, then explicitly grant to
--  authenticated. (anon callers are rejected by the auth.uid() check inside
--  the body, but defence in depth — see 0004's rationale.)
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.family_create(TEXT, TEXT)                                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.child_create(TEXT, DATE, TEXT, TEXT, TEXT)               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.family_set_cafe_only()                                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.family_touch_active()                                    FROM PUBLIC, anon;

GRANT  EXECUTE ON FUNCTION public.family_create(TEXT, TEXT)                                TO authenticated;
GRANT  EXECUTE ON FUNCTION public.child_create(TEXT, DATE, TEXT, TEXT, TEXT)               TO authenticated;
GRANT  EXECUTE ON FUNCTION public.family_set_cafe_only()                                   TO authenticated;
GRANT  EXECUTE ON FUNCTION public.family_touch_active()                                    TO authenticated;
