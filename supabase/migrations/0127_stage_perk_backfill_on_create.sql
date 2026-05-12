-- 0127 — backfill grants when admin creates (or re-activates) a perk.
--
-- Without this, the engine only grants perks on stage TRANSITIONS. A
-- kid who's already at Seedling-Rafi when admin first creates the
-- Seedling-Rafi sticker would never get it — they already crossed the
-- threshold. With backfill, the new perk retroactively grants for any
-- kid currently at or past that stage who has no unredeemed grant for
-- that (stage, trait).
--
-- Kids who already have an unredeemed grant for (stage, trait) are
-- skipped so existing earned perks stay stable when admin adds a
-- second option later.

CREATE OR REPLACE FUNCTION public._backfill_stage_perk_grants(
  p_stage TEXT,
  p_trait TEXT
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child RECORD;
  v_child_stage TEXT;
  v_stage_order TEXT[] := ARRAY['welcome','seedling','explorer','adventurer','champion','legend'];
  v_perk_idx INTEGER := array_position(v_stage_order, p_stage);
  v_child_idx INTEGER;
  v_count INTEGER := 0;
  v_venue_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  IF p_stage = 'welcome' THEN RETURN 0; END IF;
  IF p_trait NOT IN ('rafi','ellie','gerry','zena') THEN RETURN 0; END IF;

  FOR v_child IN
    SELECT id, family_id, stage_rafi, stage_ellie, stage_gerry, stage_zena
    FROM children
  LOOP
    v_child_stage := CASE p_trait
      WHEN 'rafi'  THEN v_child.stage_rafi
      WHEN 'ellie' THEN v_child.stage_ellie
      WHEN 'gerry' THEN v_child.stage_gerry
      WHEN 'zena'  THEN v_child.stage_zena
    END;

    v_child_idx := array_position(v_stage_order, v_child_stage);

    IF v_child_idx IS NOT NULL AND v_child_idx >= v_perk_idx THEN
      IF NOT EXISTS (
        SELECT 1 FROM stage_perk_grants
         WHERE child_id = v_child.id
           AND stage = p_stage
           AND trait = p_trait
           AND redeemed_at IS NULL
      ) THEN
        PERFORM _grant_stage_perk_slot(
          v_child.id, v_child.family_id, v_venue_id, p_trait, p_stage
        );
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END $$;

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
  v_is_new BOOLEAN := false;
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
    v_is_new := true;
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
    IF v_is_new OR (v_was_active = false AND p_is_active = true) THEN
      v_backfilled_count :=
        _backfill_stage_perk_grants(p_stage, p_trait);
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
      'backfilled_grants', v_backfilled_count
    )
  );

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_upsert(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;
