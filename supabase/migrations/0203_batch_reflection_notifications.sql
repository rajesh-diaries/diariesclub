-- ===========================================================================
--  Migration 0203 — Batch all reflection-driven notifications into one push
--
--  Problem: reflecting a single session can fire many simultaneous pushes:
--    * xp_credit_with_split cards+perks summary
--    * xp_credit_with_split level-up summary
--    * up to 4 hero-quest completion notifications
--    * each quest also calls xp_credit_with_split again
--  Parents see 6-10+ pushes at once (spam).
--
--  Fix:
--    1. Add a transaction-local suppress flag
--       (`app.suppress_notifications = 'true'`).
--    2. Wrap notification inserts in xp_credit_with_split and
--       _quest_progress_check so they skip while the flag is set.
--    3. Redefine reflection_submit to set the flag, run all XP/quest logic,
--       then emit exactly ONE combined notification at the end.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Allow a new notification type for the combined reflection summary.
-- ---------------------------------------------------------------------------
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (
  type = ANY (ARRAY[
    'session_started','hydration_nudge','healthy_bite_earned',
    'grace_started','extend_nudge','session_closed','recap_ready',
    'reflection_prompt','reflection_auto_split','reflection_summary',
    'order_confirmed','order_ready',
    'hero_card_received','stage_transition_imminent',
    'stage_transition_revealed','level_up',
    'birthday_d_minus_90','birthday_d_minus_60','birthday_d_minus_30',
    'birthday_d_minus_14','birthday_d_minus_7','birthday_d_minus_3',
    'birthday_d_minus_1','birthday_d_zero','birthday_d_plus_1',
    'birthday_album_ready','birthday_hero_progression_trigger',
    'birthday_wish','referral_reward','first_referral_brave_boost',
    'wallet_topup','wallet_low_balance','visit_milestone',
    'streak_milestone','refund_processed','reactivation_welcome',
    'workshop_reminder','workshop_cancelled',
    'workshop_registered','workshop_starting_soon','workshop_attended',
    'workshop_started','workshop_thanks',
    'birthday_lead_d_minus_30','birthday_lead_d_minus_15',
    'pre_booking_reminder','pre_booking_expired','while_you_wait_food',
    'announcement_published','hero_within_unlocked'
  ])
);

