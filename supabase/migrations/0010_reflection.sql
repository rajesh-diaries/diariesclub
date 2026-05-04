-- ===========================================================================
--  Migration 0010 — Gamification + Reflection (Session 6)
--
--  Adds:
--    1) notifications.metadata JSONB           (dedupe key for stage-imminent)
--    2) venue_config.stage_imminent_xp_gap     (configurable, default 50)
--    3) reflection_moments seed                (24 cards, 6 per trait)
--    4) hero_card_definitions seed             (24 cards, 4 common + 2 rare per hero)
--    5) reflection_moments_for_recap RPC       (deterministic 12-card sample)
--    6) reflection_submit RPC                  (now surfaces transitions)
--    7) xp_credit_with_split RPC               (inline stage-imminent push)
--    8) healthy_bite_distribute RPC            (deep_link → /cards/unbox/{id})
--    9) session_complete RPC                   (fix recap notification deep_link)
--
--  TODO(founder): wordsmith pass on the 24 reflection-moment captions.
--  TODO(founder): replace placeholder hero card names + image_urls before launch.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. notifications.metadata
-- ---------------------------------------------------------------------------
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ---------------------------------------------------------------------------
--  2. venue_config.stage_imminent_xp_gap
-- ---------------------------------------------------------------------------
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS stage_imminent_xp_gap INTEGER NOT NULL DEFAULT 50;

-- ---------------------------------------------------------------------------
--  3. reflection_moments seed
--     TODO(founder): wordsmith pass.
-- ---------------------------------------------------------------------------
DELETE FROM reflection_moments;
INSERT INTO reflection_moments (tag, display_text, primary_trait, sort_order, icon) VALUES
  -- Rafi (Brave) — 6 cards
  ('tried_something_new',    'Tried something new',           'rafi',  10, 'rocket'),
  ('took_a_leap',            'Took a leap',                   'rafi',  20, 'arrow-fat-up'),
  ('faced_a_fear',           'Faced something they feared',   'rafi',  30, 'shield-check'),
  ('led_the_way',            'Led the way',                   'rafi',  40, 'flag'),
  ('kept_trying',            'Kept trying after stumbling',   'rafi',  50, 'arrow-clockwise'),
  ('went_first',             'Went first when others paused', 'rafi',  60, 'star'),

  -- Ellie (Kind) — 6 cards
  ('shared_with_friend',     'Shared with a friend',          'ellie', 110, 'gift'),
  ('helped_a_friend',        'Helped a friend',               'ellie', 120, 'hand-heart'),
  ('checked_on_someone',     'Checked on someone upset',      'ellie', 130, 'smiley'),
  ('included_someone_new',   'Included someone new',          'ellie', 140, 'users'),
  ('said_thank_you',         'Said thank you on their own',   'ellie', 150, 'heart'),
  ('gave_a_compliment',      'Gave a compliment',             'ellie', 160, 'sparkle'),

  -- Gerry (Curious) — 6 cards
  ('asked_questions',        'Asked lots of questions',       'gerry', 210, 'question'),
  ('explored_new_corner',    'Explored a new corner',         'gerry', 220, 'compass'),
  ('figured_it_out',         'Figured something out',         'gerry', 230, 'lightbulb'),
  ('observed_carefully',     'Watched carefully before doing','gerry', 240, 'eye'),
  ('connected_two_things',   'Connected two ideas',           'gerry', 250, 'graph'),
  ('learned_a_word',         'Learned a new word or phrase',  'gerry', 260, 'book-open'),

  -- Zena (Creative) — 6 cards
  ('made_up_a_game',         'Made up a game',                'zena',  310, 'puzzle-piece'),
  ('drew_or_built',          'Drew or built something',       'zena',  320, 'palette'),
  ('imagined_a_story',       'Imagined a story',              'zena',  330, 'feather'),
  ('mixed_things_unusually', 'Mixed things in a new way',     'zena',  340, 'shuffle'),
  ('performed_for_others',   'Performed or showed off art',   'zena',  350, 'microphone'),
  ('reused_something',       'Used something in a new way',   'zena',  360, 'recycle');

