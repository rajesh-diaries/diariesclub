-- 0120 — stage_perks per character.
--
-- A perk is now scoped to (stage, trait). Welcome stage has trait = NULL
-- (character-agnostic, granted once at signup). All other stages require
-- a trait so a Rafi Seedling perk doesn't fire on Ellie's seedling
-- transition. Each (stage, trait) section should have 2+ active perks so
-- the customer gets the choose-your-reward picker at claim time.

ALTER TABLE stage_perks
  ADD COLUMN IF NOT EXISTS trait TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'stage_perks_trait_check'
  ) THEN
    ALTER TABLE stage_perks
      ADD CONSTRAINT stage_perks_trait_check
      CHECK (trait IS NULL OR trait IN ('rafi','ellie','gerry','zena'));
  END IF;
END $$;

-- _grant_stage_perk_slot now filters by (stage, trait).
-- Welcome → trait IS NULL; non-welcome → trait = p_trait. Legacy
-- trait-NULL non-welcome perks no longer grant; admin assigns a
-- character via the upsert RPC to revive them.

CREATE OR REPLACE FUNCTION public._grant_stage_perk_slot(
  p_child_id   UUID,
  p_family_id  UUID,
  p_venue_id   UUID,
  p_trait      TEXT,
  p_stage      TEXT,
  OUT granted  JSONB
) LANGUAGE plpgsql AS $$
DECLARE
  v_active_count INTEGER;
  v_perk         stage_perks%ROWTYPE;
  v_code         TEXT;
  v_grant_id     UUID;
BEGIN
  SELECT count(*) INTO v_active_count FROM stage_perks
   WHERE stage = p_stage AND is_active = true
     AND (venue_id IS NULL OR venue_id = p_venue_id)
     AND (
       (p_stage = 'welcome' AND trait IS NULL)
       OR (p_stage <> 'welcome' AND trait = p_trait)
     );

  IF v_active_count = 0 THEN
    granted := jsonb_build_object('skipped', true, 'reason', 'no_active_perks');
    RETURN;
  END IF;

  IF v_active_count = 1 THEN
    SELECT * INTO v_perk FROM stage_perks
     WHERE stage = p_stage AND is_active = true
       AND (venue_id IS NULL OR venue_id = p_venue_id)
       AND (
         (p_stage = 'welcome' AND trait IS NULL)
         OR (p_stage <> 'welcome' AND trait = p_trait)
       );
    v_code := _generate_stage_perk_code();
    INSERT INTO stage_perk_grants(
      child_id, family_id, stage, trait, perk_id, code,
      chosen_at, expires_at
    ) VALUES (
      p_child_id, p_family_id, p_stage, p_trait, v_perk.id, v_code,
      now(), now() + make_interval(days => v_perk.validity_days)
    ) RETURNING id INTO v_grant_id;
    granted := jsonb_build_object(
      'grant_id', v_grant_id, 'auto_picked', true,
      'perk_id', v_perk.id, 'label', v_perk.perk_label, 'code', v_code,
      'stage', p_stage, 'trait', p_trait
    );
    RETURN;
  END IF;

  INSERT INTO stage_perk_grants(
    child_id, family_id, stage, trait, perk_id, code, expires_at
  ) VALUES (
    p_child_id, p_family_id, p_stage, p_trait, NULL, NULL, NULL
  ) RETURNING id INTO v_grant_id;

  granted := jsonb_build_object(
    'grant_id', v_grant_id, 'auto_picked', false,
    'options_count', v_active_count,
    'stage', p_stage, 'trait', p_trait
  );
END $$;

-- stage_perk_pick now validates the picked perk's trait matches the
-- grant's trait (welcome → both NULL; non-welcome → both equal).

CREATE OR REPLACE FUNCTION public.stage_perk_pick(
  p_grant_id UUID,
  p_perk_id  UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_grant stage_perk_grants%ROWTYPE;
  v_perk  stage_perks%ROWTYPE;
  v_code  TEXT;
BEGIN
  SELECT * INTO v_grant FROM stage_perk_grants
   WHERE id = p_grant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'grant_not_found'; END IF;
  IF v_grant.family_id <> auth_family_id() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;
  IF v_grant.perk_id IS NOT NULL THEN
    RAISE EXCEPTION 'already_picked';
  END IF;

  SELECT * INTO v_perk FROM stage_perks
   WHERE id = p_perk_id
     AND stage = v_grant.stage
     AND is_active = true
     AND (
       (v_grant.stage = 'welcome' AND trait IS NULL)
       OR (v_grant.stage <> 'welcome' AND trait = v_grant.trait)
     );
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_perk_for_stage_trait'; END IF;

  v_code := _generate_stage_perk_code();
  UPDATE stage_perk_grants SET
    perk_id    = v_perk.id,
    code       = v_code,
    chosen_at  = now(),
    expires_at = now() + make_interval(days => v_perk.validity_days)
  WHERE id = p_grant_id;

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'label', v_perk.perk_label,
    'expires_at', now() + make_interval(days => v_perk.validity_days)
  );
END $$;

GRANT EXECUTE ON FUNCTION public.stage_perk_pick(UUID, UUID)
  TO authenticated;

-- admin_stage_perk_upsert: new signature with p_trait. Welcome stage
-- must have trait NULL; other stages require a trait.

DROP FUNCTION IF EXISTS public.admin_stage_perk_upsert(
  uuid, uuid, text, text, text, integer, boolean
);

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
  v_id UUID;
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

    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'stage_perk.create' ELSE 'stage_perk.update' END,
    'stage_perk', v_id,
    jsonb_build_object(
      'stage', p_stage, 'trait', p_trait,
      'perk_label', p_perk_label, 'is_active', p_is_active
    )
  );

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_upsert(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, BOOLEAN
) TO authenticated;
