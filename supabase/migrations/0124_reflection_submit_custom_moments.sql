-- 0124 — reflection_submit accepts custom moments.
--
-- The reflection screen's "+ More moments" tile now opens a multi-select
-- sheet that returns extra picks (presets from the wider parent-log pool
-- + free-text). Those selections feed the SAME 50 XP pool — not a
-- separate +5 XP-per-tap log. Each custom moment counts as 1.0 weight
-- on its trait (equivalent to a preset reflection moment with weight 1.0).
--
-- Custom moments are persisted in hero_recaps.moment_tags as
-- "custom:<trait>:<text>" so the diary view + audit log keep the text.

DROP FUNCTION IF EXISTS public.reflection_submit(uuid, text[]);

CREATE OR REPLACE FUNCTION public.reflection_submit(
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

  UPDATE sessions SET reflection_status = 'reflected' WHERE id = p_session_id;

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
      'custom_moments', p_custom_moments
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

GRANT EXECUTE ON FUNCTION public.reflection_submit(UUID, TEXT[], JSONB)
  TO authenticated;
