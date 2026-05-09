-- 0067_stage_perk_redeem_and_admin.sql
--
-- Two RPCs:
--   stage_perk_redeem(p_code, p_staff_pin_id, p_note) — staff at counter
--     types code, validates active staff PIN + grant existence + not
--     already-redeemed + not-expired, marks redeemed atomically. Returns
--     child_name + stage + perk_label so the staff app can show a clear
--     confirmation.
--   admin_stage_perk_upsert(...) — admin web CRUD for stage_perks.

CREATE OR REPLACE FUNCTION stage_perk_redeem(
  p_code         TEXT,
  p_staff_pin_id UUID,
  p_note         TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_grant stage_perk_grants%ROWTYPE;
  v_perk  stage_perks%ROWTYPE;
  v_child children%ROWTYPE;
  v_normalized TEXT := upper(trim(p_code));
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  SELECT * INTO v_grant FROM stage_perk_grants
    WHERE upper(code) = v_normalized FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'perk_code_not_found'; END IF;

  IF v_grant.redeemed_at IS NOT NULL THEN
    RAISE EXCEPTION 'perk_already_redeemed';
  END IF;

  IF v_grant.expires_at < now() THEN
    RAISE EXCEPTION 'perk_expired';
  END IF;

  SELECT * INTO v_perk  FROM stage_perks WHERE id = v_grant.perk_id;
  SELECT * INTO v_child FROM children    WHERE id = v_grant.child_id;

  UPDATE stage_perk_grants SET
    redeemed_at = now(),
    redeemed_by_pin = p_staff_pin_id,
    redeem_note = p_note
  WHERE id = v_grant.id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'stage_perk.redeem', 'stage_perk_grant', v_grant.id,
    jsonb_build_object(
      'code', v_grant.code,
      'child_id', v_grant.child_id,
      'family_id', v_grant.family_id,
      'stage', v_grant.stage,
      'trait', v_grant.trait,
      'perk_label', v_perk.perk_label,
      'note', p_note
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'grant_id', v_grant.id,
    'child_name', v_child.name,
    'stage', v_grant.stage,
    'trait', v_grant.trait,
    'perk_label', v_perk.perk_label,
    'perk_description', v_perk.perk_description
  );
END $$;

REVOKE EXECUTE ON FUNCTION stage_perk_redeem(TEXT, UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION stage_perk_redeem(TEXT, UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION admin_stage_perk_upsert(
  p_id               UUID,
  p_venue_id         UUID,
  p_stage            TEXT,
  p_perk_label       TEXT,
  p_perk_description TEXT,
  p_validity_days    INTEGER,
  p_is_active        BOOLEAN
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_stage NOT IN ('welcome','seedling','explorer','adventurer','champion','legend') THEN
    RAISE EXCEPTION 'invalid_stage: %', p_stage;
  END IF;

  IF p_validity_days IS NOT NULL AND (p_validity_days < 1 OR p_validity_days > 365) THEN
    RAISE EXCEPTION 'invalid_validity_days';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO stage_perks(
      venue_id, stage, perk_label, perk_description, validity_days, is_active
    ) VALUES (
      p_venue_id, p_stage, p_perk_label, p_perk_description,
      COALESCE(p_validity_days, 30),
      COALESCE(p_is_active, true)
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE stage_perks SET
      venue_id         = COALESCE(p_venue_id,         venue_id),
      stage            = COALESCE(p_stage,            stage),
      perk_label       = COALESCE(p_perk_label,       perk_label),
      perk_description = COALESCE(p_perk_description, perk_description),
      validity_days    = COALESCE(p_validity_days,    validity_days),
      is_active        = COALESCE(p_is_active,        is_active),
      updated_at       = now()
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'stage_perk.create' ELSE 'stage_perk.update' END,
    'stage_perk', v_id,
    jsonb_build_object(
      'stage', p_stage, 'perk_label', p_perk_label,
      'is_active', p_is_active
    )
  );

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION admin_stage_perk_upsert(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, BOOLEAN)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_stage_perk_upsert(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, BOOLEAN)
  TO authenticated;
