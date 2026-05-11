-- 0089 — admin_family_children_summary RPC
--
-- Returns per-kid activity stats for the admin customer detail screen
-- in a single round-trip. Stats: visits (completed sessions), total
-- play minutes, last visit date, workshops attended, cards collected,
-- perks redeemed, reflections completed.

CREATE OR REPLACE FUNCTION public.admin_family_children_summary(
  p_family_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result JSONB := '[]'::jsonb;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'child_id', c.id,
    'sessions_completed', sess.cnt,
    'total_play_minutes', sess.total_min,
    'last_visit_at', sess.last_at,
    'workshops_attended', w.cnt,
    'cards_collected', cards.cnt,
    'perks_redeemed', perks.cnt,
    'reflections_completed', refl.cnt
  )), '[]'::jsonb) INTO result
  FROM children c
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*) AS cnt,
      COALESCE(SUM(duration_minutes), 0) AS total_min,
      MAX(completed_at) AS last_at
    FROM sessions
    WHERE child_id = c.id AND status = 'completed'
  ) sess ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM workshop_registrations
    WHERE child_id = c.id AND attended = true
  ) w ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM hero_card_collection WHERE child_id = c.id
  ) cards ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM stage_perk_grants
    WHERE child_id = c.id AND redeemed_at IS NOT NULL
  ) perks ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM hero_recaps
    WHERE child_id = c.id AND reflection_status = 'completed'
  ) refl ON true
  WHERE c.family_id = p_family_id;

  RETURN result;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_family_children_summary(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_family_children_summary(uuid)
  TO authenticated;
