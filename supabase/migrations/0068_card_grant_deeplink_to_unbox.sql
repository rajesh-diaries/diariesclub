-- 0068_card_grant_deeplink_to_unbox.sql
--
-- Notification taps for new hero cards now route to the unboxing
-- animation screen (/cards/unbox/:collectionId) instead of dropping
-- the customer on the Adventure tab.
--
-- Three call sites updated:
--   * xp_credit_with_split          stage card grants on transition
--   * _card_grant_surprise_inner    manual admin/staff surprise grants
--   * healthy_bite_distribute       random drops at counter
--
-- All three INSERT into hero_card_collection. To get the resulting
-- collection row id (whether the row is newly inserted or already
-- existed), use the ON CONFLICT DO UPDATE SET earned_at =
-- hero_card_collection.earned_at trick — RETURNING then fires in
-- both cases without changing data.
--
-- Notification deep_link template: '/cards/unbox/' || collection_id

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

    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_array(
        jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage)
      );

      FOR v_card_row IN
        SELECT id, name FROM hero_card_definitions
         WHERE unlock_method = 'stage'
           AND hero = v_trait
           AND unlock_stage = v_new_stage
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
            'hero', v_trait, 'stage', v_new_stage,
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

      FOR v_perk_row IN
        SELECT id, perk_label, validity_days
          FROM stage_perks
         WHERE stage = v_new_stage
           AND is_active = true
           AND (venue_id IS NULL OR venue_id = p_venue_id)
      LOOP
        v_perk_code := _generate_stage_perk_code();
        INSERT INTO stage_perk_grants(
          child_id, family_id, stage, trait, perk_id, code, expires_at
        ) VALUES (
          p_child_id, p_family_id, v_new_stage, v_trait, v_perk_row.id, v_perk_code,
          now() + make_interval(days => v_perk_row.validity_days)
        ) RETURNING id INTO v_perk_grant_id;

        v_granted_perks := v_granted_perks || jsonb_build_array(
          jsonb_build_object(
            'grant_id', v_perk_grant_id,
            'perk_id', v_perk_row.id,
            'label', v_perk_row.perk_label,
            'stage', v_new_stage,
            'trait', v_trait,
            'code', v_perk_code
          )
        );

        INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
        VALUES (
          p_family_id, 'stage_transition_revealed',
          'New perk unlocked! ' || v_perk_row.perk_label,
          v_child.name || ' just reached ' || v_new_stage ||
            '. Show code ' || v_perk_code || ' at the counter.',
          '/profile', p_child_id
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

CREATE OR REPLACE FUNCTION _card_grant_surprise_inner(
  p_child_id UUID,
  p_card_id  UUID,
  p_actor_id UUID,
  p_actor_type TEXT,
  p_note TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_child children%ROWTYPE;
  v_already_owned BOOLEAN;
  v_inserted BOOLEAN;
  v_collection_id UUID;
BEGIN
  SELECT * INTO v_card FROM hero_card_definitions WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'card_not_found'; END IF;
  IF NOT v_card.is_active THEN RAISE EXCEPTION 'card_inactive'; END IF;
  IF v_card.unlock_method <> 'surprise' THEN
    RAISE EXCEPTION 'not_a_surprise_card'
      USING DETAIL = format('unlock_method=%s', v_card.unlock_method);
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM hero_card_collection
     WHERE child_id = p_child_id AND card_id = p_card_id
  ) INTO v_already_owned;

  INSERT INTO hero_card_collection(child_id, card_id)
  VALUES (p_child_id, p_card_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = hero_card_collection.earned_at
  RETURNING id INTO v_collection_id;

  v_inserted := NOT v_already_owned;

  IF v_inserted THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_child.family_id, 'hero_card_received',
      'A surprise card!',
      v_child.name || ' just received ' || v_card.name || '.',
      '/cards/unbox/' || v_collection_id, p_child_id
    );

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
    VALUES (
      p_actor_id, p_actor_type, 'hero_card.grant_surprise', 'child', p_child_id,
      jsonb_build_object(
        'card_id', p_card_id,
        'card_name', v_card.name,
        'hero', v_card.hero,
        'collection_id', v_collection_id,
        'note', p_note
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'newly_granted', v_inserted,
    'card_id', p_card_id,
    'card_name', v_card.name,
    'hero', v_card.hero,
    'collection_id', v_collection_id
  );
END $$;

CREATE OR REPLACE FUNCTION healthy_bite_distribute(
  p_session_id UUID,
  p_child_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_is_rare BOOLEAN;
  v_collection_id UUID;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.healthy_bite_distributed THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  UPDATE sessions SET
    healthy_bite_earned = true,
    healthy_bite_distributed = true
  WHERE id = p_session_id;

  v_is_rare := random() <= 0.10;

  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare AND is_birthday_exclusive = false AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_cards_available';
  END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = hero_card_collection.earned_at
  RETURNING id INTO v_collection_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'hero_card_received',
    'New hero card!',
    CASE WHEN v_card.is_rare THEN 'A rare card just arrived in your collection.'
         ELSE 'Tap to add it to your collection.' END,
    '/cards/unbox/' || v_collection_id, p_child_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
          v_session.venue_id,
          jsonb_build_object('card_id', v_card.id, 'is_rare', v_card.is_rare,
                             'collection_id', v_collection_id));

  RETURN jsonb_build_object(
    'success', true,
    'card_id', v_card.id,
    'card_name', v_card.name,
    'is_rare', v_card.is_rare,
    'collection_id', v_collection_id
  );
END $$;
