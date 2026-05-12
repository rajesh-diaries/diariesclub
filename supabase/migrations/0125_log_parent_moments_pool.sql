-- 0125 — log_parent_moments_pool RPC + pool tracking column.
--
-- Standalone Adventure-tab "My kid did this" flow now uses the same
-- pool-split model as the post-session reflection: ONE 50 XP pool gets
-- divided across whatever the parent ticks across all 4 characters.
-- Each ticked moment counts as 1.0 weight on its trait.
--
-- Cap: one pool submission per kid per calendar day (Asia/Kolkata).
-- That's a softer constraint than the old +5/tap × 3/day; it gives the
-- parent freedom to log as many moments as they want — the pool just
-- gets distributed differently.

ALTER TABLE parent_logged_moments
  ADD COLUMN IF NOT EXISTS pool_submission_id UUID;

ALTER TABLE xp_events DROP CONSTRAINT IF EXISTS xp_events_event_type_check;
ALTER TABLE xp_events ADD CONSTRAINT xp_events_event_type_check
  CHECK (event_type IN (
    'play_session', 'reflection_split', 'auto_split',
    'healthy_bite', 'workshop', 'birthday_hosted', 'birthday_guest',
    'first_session', 'streak_bonus', 'referral_bonus', 'birthday_bonus',
    'visit_milestone', 'manual_admin', 'admin_manual_grant',
    'parent_log_moment', 'parent_log_pool'
  ));

CREATE OR REPLACE FUNCTION public.log_parent_moments_pool(
  p_child_id UUID,
  p_moments  JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child       children%ROWTYPE;
  v_today_count INTEGER;
  v_pool        INTEGER := 50;
  v_weights JSONB := '{"rafi":0,"ellie":0,"gerry":0,"zena":0}'::JSONB;
  v_total_weight NUMERIC := 0;
  v_moment      JSONB;
  v_trait       TEXT;
  v_text        TEXT;
  v_xp_rafi  INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena  INTEGER := 0;
  v_xp_result JSONB;
  v_submission_id UUID := gen_random_uuid();
  v_venue_id UUID := '00000000-0000-0000-0000-000000000001';
  v_count_inserted INTEGER := 0;
BEGIN
  IF p_moments IS NULL OR jsonb_typeof(p_moments) <> 'array' THEN
    RAISE EXCEPTION 'invalid_payload';
  END IF;
  IF jsonb_array_length(p_moments) = 0 THEN
    RAISE EXCEPTION 'empty_submission';
  END IF;
  IF jsonb_array_length(p_moments) > 40 THEN
    RAISE EXCEPTION 'too_many_moments';
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;
  IF v_child.family_id <> auth.uid() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT count(DISTINCT pool_submission_id) INTO v_today_count
    FROM parent_logged_moments
   WHERE child_id = p_child_id
     AND pool_submission_id IS NOT NULL
     AND (logged_at AT TIME ZONE 'Asia/Kolkata')::date
         = (now() AT TIME ZONE 'Asia/Kolkata')::date;
  IF v_today_count >= 1 THEN
    RAISE EXCEPTION 'daily_pool_cap_reached';
  END IF;

  FOR v_moment IN SELECT * FROM jsonb_array_elements(p_moments) LOOP
    v_trait := v_moment->>'trait';
    v_text  := trim(coalesce(v_moment->>'text',''));
    IF v_trait NOT IN ('rafi','ellie','gerry','zena') THEN
      RAISE EXCEPTION 'invalid_trait: %', v_trait;
    END IF;
    IF v_text = '' OR length(v_text) > 280 THEN
      RAISE EXCEPTION 'invalid_text_length';
    END IF;
    v_weights := jsonb_set(
      v_weights,
      ARRAY[v_trait],
      to_jsonb((v_weights->>v_trait)::NUMERIC + 1.0)
    );
    v_total_weight := v_total_weight + 1.0;
  END LOOP;

  v_xp_rafi  := FLOOR(v_pool * (v_weights->>'rafi') ::NUMERIC / v_total_weight)::INTEGER;
  v_xp_ellie := FLOOR(v_pool * (v_weights->>'ellie')::NUMERIC / v_total_weight)::INTEGER;
  v_xp_gerry := FLOOR(v_pool * (v_weights->>'gerry')::NUMERIC / v_total_weight)::INTEGER;
  v_xp_zena  := v_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);

  v_xp_result := xp_credit_with_split(
    p_child_id, v_child.family_id, v_venue_id,
    'parent_log_pool',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    NULL,
    jsonb_build_object(
      'pool_submission_id', v_submission_id,
      'moments', p_moments,
      'pool_xp', v_pool
    )
  );

  FOR v_moment IN SELECT * FROM jsonb_array_elements(p_moments) LOOP
    INSERT INTO parent_logged_moments(
      child_id, family_id, venue_id, hero, moment_text, source,
      xp_awarded, logged_by, pool_submission_id
    ) VALUES (
      p_child_id, v_child.family_id, v_venue_id,
      v_moment->>'trait',
      trim(v_moment->>'text'),
      coalesce(v_moment->>'source','pool'),
      0,
      v_child.family_id,
      v_submission_id
    );
    v_count_inserted := v_count_inserted + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'pool_submission_id', v_submission_id,
    'moments_logged', v_count_inserted,
    'pool_xp', v_pool,
    'split', jsonb_build_object(
      'rafi', v_xp_rafi, 'ellie', v_xp_ellie,
      'gerry', v_xp_gerry, 'zena', v_xp_zena
    ),
    'xp_result', v_xp_result
  );
END $$;

GRANT EXECUTE ON FUNCTION public.log_parent_moments_pool(UUID, JSONB)
  TO authenticated;