-- ---------------------------------------------------------------------------
--  4. hero_card_definitions seed
--     4 common + 2 rare per hero × 4 heroes = 24 placeholder cards.
--     TODO(founder): rename + ship real artwork; bump image_url to CDN paths.
-- ---------------------------------------------------------------------------
DELETE FROM hero_card_definitions;
INSERT INTO hero_card_definitions (name, hero, is_rare, image_url, description) VALUES
  -- Rafi (Brave)
  ('Brave Beginner',   'rafi',  false, 'https://placehold.co/600x800/E8524A/FFFFFF.png?text=Brave+Beginner',   'Took a first step.'),
  ('Trusty Shield',    'rafi',  false, 'https://placehold.co/600x800/E8524A/FFFFFF.png?text=Trusty+Shield',    'Stood firm for a friend.'),
  ('First Charge',     'rafi',  false, 'https://placehold.co/600x800/E8524A/FFFFFF.png?text=First+Charge',     'Led the way into something new.'),
  ('Steady Stand',     'rafi',  false, 'https://placehold.co/600x800/E8524A/FFFFFF.png?text=Steady+Stand',     'Kept trying when things got hard.'),
  ('Lionheart',        'rafi',  true,  'https://placehold.co/600x800/E8524A/FFE066.png?text=Lionheart',        'Brave through and through. (Rare)'),
  ('Courage Crown',    'rafi',  true,  'https://placehold.co/600x800/E8524A/FFE066.png?text=Courage+Crown',    'A legend of fearlessness. (Rare)'),

  -- Ellie (Kind)
  ('Helping Hand',     'ellie', false, 'https://placehold.co/600x800/5BC8E8/FFFFFF.png?text=Helping+Hand',     'Lent a hand without being asked.'),
  ('Sharing Spirit',   'ellie', false, 'https://placehold.co/600x800/5BC8E8/FFFFFF.png?text=Sharing+Spirit',   'Made someone smile by sharing.'),
  ('Warm Welcome',     'ellie', false, 'https://placehold.co/600x800/5BC8E8/FFFFFF.png?text=Warm+Welcome',     'Made a new friend feel included.'),
  ('Kind Echo',        'ellie', false, 'https://placehold.co/600x800/5BC8E8/FFFFFF.png?text=Kind+Echo',        'Said thank you with heart.'),
  ('Gentle Giant',     'ellie', true,  'https://placehold.co/600x800/5BC8E8/FFE066.png?text=Gentle+Giant',     'Big-hearted hero. (Rare)'),
  ('Heart of Gold',    'ellie', true,  'https://placehold.co/600x800/5BC8E8/FFE066.png?text=Heart+of+Gold',    'Pure kindness made visible. (Rare)'),

  -- Gerry (Curious)
  ('Question Spark',   'gerry', false, 'https://placehold.co/600x800/F0A830/FFFFFF.png?text=Question+Spark',   'Asked the question no one else thought of.'),
  ('Tinkerer',         'gerry', false, 'https://placehold.co/600x800/F0A830/FFFFFF.png?text=Tinkerer',         'Took it apart to see how it works.'),
  ('Wonder Walker',    'gerry', false, 'https://placehold.co/600x800/F0A830/FFFFFF.png?text=Wonder+Walker',    'Explored a brand-new corner.'),
  ('Tiny Detective',   'gerry', false, 'https://placehold.co/600x800/F0A830/FFFFFF.png?text=Tiny+Detective',   'Watched, listened, then figured it out.'),
  ('Discovery Beacon', 'gerry', true,  'https://placehold.co/600x800/F0A830/FFE066.png?text=Discovery+Beacon', 'Lights the way for others. (Rare)'),
  ('Mystery Seeker',   'gerry', true,  'https://placehold.co/600x800/F0A830/FFE066.png?text=Mystery+Seeker',   'Always one question deeper. (Rare)'),

  -- Zena (Creative)
  ('Doodler',          'zena',  false, 'https://placehold.co/600x800/7BC74D/FFFFFF.png?text=Doodler',          'Made marks that meant something.'),
  ('Idea Spark',       'zena',  false, 'https://placehold.co/600x800/7BC74D/FFFFFF.png?text=Idea+Spark',       'Came up with a brand-new game.'),
  ('Storyteller',      'zena',  false, 'https://placehold.co/600x800/7BC74D/FFFFFF.png?text=Storyteller',      'Imagined a world out loud.'),
  ('Junk Genius',      'zena',  false, 'https://placehold.co/600x800/7BC74D/FFFFFF.png?text=Junk+Genius',      'Used something for a brand-new purpose.'),
  ('Imaginarium',      'zena',  true,  'https://placehold.co/600x800/7BC74D/FFE066.png?text=Imaginarium',      'A whole imagined world inside. (Rare)'),
  ('Master Maker',     'zena',  true,  'https://placehold.co/600x800/7BC74D/FFE066.png?text=Master+Maker',     'Builds wonder from anything. (Rare)');

