-- 0072_admin_quest_rpcs.sql
--
-- Two RPCs for admin web Layer-3 management:
--
--   admin_quest_def_upsert      Create/update a hero_quest_definitions
--                               row. is_admin() gated. Validates hero,
--                               event_type, predicate JSONB shape,
--                               xp_bonus range.
--
--   admin_quest_week_set        Schedule (or unschedule) one hero's
--                               quest for a given week. Pass quest_id
--                               = NULL to unset. Inserts hero_quest_weeks
--                               row for the week if missing.

CREATE OR REPLACE FUNCTION admin_quest_def_upsert(
  p_id                    UUID,
  p_hero                  TEXT,
  p_title                 TEXT,
  p_description           TEXT,
  p_completion_event_type TEXT,
  p_completion_predicate  JSONB,
  p_xp_bonus              INTEGER,
  p_is_active             BOOLEAN
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero: %', p_hero;
  END IF;

  IF p_completion_event_type NOT IN
     ('session_complete','workshop_attend','healthy_bite','fit_meal_order','reflection_save') THEN
    RAISE EXCEPTION 'invalid_event_type: %', p_completion_event_type;
  END IF;

  IF p_xp_bonus IS NOT NULL AND (p_xp_bonus < 0 OR p_xp_bonus > 1000) THEN
    RAISE EXCEPTION 'invalid_xp_bonus: % (must be 0..1000)', p_xp_bonus;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO hero_quest_definitions(
      hero, title, description, completion_event_type,
      completion_predicate, xp_bonus, is_active
    ) VALUES (
      p_hero, p_title, p_description, p_completion_event_type,
      COALESCE(p_completion_predicate, '{}'::jsonb),
      COALESCE(p_xp_bonus, 50),
      COALESCE(p_is_active, true)
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE hero_quest_definitions SET
      hero                  = COALESCE(p_hero, hero),
      title                 = COALESCE(p_title, title),
      description           = COALESCE(p_description, description),
      completion_event_type = COALESCE(p_completion_event_type, completion_event_type),
      completion_predicate  = COALESCE(p_completion_predicate, completion_predicate),
      xp_bonus              = COALESCE(p_xp_bonus, xp_bonus),
      is_active             = COALESCE(p_is_active, is_active),
      updated_at            = now()
    WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'hero_quest.create' ELSE 'hero_quest.update' END,
    'hero_quest', v_id,
    jsonb_build_object('hero', p_hero, 'title', p_title, 'is_active', p_is_active)
  );

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION admin_quest_def_upsert(UUID, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER, BOOLEAN)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_quest_def_upsert(UUID, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER, BOOLEAN)
  TO authenticated;

CREATE OR REPLACE FUNCTION admin_quest_week_set(
  p_week_start_date DATE,
  p_hero            TEXT,
  p_quest_id        UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero: %', p_hero;
  END IF;

  IF p_quest_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM hero_quest_definitions
       WHERE id = p_quest_id AND hero = p_hero AND is_active = true
    ) THEN
      RAISE EXCEPTION 'quest_does_not_match_hero_or_inactive';
    END IF;
  END IF;

  INSERT INTO hero_quest_weeks(week_start_date)
  VALUES (p_week_start_date)
  ON CONFLICT (week_start_date) DO NOTHING;

  IF p_hero = 'rafi'  THEN UPDATE hero_quest_weeks SET quest_id_rafi  = p_quest_id, updated_at = now() WHERE week_start_date = p_week_start_date; END IF;
  IF p_hero = 'ellie' THEN UPDATE hero_quest_weeks SET quest_id_ellie = p_quest_id, updated_at = now() WHERE week_start_date = p_week_start_date; END IF;
  IF p_hero = 'gerry' THEN UPDATE hero_quest_weeks SET quest_id_gerry = p_quest_id, updated_at = now() WHERE week_start_date = p_week_start_date; END IF;
  IF p_hero = 'zena'  THEN UPDATE hero_quest_weeks SET quest_id_zena  = p_quest_id, updated_at = now() WHERE week_start_date = p_week_start_date; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin', 'hero_quest_week.set', 'hero_quest_week',
    NULL,
    jsonb_build_object('week_start_date', p_week_start_date,
                       'hero', p_hero, 'quest_id', p_quest_id)
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_quest_week_set(DATE, TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_quest_week_set(DATE, TEXT, UUID) TO authenticated;
