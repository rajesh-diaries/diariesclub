-- 0069_hero_quests_schema_and_check_helper.sql
--
-- Be the Hero Layer 3 — Weekly Hero Quests.
--
-- Each calendar week (Monday→Sunday IST), every kid sees one quest
-- per hero. Quests are admin-authored templates; admin schedules four
-- per week (one per hero). Completion is auto-detected when one of
-- the five qualifying events fires for the kid (session_complete /
-- workshop_attend / healthy_bite / fit_meal_order / reflection_save).
--
-- Schema:
--   hero_quest_definitions   admin-authored quest templates per hero
--   hero_quest_weeks         the 4 active quests for a Monday→Sunday week
--   hero_quest_progress      per-child completion record (1 row per
--                            child × week × hero, only when active)
--
-- Helper:
--   _quest_progress_check(...)
--     Looks up the active quest for the child's hero this week,
--     validates the event matches the quest's event_type + predicate,
--     marks complete + grants xp_bonus via xp_credit_with_split
--     (which in turn can chain stage transitions / card grants /
--     perk grants). Idempotent — second call for the same kid+week+
--     hero is a no-op.
--
-- Detection hooks into session_complete / workshop_attend /
-- healthy_bite_distribute / order_place / reflection_save ship in
-- subsequent migrations alongside admin + customer UI.

CREATE TABLE IF NOT EXISTS hero_quest_definitions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hero                TEXT NOT NULL CHECK (hero IN ('rafi','ellie','gerry','zena')),
  title               TEXT NOT NULL,
  description         TEXT,
  completion_event_type TEXT NOT NULL CHECK (completion_event_type IN
                        ('session_complete','workshop_attend','healthy_bite',
                         'fit_meal_order','reflection_save')),
  completion_predicate JSONB NOT NULL DEFAULT '{}'::jsonb,
  xp_bonus            INTEGER NOT NULL DEFAULT 50 CHECK (xp_bonus BETWEEN 0 AND 1000),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hero_quest_defs_hero_active
  ON hero_quest_definitions(hero, is_active) WHERE is_active = true;

CREATE TABLE IF NOT EXISTS hero_quest_weeks (
  week_start_date     DATE PRIMARY KEY,
  quest_id_rafi       UUID REFERENCES hero_quest_definitions(id) ON DELETE SET NULL,
  quest_id_ellie      UUID REFERENCES hero_quest_definitions(id) ON DELETE SET NULL,
  quest_id_gerry      UUID REFERENCES hero_quest_definitions(id) ON DELETE SET NULL,
  quest_id_zena       UUID REFERENCES hero_quest_definitions(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hero_quest_progress (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id            UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  family_id           UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  week_start_date     DATE NOT NULL,
  hero                TEXT NOT NULL CHECK (hero IN ('rafi','ellie','gerry','zena')),
  quest_id            UUID NOT NULL REFERENCES hero_quest_definitions(id) ON DELETE RESTRICT,
  completed_at        TIMESTAMPTZ,
  completion_reference_id UUID,
  xp_awarded          INTEGER NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(child_id, week_start_date, hero)
);

CREATE INDEX IF NOT EXISTS idx_hero_quest_progress_family_week
  ON hero_quest_progress(family_id, week_start_date);
CREATE INDEX IF NOT EXISTS idx_hero_quest_progress_pending
  ON hero_quest_progress(child_id, week_start_date)
  WHERE completed_at IS NULL;

ALTER TABLE hero_quest_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_quest_weeks       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_quest_progress    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hq_defs_admin_all ON hero_quest_definitions;
CREATE POLICY hq_defs_admin_all ON hero_quest_definitions
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

DROP POLICY IF EXISTS hq_defs_public_read ON hero_quest_definitions;
CREATE POLICY hq_defs_public_read ON hero_quest_definitions
  FOR SELECT TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS hq_weeks_admin_all ON hero_quest_weeks;
CREATE POLICY hq_weeks_admin_all ON hero_quest_weeks
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

DROP POLICY IF EXISTS hq_weeks_public_read ON hero_quest_weeks;
CREATE POLICY hq_weeks_public_read ON hero_quest_weeks
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS hq_progress_family ON hero_quest_progress;
CREATE POLICY hq_progress_family ON hero_quest_progress
  FOR SELECT TO authenticated
  USING (family_id = auth.uid());

DROP POLICY IF EXISTS hq_progress_admin_all ON hero_quest_progress;
CREATE POLICY hq_progress_admin_all ON hero_quest_progress
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

CREATE OR REPLACE FUNCTION _ist_week_start(p_ts TIMESTAMPTZ DEFAULT now())
RETURNS DATE
LANGUAGE sql IMMUTABLE AS $$
  SELECT (date_trunc('week', (p_ts AT TIME ZONE 'Asia/Kolkata'))::DATE);
$$;

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

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    p_family_id, 'stage_transition_revealed',
    'Quest complete: ' || v_def.title,
    '+' || v_def.xp_bonus || ' XP for ' || initcap(p_hero) || '.',
    '/adventure', p_child_id
  );

  RETURN jsonb_build_object(
    'matched', true,
    'quest_id', v_quest_id,
    'title', v_def.title,
    'xp_awarded', v_def.xp_bonus,
    'hero', p_hero
  );
END $$;

REVOKE EXECUTE ON FUNCTION _quest_progress_check(UUID, UUID, UUID, TEXT, TEXT, JSONB, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _quest_progress_check(UUID, UUID, UUID, TEXT, TEXT, JSONB, UUID)
  TO service_role;
