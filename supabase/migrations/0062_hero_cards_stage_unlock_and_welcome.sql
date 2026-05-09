-- 0062_hero_cards_stage_unlock_and_welcome.sql
--
-- "Be the Hero" Layer 2 schema + auto-grant on stage cross.
--
-- Per hero, 10 cards total: 6 stage cards (auto-unlocked by XP threshold
-- crosses, including a brand-new 'welcome' stage at signup) + 4 surprise
-- cards (manually granted by admin or staff).
--
-- This migration:
--   1. Adds 'welcome' to the children.stage_* CHECK constraints + sets
--      it as the default for newly created children.
--   2. Adds unlock_method (enum) + unlock_stage to hero_card_definitions.
--   3. Migrates existing rows: birthday-exclusive → 'birthday', else
--      stays 'random_drop'. Founder re-tags in admin web after.
--   4. Rewrites xp_credit_with_split so any stage transition (including
--      the welcome→seedling first-XP flip) auto-grants matching stage
--      cards to the child's collection. Idempotent thanks to the
--      hero_card_collection UNIQUE(child_id, card_id) constraint.
--
-- Backfill of existing kids' stage cards happens in 0063. After that
-- migration, kids like Gaddam (Rafi 511 XP, Champion stage) instantly
-- see all 4 of their entitled stage cards unlock.

-- ---------------------------------------------------------------------
-- 1. Stage enum widening + default change
-- ---------------------------------------------------------------------
ALTER TABLE children DROP CONSTRAINT IF EXISTS children_stage_rafi_check;
ALTER TABLE children ADD CONSTRAINT children_stage_rafi_check
  CHECK (stage_rafi IN ('welcome','seedling','explorer','adventurer','champion','legend'));

ALTER TABLE children DROP CONSTRAINT IF EXISTS children_stage_ellie_check;
ALTER TABLE children ADD CONSTRAINT children_stage_ellie_check
  CHECK (stage_ellie IN ('welcome','seedling','explorer','adventurer','champion','legend'));

ALTER TABLE children DROP CONSTRAINT IF EXISTS children_stage_gerry_check;
ALTER TABLE children ADD CONSTRAINT children_stage_gerry_check
  CHECK (stage_gerry IN ('welcome','seedling','explorer','adventurer','champion','legend'));

ALTER TABLE children DROP CONSTRAINT IF EXISTS children_stage_zena_check;
ALTER TABLE children ADD CONSTRAINT children_stage_zena_check
  CHECK (stage_zena IN ('welcome','seedling','explorer','adventurer','champion','legend'));

ALTER TABLE children ALTER COLUMN stage_rafi  SET DEFAULT 'welcome';
ALTER TABLE children ALTER COLUMN stage_ellie SET DEFAULT 'welcome';
ALTER TABLE children ALTER COLUMN stage_gerry SET DEFAULT 'welcome';
ALTER TABLE children ALTER COLUMN stage_zena  SET DEFAULT 'welcome';

-- ---------------------------------------------------------------------
-- 2. unlock_method + unlock_stage on hero_card_definitions
-- ---------------------------------------------------------------------
ALTER TABLE hero_card_definitions
  ADD COLUMN IF NOT EXISTS unlock_method TEXT NOT NULL DEFAULT 'random_drop'
    CHECK (unlock_method IN ('stage','surprise','birthday','random_drop')),
  ADD COLUMN IF NOT EXISTS unlock_stage TEXT
    CHECK (unlock_stage IS NULL OR unlock_stage IN
      ('welcome','seedling','explorer','adventurer','champion','legend'));

-- Backfill: birthday-exclusive cards → 'birthday' method.
UPDATE hero_card_definitions
   SET unlock_method = 'birthday'
 WHERE is_birthday_exclusive = true
   AND unlock_method = 'random_drop';

CREATE INDEX IF NOT EXISTS idx_hero_card_defs_method_hero_stage
  ON hero_card_definitions(unlock_method, hero, unlock_stage)
  WHERE is_active = true;

