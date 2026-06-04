-- ===========================================================================
--  Migration 0171 — Batch XP/card/perk notifications to stop push spam
--
--  Problem: xp_credit_with_split (0075) INSERTs one notification row per
--  card grant and one per perk grant inside nested trait/stage loops.
--  On a kid's first session all 4 traits typically jump welcome→seedling,
--  producing 8-14 simultaneous push notifications — treated as spam by
--  parents and flagged by App Review (2.1a Performance).
--
--  Fix: collect card + perk lists during the loops, then emit at most ONE
--  summary notification for cards and ONE for perks after the loops finish.
--  The existing final "leveled up" notification is retained.
--
--  Types preserved:
--    hero_card_received        — single summary (was N individual)
--    stage_transition_revealed — single summary for perks (was N individual)
--    stage_transition_revealed — retained for the overall level-up
-- ===========================================================================

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
  v_granted_perks JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_card_row RECORD;
  v_perk_row RECORD;
  v_perk_code TEXT;
  v_perk_grant_id UUID;
  v_collection_id UUID;
  i INTEGER;
  -- Stage iteration helpers.
  v_stage_order TEXT[] := ARRAY['welcome','seedling','explorer','adventurer','champion','legend'];
  v_old_idx INTEGER;
  v_new_idx INTEGER;
  v_step_idx INTEGER;
  v_step_stage TEXT;
  -- Batched notification summaries.
  v_card_count INTEGER := 0;
  v_card_names TEXT := '';
  v_perk_count INTEGER := 0;
  v_perk_names TEXT := '';
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

    -- Resolve indices so we can iterate every stage between old and new.
    v_old_idx := array_position(v_stage_order, v_old_stage);
    v_new_idx := array_position(v_stage_order, v_new_stage);

    IF v_new_idx > v_old_idx THEN
      FOR v_step_idx IN (v_old_idx + 1)..v_new_idx LOOP
        v_step_stage := v_stage_order[v_step_idx];

        v_transitions := v_transitions || jsonb_build_array(
          jsonb_build_object(
            'trait', v_trait,
            'from', v_stage_order[v_step_idx - 1],
            'to', v_step_stage
          )
        );

        FOR v_card_row IN
          SELECT id, name FROM hero_card_definitions
           WHERE unlock_method = 'stage'
             AND hero = v_trait
             AND unlock_stage = v_step_stage
             AND is_active = true
        LOOP
          INSERT INTO hero_card_collection(child_id, card_id)
          VALUES (p_child_id, v_card_row.id)
          ON CONFLICT (child_id, card_id) DO UPDATE
            SET earned_at = hero_card_collection.earned_at
          RETURNING id INTO v_collection_id;

          v_granted_cards := v_granted_cards || jsonb_build_array(
            jsonb_build_object(
              'card_id', v_card_row.id, 'name', v_card_row.name,
              'hero', v_trait, 'stage', v_step_stage,
              'collection_id', v_collection_id
            )
          );

          -- Batch: count + collect names for summary notification.
          v_card_count := v_card_count + 1;
          IF v_card_names <> '' THEN v_card_names := v_card_names || ', '; END IF;
          v_card_names := v_card_names || v_card_row.name;
        END LOOP;

        FOR v_perk_row IN
          SELECT id, perk_label, validity_days
            FROM stage_perks
           WHERE stage = v_step_stage
             AND is_active = true
             AND (venue_id IS NULL OR venue_id = p_venue_id)
        LOOP
          v_perk_code := _generate_stage_perk_code();
          INSERT INTO stage_perk_grants(
            child_id, family_id, stage, trait, perk_id, code, expires_at
          ) VALUES (
            p_child_id, p_family_id, v_step_stage, v_trait, v_perk_row.id, v_perk_code,
            now() + make_interval(days => v_perk_row.validity_days)
          ) RETURNING id INTO v_perk_grant_id;

          v_granted_perks := v_granted_perks || jsonb_build_array(
            jsonb_build_object(
              'grant_id', v_perk_grant_id,
              'perk_id', v_perk_row.id,
              'label', v_perk_row.perk_label,
              'stage', v_step_stage,
              'trait', v_trait,
              'code', v_perk_code
            )
          );

          -- Batch: count + collect names for summary notification.
          v_perk_count := v_perk_count + 1;
          IF v_perk_names <> '' THEN v_perk_names := v_perk_names || ', '; END IF;
          v_perk_names := v_perk_names || v_perk_row.perk_label;
        END LOOP;
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
      'cards_granted', v_granted_cards,
      'perks_granted', v_granted_perks
    )
  );

  -- Emit one combined cards + perks summary notification.
  IF v_card_count > 0 OR v_perk_count > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'hero_card_received',
      CASE
        WHEN v_card_count > 0 AND v_perk_count > 0 THEN
          v_card_count || ' card' || CASE WHEN v_card_count = 1 THEN '' ELSE 's' END ||
          ' & ' || v_perk_count || ' perk' || CASE WHEN v_perk_count = 1 THEN '' ELSE 's' END ||
          ' unlocked!'
        WHEN v_card_count > 0 THEN
          v_card_count || ' card' || CASE WHEN v_card_count = 1 THEN '' ELSE 's' END || ' unlocked!'
        ELSE
          v_perk_count || ' perk' || CASE WHEN v_perk_count = 1 THEN '' ELSE 's' END || ' unlocked!'
      END,
      CASE
        WHEN v_card_count > 0 AND v_perk_count > 0 THEN
          v_child.name || ' earned ' || v_card_names || ' and unlocked ' || v_perk_names || '. Tap to see them all!'
        WHEN v_card_count > 0 THEN
          v_child.name || ' just earned ' || v_card_names || '. Tap to unbox!'
        ELSE
          v_child.name || ' reached new stages and unlocked: ' || v_perk_names || '.'
      END,
      '/adventure', p_child_id
    );
  END IF;

  -- Retain the overall level-up notification as a separate "hero moment".
  IF jsonb_array_length(v_transitions) > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      v_child.name || ' just leveled up! 🎉',
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
    'cards_granted', v_granted_cards,
    'perks_granted', v_granted_perks
  );
END $$;
