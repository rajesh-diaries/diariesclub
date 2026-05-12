-- 0128 — stage-transition cinematic uses admin-uploaded hero card art.
--
-- xp_credit_with_split now embeds card_image_url in each transition
-- object so the client cinematic renders the same artwork that lives
-- in the kid's Adventure card collection. Single source of truth:
-- one upload in Admin → Hero cards = transition cinematic + card
-- collection + physical sticker print at the counter.
--
-- Falls back to a Phosphor icon client-side when image_url is NULL so
-- nothing breaks before admin uploads each (trait, stage) image.

CREATE OR REPLACE FUNCTION public.xp_credit_with_split(
  p_child_id     UUID,
  p_family_id    UUID,
  p_venue_id     UUID,
  p_event_type   TEXT,
  p_xp_rafi      INTEGER DEFAULT 0,
  p_xp_ellie     INTEGER DEFAULT 0,
  p_xp_gerry     INTEGER DEFAULT 0,
  p_xp_zena      INTEGER DEFAULT 0,
  p_reference_id UUID DEFAULT NULL,
  p_metadata     JSONB DEFAULT '{}'::jsonb
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
  v_collection_id UUID;
  v_perk_slot JSONB;
  v_card_image_url TEXT;
  i INTEGER;
  v_stage_order TEXT[] := ARRAY['welcome','seedling','explorer','adventurer','champion','legend'];
  v_old_idx INTEGER;
  v_new_idx INTEGER;
  v_step_idx INTEGER;
  v_step_stage TEXT;
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

    v_old_idx := array_position(v_stage_order, v_old_stage);
    v_new_idx := array_position(v_stage_order, v_new_stage);

    IF v_new_idx > v_old_idx THEN
      FOR v_step_idx IN (v_old_idx + 1)..v_new_idx LOOP
        v_step_stage := v_stage_order[v_step_idx];

        SELECT image_url INTO v_card_image_url
          FROM hero_card_definitions
         WHERE unlock_method = 'stage'
           AND hero = v_trait
           AND unlock_stage = v_step_stage
           AND is_active = true
         ORDER BY created_at
         LIMIT 1;

        v_transitions := v_transitions || jsonb_build_array(
          jsonb_build_object(
            'trait', v_trait,
            'from', v_stage_order[v_step_idx - 1],
            'to', v_step_stage,
            'card_image_url', v_card_image_url
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

          INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
          VALUES (
            p_family_id, 'hero_card_received',
            'New hero card unlocked!',
            v_child.name || ' just earned ' || v_card_row.name || '.',
            '/cards/unbox/' || v_collection_id, p_child_id
          );
        END LOOP;

        SELECT granted INTO v_perk_slot
          FROM _grant_stage_perk_slot(
            p_child_id, p_family_id, p_venue_id, v_trait, v_step_stage
          );

        IF NOT COALESCE((v_perk_slot->>'skipped')::BOOLEAN, false) THEN
          v_granted_perks := v_granted_perks || jsonb_build_array(v_perk_slot);

          IF (v_perk_slot->>'auto_picked')::BOOLEAN THEN
            INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
            VALUES (
              p_family_id, 'stage_transition_revealed',
              'New perk unlocked! ' || (v_perk_slot->>'label'),
              v_child.name || ' just reached ' || v_step_stage ||
                '. Show code ' || (v_perk_slot->>'code') || ' at the counter.',
              '/profile', p_child_id
            );
          ELSE
            INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
            VALUES (
              p_family_id, 'stage_transition_revealed',
              'Pick your ' || v_step_stage || ' reward',
              v_child.name || ' just reached ' || v_step_stage ||
                '. Tap to pick from ' || (v_perk_slot->>'options_count') ||
                ' rewards.',
              '/profile', p_child_id
            );
          END IF;
        END IF;
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
    'cards_granted', v_granted_cards,
    'perks_granted', v_granted_perks
  );
END $$;