-- ---------------------------------------------------------------------
-- 3. xp_credit_with_split — welcome handling + auto-grant stage cards
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION xp_credit_with_split(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_event_type TEXT,
  p_xp_rafi  INTEGER DEFAULT 0,
  p_xp_ellie INTEGER DEFAULT 0,
  p_xp_gerry INTEGER DEFAULT 0,
  p_xp_zena  INTEGER DEFAULT 0,
  p_reference_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_overall_thresholds JSONB;
  v_trait_thresholds   JSONB;
  v_new_total INTEGER;
  v_new_level INTEGER := 1;
  v_new_overall_stage TEXT;
  v_old_stages JSONB;
  v_new_stages JSONB := '{}'::JSONB;
  v_transitions JSONB := '[]'::JSONB;
  v_granted_cards JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_card_row RECORD;
  i INTEGER;
BEGIN
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds   := v_config.stage_thresholds_per_trait;

  SELECT * INTO v_child FROM children WHERE id = p_child_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  v_old_stages := jsonb_build_object(
    'rafi',  v_child.stage_rafi,  'ellie', v_child.stage_ellie,
    'gerry', v_child.stage_gerry, 'zena',  v_child.stage_zena
  );

  UPDATE children SET
    xp_rafi  = xp_rafi  + p_xp_rafi,
    xp_ellie = xp_ellie + p_xp_ellie,
    xp_gerry = xp_gerry + p_xp_gerry,
    xp_zena  = xp_zena  + p_xp_zena
  WHERE id = p_child_id RETURNING * INTO v_child;

  -- Per-trait stage recompute. Welcome is a pre-XP state: 0 XP keeps
  -- the kid at 'welcome' (they just signed up). Any XP > 0 jumps them
  -- into the threshold-derived stage (seedling onward).
  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;

    IF v_trait_xp = 0 THEN
      v_new_stage := 'welcome';
    ELSE
      v_new_stage := 'seedling';
      FOR i IN 0..(jsonb_array_length(v_trait_thresholds) - 1) LOOP
        IF v_trait_xp >= (v_trait_thresholds->>i)::INTEGER THEN
          v_new_stage := CASE i
            WHEN 0 THEN 'seedling'  WHEN 1 THEN 'explorer'
            WHEN 2 THEN 'adventurer' WHEN 3 THEN 'champion'
            ELSE 'legend'
          END;
        END IF;
      END LOOP;
    END IF;

    v_new_stages := v_new_stages || jsonb_build_object(v_trait, v_new_stage);
    v_old_stage := v_old_stages->>v_trait;

    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_array(
        jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage)
      );

      -- Auto-grant any stage cards tied to this hero × stage.
      -- UNIQUE(child_id, card_id) means dedup is automatic.
      FOR v_card_row IN
        SELECT id, name FROM hero_card_definitions
         WHERE unlock_method = 'stage'
           AND hero = v_trait
           AND unlock_stage = v_new_stage
           AND is_active = true
      LOOP
        INSERT INTO hero_card_collection(child_id, card_id)
        VALUES (p_child_id, v_card_row.id)
        ON CONFLICT (child_id, card_id) DO NOTHING;

        v_granted_cards := v_granted_cards || jsonb_build_array(
          jsonb_build_object(
            'card_id',   v_card_row.id,
            'name',      v_card_row.name,
            'hero',      v_trait,
            'stage',     v_new_stage
          )
        );

        INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
        VALUES (
          p_family_id, 'hero_card_received',
          'New hero card unlocked!',
          v_child.name || ' just earned ' || v_card_row.name || '.',
          '/adventure', p_child_id
        );
      END LOOP;
    END IF;
  END LOOP;

  v_new_total := v_child.xp_rafi + v_child.xp_ellie + v_child.xp_gerry + v_child.xp_zena;
  FOR i IN 0..(jsonb_array_length(v_overall_thresholds) - 1) LOOP
    IF v_new_total >= (v_overall_thresholds->>i)::INTEGER THEN
      v_new_level := i + 1;
    END IF;
  END LOOP;

  v_new_overall_stage := CASE
    WHEN v_new_level <= 3  THEN 'seedling'
    WHEN v_new_level <= 6  THEN 'explorer'
    WHEN v_new_level <= 12 THEN 'adventurer'
    WHEN v_new_level <= 18 THEN 'champion'
    ELSE 'legend'
  END;

  UPDATE children SET
    stage_rafi  = v_new_stages->>'rafi',
    stage_ellie = v_new_stages->>'ellie',
    stage_gerry = v_new_stages->>'gerry',
    stage_zena  = v_new_stages->>'zena',
    total_xp = v_new_total,
    current_level = v_new_level,
    current_overall_stage = v_new_overall_stage
  WHERE id = p_child_id;

  INSERT INTO xp_events(
    child_id, family_id, venue_id, event_type,
    xp_rafi, xp_ellie, xp_gerry, xp_zena,
    reference_id, metadata
  ) VALUES (
    p_child_id, p_family_id, p_venue_id, p_event_type,
    p_xp_rafi, p_xp_ellie, p_xp_gerry, p_xp_zena,
    p_reference_id,
    p_metadata || jsonb_build_object(
      'stage_transitions', v_transitions,
      'cards_granted', v_granted_cards
    )
  );

  IF jsonb_array_length(v_transitions) > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      v_child.name || ' just leveled up!',
      'See the new look in their adventure tab.',
      '/adventure', p_child_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_total_xp', v_new_total,
    'new_level', v_new_level,
    'new_overall_stage', v_new_overall_stage,
    'new_stages', v_new_stages,
    'transitions', v_transitions,
    'cards_granted', v_granted_cards
  );
END $$;