-- ---------------------------------------------------------------------------
-- 2. xp_credit_with_split — respect the suppress flag for its two
--    notification inserts.  Everything else (XP, cards, perks, stages) runs
--    unchanged.
-- ---------------------------------------------------------------------------
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
  v_stage_order TEXT[] := ARRAY['welcome','seedling','explorer','adventurer','champion','legend'];
  v_old_idx INTEGER;
  v_new_idx INTEGER;
  v_step_idx INTEGER;
  v_step_stage TEXT;
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

  -- Batched cards + perks summary (unless we're inside reflection_submit).
  IF current_setting('app.suppress_notifications', true) IS DISTINCT FROM 'true' THEN
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
  END IF;

  -- Overall level-up notification (unless suppressed).
  IF current_setting('app.suppress_notifications', true) IS DISTINCT FROM 'true' THEN
    IF jsonb_array_length(v_transitions) > 0 THEN
      INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
      VALUES (
        p_family_id, 'stage_transition_revealed',
        v_child.name || ' just leveled up! 🎉',
        'See the new look in their adventure tab.',
        '/adventure', p_child_id
      );
    END IF;
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

-- ---------------------------------------------------------------------------
-- 3. _quest_progress_check — suppress the per-quest completion notification
--    while the reflection batch flag is active.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _quest_progress_check(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_hero TEXT,
  p_event_type TEXT,
  p_event_data JSONB,
  p_reference_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_week DATE := _ist_week_start();
  v_quest_id UUID;
  v_def hero_quest_definitions%ROWTYPE;
  v_predicate_ok BOOLEAN := true;
  v_pred_key TEXT;
  v_pred_val JSONB;
  v_existing hero_quest_progress%ROWTYPE;
BEGIN
  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'invalid_hero');
  END IF;

  SELECT
    CASE p_hero
      WHEN 'rafi'  THEN quest_id_rafi
      WHEN 'ellie' THEN quest_id_ellie
      WHEN 'gerry' THEN quest_id_gerry
      WHEN 'zena'  THEN quest_id_zena
    END
  INTO v_quest_id
  FROM hero_quest_weeks
  WHERE week_start_date = v_week;

  IF v_quest_id IS NULL THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'no_quest_scheduled');
  END IF;

  SELECT * INTO v_def FROM hero_quest_definitions WHERE id = v_quest_id;
  IF NOT FOUND OR NOT v_def.is_active THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'quest_inactive');
  END IF;

  IF v_def.completion_event_type <> p_event_type THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'event_type_mismatch');
  END IF;

  FOR v_pred_key, v_pred_val IN
    SELECT * FROM jsonb_each(v_def.completion_predicate)
  LOOP
    IF v_pred_key LIKE 'min_%' THEN
      DECLARE
        v_field TEXT := substring(v_pred_key from 5);
        v_event_num NUMERIC;
        v_pred_num NUMERIC;
      BEGIN
        v_event_num := (p_event_data->>v_field)::NUMERIC;
        v_pred_num  := v_pred_val::TEXT::NUMERIC;
        IF v_event_num IS NULL OR v_event_num < v_pred_num THEN
          v_predicate_ok := false;
          EXIT;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_predicate_ok := false;
        EXIT;
      END;
    ELSE
      IF (p_event_data->v_pred_key) IS NULL
         OR (p_event_data->v_pred_key) <> v_pred_val THEN
        v_predicate_ok := false;
        EXIT;
      END IF;
    END IF;
  END LOOP;

  IF NOT v_predicate_ok THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'predicate_unsatisfied');
  END IF;

  SELECT * INTO v_existing FROM hero_quest_progress
  WHERE child_id = p_child_id
    AND week_start_date = v_week
    AND hero = p_hero;

  IF FOUND AND v_existing.completed_at IS NOT NULL THEN
    RETURN jsonb_build_object('matched', false, 'reason', 'already_completed');
  END IF;

  INSERT INTO hero_quest_progress(
    child_id, family_id, week_start_date, hero, quest_id,
    completed_at, completion_reference_id, xp_awarded
  ) VALUES (
    p_child_id, p_family_id, v_week, p_hero, v_quest_id,
    now(), p_reference_id, v_def.xp_bonus
  )
  ON CONFLICT (child_id, week_start_date, hero) DO UPDATE
    SET completed_at = now(),
        completion_reference_id = EXCLUDED.completion_reference_id,
        xp_awarded = EXCLUDED.xp_awarded;

  PERFORM xp_credit_with_split(
    p_child_id, p_family_id, p_venue_id,
    'manual_admin',
    CASE WHEN p_hero = 'rafi'  THEN v_def.xp_bonus ELSE 0 END,
    CASE WHEN p_hero = 'ellie' THEN v_def.xp_bonus ELSE 0 END,
    CASE WHEN p_hero = 'gerry' THEN v_def.xp_bonus ELSE 0 END,
    CASE WHEN p_hero = 'zena'  THEN v_def.xp_bonus ELSE 0 END,
    p_reference_id,
    jsonb_build_object('quest_id', v_quest_id, 'quest_title', v_def.title)
  );

  -- Per-quest completion push (suppressed during reflection batch).
  IF current_setting('app.suppress_notifications', true) IS DISTINCT FROM 'true' THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      'Quest complete: ' || v_def.title,
      '+' || v_def.xp_bonus || ' XP for ' || initcap(p_hero) || '.',
      '/adventure', p_child_id
    );
  END IF;

  RETURN jsonb_build_object(
    'matched', true,
    'quest_id', v_quest_id,
    'title', v_def.title,
    'xp_awarded', v_def.xp_bonus,
    'hero', p_hero
  );