-- ---------------------------------------------------------------------------
--  5. reflection_moments_for_recap RPC
--
--  Deterministic 12-card sample (3 per trait) keyed by recap_id so a parent
--  who closes and reopens the reflection screen sees the same 12 cards.
--  The hash of recap_id || tag gives a stable per-recap shuffle without
--  needing a separate persisted column.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reflection_moments_for_recap(p_recap_id UUID)
RETURNS TABLE(
  id UUID, tag TEXT, display_text TEXT, primary_trait TEXT,
  icon TEXT, xp_weight NUMERIC, sort_order INTEGER
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  WITH ranked AS (
    SELECT
      rm.id, rm.tag, rm.display_text, rm.primary_trait,
      rm.icon, rm.xp_weight, rm.sort_order,
      ROW_NUMBER() OVER (
        PARTITION BY rm.primary_trait
        ORDER BY md5(p_recap_id::text || rm.tag)
      ) AS rn
    FROM reflection_moments rm
    WHERE rm.is_active = true
  )
  SELECT r.id, r.tag, r.display_text, r.primary_trait,
         r.icon, r.xp_weight, r.sort_order
  FROM ranked r
  WHERE r.rn <= 3
  ORDER BY r.primary_trait, r.sort_order;
END $$;

REVOKE EXECUTE ON FUNCTION reflection_moments_for_recap(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION reflection_moments_for_recap(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
--  6. reflection_submit — now returns transitions
--
--  Functional change: capture xp_credit_with_split's JSONB result and merge
--  transitions / new_level / new_stages into the response so the client can
--  drive the cinematic. Signature unchanged; previous callers tolerate the
--  richer payload.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reflection_submit(
  p_session_id UUID,
  p_moment_tags TEXT[]
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
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena  INTEGER := 0;
  v_xp_result JSONB;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

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

  -- Capture xp_credit_with_split's full JSONB so we can surface transitions
  -- + new_level + new_stages to the client (drives the cinematic).
  v_xp_result := xp_credit_with_split(
    v_session.child_id, v_session.family_id, v_session.venue_id,
    'reflection_split',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    p_session_id,
    jsonb_build_object('moment_tags', to_jsonb(p_moment_tags))
  );

  UPDATE hero_recaps SET
    reflection_status = 'reflected',
    reflection_at = now(),
    moment_tags = p_moment_tags
  WHERE session_id = p_session_id;

  UPDATE sessions SET reflection_status = 'reflected' WHERE id = p_session_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_session.family_id, 'customer',
    'reflection.submit', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('split',
      jsonb_build_object('rafi', v_xp_rafi, 'ellie', v_xp_ellie,
                         'gerry', v_xp_gerry, 'zena', v_xp_zena),
      'moment_tags', to_jsonb(p_moment_tags))
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

-- ---------------------------------------------------------------------------
--  7. xp_credit_with_split — adds inline "stage_transition_imminent" push
--
--  After the per-trait XP + stage recompute, scan the four traits and emit
--  a 'stage_transition_imminent' notification for any trait that is now
--  within `venue_config.stage_imminent_xp_gap` of the next threshold (and
--  not already past it). Dedup via NOT EXISTS check on the same metadata
--  threshold_label within the last 24 hours — prevents spam if XP comes in
--  bursty (e.g. a workshop right after a session).
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
  v_imminent_gap INTEGER;
  v_new_total INTEGER;
  v_new_level INTEGER := 1;
  v_new_overall_stage TEXT;
  v_old_stages JSONB;
  v_new_stages JSONB := '{}'::JSONB;
  v_transitions JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_next_threshold INTEGER;
  v_next_stage_label TEXT;
  i INTEGER;
BEGIN
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds   := v_config.stage_thresholds_per_trait;
  v_imminent_gap       := v_config.stage_imminent_xp_gap;

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

  -- Per-trait stage recompute + transitions detection
  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;
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
    v_new_stages := v_new_stages || jsonb_build_object(v_trait, v_new_stage);
    v_old_stage := v_old_stages->>v_trait;
    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_array(
        jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage)
      );
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
    p_reference_id, p_metadata || jsonb_build_object('stage_transitions', v_transitions)
  );

  -- Stage transition revealed: notification once per credit-call when any
  -- trait actually crossed a threshold (existing behaviour preserved).
  IF jsonb_array_length(v_transitions) > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      v_child.name || ' just leveled up!',
      'See the new look in their adventure tab.',
      '/adventure', p_child_id
    );
  END IF;

  -- Stage-imminent push: for each trait, if the new XP is within the gap
  -- of the next threshold (and below it), and we haven't already nudged
  -- for that exact (child × trait × next-stage-label) in the last 24h,
  -- fire a notification. Reads gap from venue_config.
  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;
    v_next_threshold := NULL;
    v_next_stage_label := NULL;
    FOR i IN 0..(jsonb_array_length(v_trait_thresholds) - 1) LOOP
      IF (v_trait_thresholds->>i)::INTEGER > v_trait_xp THEN
        v_next_threshold := (v_trait_thresholds->>i)::INTEGER;
        v_next_stage_label := CASE i
          WHEN 1 THEN 'explorer'  WHEN 2 THEN 'adventurer'
          WHEN 3 THEN 'champion'  WHEN 4 THEN 'legend'
          ELSE NULL
        END;
        EXIT;
      END IF;
    END LOOP;

    IF v_next_threshold IS NOT NULL
       AND v_next_stage_label IS NOT NULL
       AND (v_next_threshold - v_trait_xp) <= v_imminent_gap
       AND NOT EXISTS (
         SELECT 1 FROM notifications
          WHERE family_id = p_family_id
            AND type = 'stage_transition_imminent'
            AND reference_id = p_child_id
            AND metadata->>'trait' = v_trait
            AND metadata->>'threshold_label' = v_next_stage_label
            AND created_at > now() - INTERVAL '24 hours'
       )
    THEN
      INSERT INTO notifications(
        family_id, type, title, body, deep_link, reference_id, metadata
      ) VALUES (
        p_family_id, 'stage_transition_imminent',
        v_child.name || ' is close to a milestone',
        'One good session away from ' || v_next_stage_label || '.',
        '/adventure', p_child_id,
        jsonb_build_object(
          'trait', v_trait,
          'threshold_label', v_next_stage_label,
          'current_xp', v_trait_xp,
          'threshold_xp', v_next_threshold
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'new_total_xp', v_new_total,
    'new_level', v_new_level,
    'new_overall_stage', v_new_overall_stage,
    'new_stages', v_new_stages,
    'transitions', v_transitions
  );
END $$;

-- ---------------------------------------------------------------------------
--  8. healthy_bite_distribute — deep_link to /cards/unbox/{collection_id}
--
--  Functional changes: (a) capture the inserted hero_card_collection.id and
--  use it in the notification deep_link; (b) include card_id + is_rare in
--  notifications.metadata so the unbox screen can render before fetching.
-- ---------------------------------------------------------------------------
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
    SET earned_at = EXCLUDED.earned_at
  RETURNING id INTO v_collection_id;

  INSERT INTO notifications(
    family_id, type, title, body, deep_link, reference_id, metadata
  ) VALUES (
    v_session.family_id, 'hero_card_received',
    'New hero card!',
    CASE WHEN v_card.is_rare THEN 'A rare card just arrived in your collection.'
         ELSE 'Tap to add it to your collection.' END,
    '/cards/unbox/' || v_collection_id, p_child_id,
    jsonb_build_object(
      'card_id', v_card.id,
      'collection_id', v_collection_id,
      'is_rare', v_card.is_rare
    )
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
          v_session.venue_id,
          jsonb_build_object('card_id', v_card.id, 'is_rare', v_card.is_rare,
                             'collection_id', v_collection_id));

  RETURN jsonb_build_object(
    'success', true,
    'card_id', v_card.id,
    'collection_id', v_collection_id,
    'card_name', v_card.name,
    'is_rare', v_card.is_rare,
    'image_url', v_card.image_url
  );
END $$;

-- ---------------------------------------------------------------------------
--  9. session_complete — fix recap notification deep_link
--
--  The body was unchanged from 0003 except for the deep_link, which used
--  '/recap/{id}' (a 404 — no such route). Now points at the existing
--  '/reflection/:sessionId' GoRoute so taps from the bell actually work.
--  Everything else is byte-for-byte the same as 0003.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION session_complete(
  p_session_id UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_config  venue_config%ROWTYPE;
  v_pool    INTEGER;
  v_recap_id UUID;
  v_deadline TIMESTAMPTZ;
  v_old_status TEXT;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF auth.role() <> 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);
  END IF;

  IF v_session.status IN ('completed','auto_closed','void') THEN
    SELECT id INTO v_recap_id FROM hero_recaps WHERE session_id = p_session_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', p_session_id,
      'recap_id', v_recap_id,
      'status', v_session.status
    );
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  v_pool := v_session.duration_minutes * v_config.xp_per_session_minute;
  v_deadline := now() + (v_config.reflection_window_hours || ' hours')::INTERVAL;
  v_old_status := v_session.status;

  UPDATE sessions SET
    status = 'completed',
    completed_at = now(),
    reflection_deadline = v_deadline,
    total_xp_earned = v_pool
  WHERE id = p_session_id;

  INSERT INTO hero_recaps(
    session_id, child_id, total_xp_pool,
    reflection_status, reflection_deadline
  ) VALUES (
    p_session_id, v_session.child_id, v_pool,
    'pending', v_deadline
  )
  ON CONFLICT (session_id) DO NOTHING
  RETURNING id INTO v_recap_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'session_closed',
    'Session ended — recap on the way',
    'Tap to reflect on the moments and earn XP.',
    '/reflection/' || p_session_id, p_session_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN auth.role() = 'service_role' THEN 'system'
         WHEN p_staff_pin_id IS NOT NULL    THEN 'staff'
         ELSE 'customer' END,
    'session.complete', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', 'completed', 'total_xp_pool', v_pool,
                       'reflection_deadline', v_deadline)
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'recap_id', v_recap_id,
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $$;

COMMIT;
