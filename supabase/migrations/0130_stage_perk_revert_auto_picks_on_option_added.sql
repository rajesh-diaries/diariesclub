-- 0130 — when admin adds a 2nd+ active perk to (stage, trait), existing
-- auto-picked grants revert to unchosen so customers can pick.
--
-- Founder's principle: admin changes the catalog → customers see the
-- updated state. If a kid auto-received Free brownie when it was the
-- only Explorer-Rafi option, and admin later adds Free hot chocolate
-- as a 2nd option, the kid should now be able to pick between the
-- two. Customer-picked grants are left alone — they made a deliberate
-- choice the customer shouldn't lose.
--
-- "Auto-picked" is identified by granted_at = chosen_at. Both columns
-- are set to the same now() in _grant_stage_perk_slot's auto-pick
-- INSERT, so they match to microsecond precision. Customer picks via
-- stage_perk_pick UPDATE chosen_at later, so the timestamps diverge.

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
  v_backfilled_count INTEGER := 0;
  v_auto_reverted_count INTEGER := 0;
  v_active_count_now INTEGER := 0;
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

  IF p_stage <> 'welcome' AND COALESCE(p_is_active, true) = true THEN
    v_backfilled_count := _backfill_stage_perk_grants(p_stage, p_trait);

    SELECT count(*) INTO v_active_count_now
      FROM stage_perks
     WHERE stage = p_stage AND trait = p_trait AND is_active = true;

    IF v_active_count_now >= 2 THEN
      UPDATE stage_perk_grants SET
        perk_id    = NULL,
        code       = NULL,
        chosen_at  = NULL,
        expires_at = NULL
      WHERE stage = p_stage
        AND trait = p_trait
        AND redeemed_at IS NULL
        AND perk_id IS NOT NULL
        AND chosen_at IS NOT NULL
        AND granted_at = chosen_at;
      GET DIAGNOSTICS v_auto_reverted_count = ROW_COUNT;
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
      'reverted_unredeemed_grants', v_reverted_count,
      'backfilled_grants', v_backfilled_count,
      'auto_picks_opened_to_pick', v_auto_reverted_count
    )
  );

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_upsert(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;