END $$;

-- ---------------------------------------------------------------------------
-- 4. reflection_submit — suppress all internal notifications, then emit one
--    combined summary at the end.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reflection_submit(
  p_session_id     UUID,
  p_moment_tags    TEXT[],
  p_custom_moments JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_recap   hero_recaps%ROWTYPE;
  v_pool INTEGER;
  v_weights JSONB := '{"rafi":0,"ellie":0,"gerry":0,"zena":0}'::JSONB;
  v_total_weight NUMERIC := 0;
  v_tag TEXT;
  v_moment reflection_moments%ROWTYPE;
  v_custom JSONB;
  v_custom_trait TEXT;
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena  INTEGER := 0;
  v_xp_result JSONB;
  v_all_tags TEXT[];
  v_child_name TEXT;
  v_quest_titles TEXT[];
  v_quest_count INTEGER;
  v_card_count INTEGER;
  v_perk_count INTEGER;
  v_transition_count INTEGER;
  v_summary_body TEXT;
  v_summary_parts TEXT[];
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

  PERFORM assert_caller_authority(v_session.family_id, NULL);

  SELECT * INTO v_recap FROM hero_recaps WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'recap_not_ready'; END IF;
  IF v_recap.reflection_status <> 'pending' THEN RAISE EXCEPTION 'reflection_already_done'; END IF;
  IF v_recap.reflection_deadline IS NOT NULL AND now() > v_recap.reflection_deadline THEN
    RAISE EXCEPTION 'reflection_window_expired';
  END IF;

  v_pool := v_recap.total_xp_pool;

  FOREACH v_tag IN ARRAY p_moment_tags LOOP
    SELECT * INTO v_moment FROM reflection_moments WHERE tag = v_tag AND is_active;
    IF FOUND THEN
      v_weights := jsonb_set(
        v_weights,
        ARRAY[v_moment.primary_trait],
        to_jsonb((v_weights->>v_moment.primary_trait)::NUMERIC + v_moment.xp_weight)
      );
      v_total_weight := v_total_weight + v_moment.xp_weight;
    END IF;
  END LOOP;

  IF p_custom_moments IS NOT NULL THEN
    FOR v_custom IN SELECT * FROM jsonb_array_elements(p_custom_moments) LOOP
      v_custom_trait := v_custom->>'trait';
      IF v_custom_trait IN ('rafi','ellie','gerry','zena') THEN
        v_weights := jsonb_set(
          v_weights,
          ARRAY[v_custom_trait],
          to_jsonb((v_weights->>v_custom_trait)::NUMERIC + 1.0)
        );
        v_total_weight := v_total_weight + 1.0;
      END IF;
    END LOOP;
  END IF;

  IF v_total_weight = 0 THEN
    v_xp_rafi  := v_pool / 4;
    v_xp_ellie := v_pool / 4;
    v_xp_gerry := v_pool / 4;
    v_xp_zena  := v_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  ELSE
    v_xp_rafi  := FLOOR(v_pool * (v_weights->>'rafi') ::NUMERIC / v_total_weight)::INTEGER;
    v_xp_ellie := FLOOR(v_pool * (v_weights->>'ellie')::NUMERIC / v_total_weight)::INTEGER;
    v_xp_gerry := FLOOR(v_pool * (v_weights->>'gerry')::NUMERIC / v_total_weight)::INTEGER;
    v_xp_zena  := v_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  END IF;

  -- Suppress every notification insert that happens inside this transaction
  -- (initial XP credit + quest completions + their XP credits).
  PERFORM set_config('app.suppress_notifications', 'true', true);

  v_xp_result := xp_credit_with_split(
    v_session.child_id, v_session.family_id, v_session.venue_id,
    'reflection_split',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    p_session_id,
    jsonb_build_object(
      'moment_tags', to_jsonb(p_moment_tags),
      'custom_moments', p_custom_moments
    )
  );

  v_all_tags := COALESCE(p_moment_tags, ARRAY[]::TEXT[]);
  IF p_custom_moments IS NOT NULL THEN
    FOR v_custom IN SELECT * FROM jsonb_array_elements(p_custom_moments) LOOP
      v_all_tags := array_append(
        v_all_tags,
        'custom:' || (v_custom->>'trait') || ':' || (v_custom->>'text')
      );
    END LOOP;
  END IF;

  UPDATE hero_recaps SET
    reflection_status = 'reflected',
    reflection_at = now(),
    moment_tags = v_all_tags
  WHERE session_id = p_session_id;

  -- Re-enable notifications so the single summary below actually dispatches.
  PERFORM set_config('app.suppress_notifications', 'false', true);

  -- Collect what happened so we can build one combined message.
  v_card_count := COALESCE(jsonb_array_length(v_xp_result->'cards_granted'), 0);
  v_perk_count := COALESCE(jsonb_array_length(v_xp_result->'perks_granted'), 0);
  v_transition_count := COALESCE(jsonb_array_length(v_xp_result->'transitions'), 0);

  SELECT array_agg(hqd.title ORDER BY hqp.hero) INTO v_quest_titles
  FROM hero_quest_progress hqp
  JOIN hero_quest_definitions hqd ON hqd.id = hqp.quest_id
  WHERE hqp.completion_reference_id = v_recap.id;

  v_quest_count := COALESCE(array_length(v_quest_titles, 1), 0);

  v_summary_parts := ARRAY[]::TEXT[];
  v_summary_parts := array_append(v_summary_parts, '+' || v_pool || ' XP shared across heroes');
  IF v_transition_count > 0 THEN
    v_summary_parts := array_append(v_summary_parts,
      'Levelled up to ' || initcap(v_xp_result->>'new_overall_stage'));
  END IF;
  IF v_card_count > 0 THEN
    v_summary_parts := array_append(v_summary_parts,
      v_card_count || ' card' || CASE WHEN v_card_count = 1 THEN '' ELSE 's' END || ' unlocked');
  END IF;
  IF v_perk_count > 0 THEN
    v_summary_parts := array_append(v_summary_parts,
      v_perk_count || ' perk' || CASE WHEN v_perk_count = 1 THEN '' ELSE 's' END || ' unlocked');
  END IF;
  IF v_quest_count > 0 THEN
    v_summary_parts := array_append(v_summary_parts,
      v_quest_count || ' quest' || CASE WHEN v_quest_count = 1 THEN '' ELSE 's' END || ' completed');
  END IF;

  v_summary_body := COALESCE(v_child_name, 'Your kid') || '''s reflection is in — ' ||
                    array_to_string(v_summary_parts, ', ') || '. Tap to celebrate!';

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id,
    'reflection_summary',
    COALESCE(v_child_name, 'Your kid') || ' reflected! 🌟',
    v_summary_body,
    '/adventure',
    v_session.child_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_session.family_id, 'customer',
    'reflection.submit', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object(
      'split', jsonb_build_object(
        'rafi', v_xp_rafi, 'ellie', v_xp_ellie,
        'gerry', v_xp_gerry, 'zena', v_xp_zena
      ),
      'moment_tags', to_jsonb(p_moment_tags),
      'custom_moments', p_custom_moments,
      'summary_parts', to_jsonb(v_summary_parts)
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'split', jsonb_build_object(
      'rafi', v_xp_rafi, 'ellie', v_xp_ellie,
      'gerry', v_xp_gerry, 'zena', v_xp_zena
    ),
    'transitions', COALESCE(v_xp_result->'transitions', '[]'::JSONB),
    'new_level',   v_xp_result->'new_level',
    'new_stages',  v_xp_result->'new_stages',
    'new_total_xp', v_xp_result->'new_total_xp'
  );
END $$;

GRANT EXECUTE ON FUNCTION reflection_submit(UUID, TEXT[], JSONB)
  TO authenticated;
