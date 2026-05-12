-- 0126 — admin edits to stage perks flow live to customer.
--
-- Principle: admin shouldn't be locked out of changing perks just
-- because a kid earned the old one. When admin removes or deactivates
-- a perk, unredeemed grants pointing at it revert to unchosen slots
-- (perk_id NULL) so the kid picks again from the LIVE pool of options.
-- Redeemed grants are preserved for audit.
--
-- Two RPC paths are updated:
--   * admin_stage_perk_delete — already archives when grants exist;
--     now also reverts unredeemed grants so the perk row can be
--     hard-deleted when no redemptions remain.
--   * admin_stage_perk_upsert — when toggling is_active true→false
--     via the Edit dialog, behave the same as Delete: revert
--     unredeemed grants. Label/description edits don't need a
--     reversion — they auto-flow via the join on stage_perks.

CREATE OR REPLACE FUNCTION public.admin_stage_perk_delete(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_perk            stage_perks%ROWTYPE;
  v_redeemed_count  INTEGER;
  v_reverted_count  INTEGER;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_perk FROM stage_perks WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE stage_perk_grants SET
    perk_id    = NULL,
    code       = NULL,
    chosen_at  = NULL,
    expires_at = NULL
  WHERE perk_id = p_id AND redeemed_at IS NULL;
  GET DIAGNOSTICS v_reverted_count = ROW_COUNT;

  SELECT count(*) INTO v_redeemed_count
    FROM stage_perk_grants WHERE perk_id = p_id;

  IF v_redeemed_count = 0 THEN
    DELETE FROM stage_perks WHERE id = p_id;
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id, new_value
    ) VALUES (
      auth.uid(), 'admin', 'stage_perk.delete', 'stage_perk', p_id,
      jsonb_build_object(
        'stage', v_perk.stage, 'trait', v_perk.trait,
        'perk_label', v_perk.perk_label,
        'reverted_unredeemed_grants', v_reverted_count
      )
    );
    RETURN jsonb_build_object(
      'deleted', true, 'archived', false,
      'reverted_grants', v_reverted_count
    );
  ELSE
    UPDATE stage_perks SET is_active = false, updated_at = now()
      WHERE id = p_id;
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id, new_value
    ) VALUES (
      auth.uid(), 'admin', 'stage_perk.archive', 'stage_perk', p_id,
      jsonb_build_object(
        'stage', v_perk.stage, 'trait', v_perk.trait,
        'perk_label', v_perk.perk_label,
        'redeemed_grants', v_redeemed_count,
        'reverted_unredeemed_grants', v_reverted_count
      )
    );
    RETURN jsonb_build_object(
      'deleted', false, 'archived', true,
      'redeemed_grants', v_redeemed_count,
      'reverted_grants', v_reverted_count
    );
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_delete(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_stage_perk_upsert(
  p_id              UUID,
  p_venue_id        UUID,
  p_stage           TEXT,
  p_trait           TEXT,
  p_perk_label      TEXT,
  p_perk_description TEXT,
  p_validity_days   INTEGER,
  p_is_active       BOOLEAN
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id        UUID;
  v_was_active BOOLEAN;
  v_reverted_count INTEGER := 0;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_stage NOT IN ('welcome','seedling','explorer','adventurer','champion','legend') THEN
    RAISE EXCEPTION 'invalid_stage: %', p_stage;
  END IF;

  IF p_stage = 'welcome' THEN
    IF p_trait IS NOT NULL THEN
      RAISE EXCEPTION 'welcome_stage_must_have_null_trait';
    END IF;
  ELSE
    IF p_trait IS NULL OR p_trait NOT IN ('rafi','ellie','gerry','zena') THEN
      RAISE EXCEPTION 'trait_required_for_non_welcome_stage';
    END IF;
  END IF;

  IF p_validity_days IS NOT NULL AND (p_validity_days < 1 OR p_validity_days > 365) THEN
    RAISE EXCEPTION 'invalid_validity_days';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO stage_perks(
      venue_id, stage, trait, perk_label, perk_description, validity_days, is_active
    ) VALUES (
      p_venue_id, p_stage, p_trait, p_perk_label, p_perk_description,
      COALESCE(p_validity_days, 30),
      COALESCE(p_is_active, true)
    ) RETURNING id INTO v_id;
  ELSE
    SELECT is_active INTO v_was_active FROM stage_perks WHERE id = p_id;
    IF v_was_active IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;

    UPDATE stage_perks SET
      venue_id         = COALESCE(p_venue_id,         venue_id),
      stage            = COALESCE(p_stage,            stage),
      trait            = p_trait,
      perk_label       = COALESCE(p_perk_label,       perk_label),
      perk_description = COALESCE(p_perk_description, perk_description),
      validity_days    = COALESCE(p_validity_days,    validity_days),
      is_active        = COALESCE(p_is_active,        is_active),
      updated_at       = now()
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF v_was_active = true AND p_is_active = false THEN
      UPDATE stage_perk_grants SET
        perk_id    = NULL,
        code       = NULL,
        chosen_at  = NULL,
        expires_at = NULL
      WHERE perk_id = p_id AND redeemed_at IS NULL;
      GET DIAGNOSTICS v_reverted_count = ROW_COUNT;
    END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'stage_perk.create' ELSE 'stage_perk.update' END,
    'stage_perk', v_id,
    jsonb_build_object(
      'stage', p_stage, 'trait', p_trait,
      'perk_label', p_perk_label, 'is_active', p_is_active,
      'reverted_unredeemed_grants', v_reverted_count
    )
  );

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_upsert(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;
