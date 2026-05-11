-- 0104 — parent-logged moments
--
-- A "My kid did this" button on the Adventure tab lets parents log a
-- moment they witnessed outside the venue (sharing a snack, asking
-- "why?", going first when nobody would). Each log:
--   * routes +5 XP to the matching hero via xp_credit_with_split
--   * stores a permanent diary entry tied to the child
-- Capped at 3 logs/kid/day to keep venue earning dominant.

CREATE TABLE IF NOT EXISTS parent_logged_moments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id      UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  family_id     UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  venue_id      UUID NOT NULL REFERENCES venues(id),
  hero          TEXT NOT NULL CHECK (hero IN ('rafi','ellie','gerry','zena')),
  moment_text   TEXT NOT NULL CHECK (length(moment_text) BETWEEN 1 AND 280),
  source        TEXT NOT NULL CHECK (source IN ('preset','custom')),
  xp_awarded    INTEGER NOT NULL DEFAULT 5,
  logged_by     UUID NOT NULL,
  logged_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_flagged    BOOLEAN NOT NULL DEFAULT FALSE,
  flagged_at    TIMESTAMPTZ,
  flagged_by    UUID
);

CREATE INDEX IF NOT EXISTS idx_parent_logged_moments_child_time
  ON parent_logged_moments(child_id, logged_at DESC);

ALTER TABLE parent_logged_moments ENABLE ROW LEVEL SECURITY;

CREATE POLICY parent_logged_moments_family_read ON parent_logged_moments
  FOR SELECT USING (
    family_id = auth.uid()
  );

CREATE OR REPLACE FUNCTION log_parent_moment(
  p_child_id    UUID,
  p_hero        TEXT,
  p_moment_text TEXT,
  p_source      TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child  children%ROWTYPE;
  v_today_count INTEGER;
  v_xp_amount INTEGER := 5;
  v_xp_result JSONB;
  v_xp_kwargs JSONB;
  v_venue_id UUID := '00000000-0000-0000-0000-000000000001';
  v_row parent_logged_moments%ROWTYPE;
BEGIN
  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero: %', p_hero;
  END IF;
  IF p_source NOT IN ('preset','custom') THEN
    RAISE EXCEPTION 'invalid_source: %', p_source;
  END IF;
  IF p_moment_text IS NULL OR length(trim(p_moment_text)) = 0 THEN
    RAISE EXCEPTION 'empty_moment_text';
  END IF;
  IF length(p_moment_text) > 280 THEN
    RAISE EXCEPTION 'moment_text_too_long';
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;
  IF v_child.family_id <> auth.uid() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  SELECT count(*) INTO v_today_count
    FROM parent_logged_moments
   WHERE child_id = p_child_id
     AND (logged_at AT TIME ZONE 'Asia/Kolkata')::date
         = (now() AT TIME ZONE 'Asia/Kolkata')::date;
  IF v_today_count >= 3 THEN
    RAISE EXCEPTION 'daily_cap_reached';
  END IF;

  v_xp_kwargs := jsonb_build_object(
    'p_child_id', p_child_id,
    'p_family_id', v_child.family_id,
    'p_venue_id', v_venue_id,
    'p_event_type', 'parent_log_moment',
    'p_xp_rafi',  CASE WHEN p_hero='rafi'  THEN v_xp_amount ELSE 0 END,
    'p_xp_ellie', CASE WHEN p_hero='ellie' THEN v_xp_amount ELSE 0 END,
    'p_xp_gerry', CASE WHEN p_hero='gerry' THEN v_xp_amount ELSE 0 END,
    'p_xp_zena',  CASE WHEN p_hero='zena'  THEN v_xp_amount ELSE 0 END,
    'p_metadata', jsonb_build_object(
      'moment_text', p_moment_text,
      'source', p_source
    )
  );

  v_xp_result := xp_credit_with_split(
    p_child_id   => (v_xp_kwargs->>'p_child_id')::UUID,
    p_family_id  => (v_xp_kwargs->>'p_family_id')::UUID,
    p_venue_id   => (v_xp_kwargs->>'p_venue_id')::UUID,
    p_event_type => v_xp_kwargs->>'p_event_type',
    p_xp_rafi    => (v_xp_kwargs->>'p_xp_rafi')::INTEGER,
    p_xp_ellie   => (v_xp_kwargs->>'p_xp_ellie')::INTEGER,
    p_xp_gerry   => (v_xp_kwargs->>'p_xp_gerry')::INTEGER,
    p_xp_zena    => (v_xp_kwargs->>'p_xp_zena')::INTEGER,
    p_metadata   => v_xp_kwargs->'p_metadata'
  );

  INSERT INTO parent_logged_moments(
    child_id, family_id, venue_id, hero, moment_text, source,
    xp_awarded, logged_by
  ) VALUES (
    p_child_id, v_child.family_id, v_venue_id, p_hero, trim(p_moment_text),
    p_source, v_xp_amount, v_child.family_id
  ) RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'success', true,
    'moment_id', v_row.id,
    'xp_awarded', v_xp_amount,
    'hero', p_hero,
    'logs_today', v_today_count + 1,
    'logs_remaining_today', 2 - v_today_count,
    'xp_result', v_xp_result
  );
END $$;

GRANT EXECUTE ON FUNCTION log_parent_moment(UUID, TEXT, TEXT, TEXT) TO authenticated;
