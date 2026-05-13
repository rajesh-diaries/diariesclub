-- 0132 — admin_kid_diary RPC for the per-kid Diary panel.
--
-- Returns a unified timeline of a kid's reflections (from hero_recaps)
-- + parent-log pool submissions (grouped by pool_submission_id), each
-- with the moments tapped/written + the per-trait XP split. Used by the
-- admin Customer Detail screen so admin can see exactly what parents
-- are saying about their kids.

CREATE OR REPLACE FUNCTION public.admin_kid_diary(
  p_child_id UUID,
  p_limit    INTEGER DEFAULT 20
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_limit IS NULL OR p_limit < 1 THEN p_limit := 20; END IF;
  IF p_limit > 200 THEN p_limit := 200; END IF;

  WITH refl AS (
    SELECT
      'reflection'::TEXT AS kind,
      hr.reflection_at   AS event_at,
      hr.id              AS reflection_id,
      hr.session_id      AS session_id,
      NULL::UUID         AS submission_id,
      hr.moment_tags     AS moment_tags,
      hr.total_xp_pool   AS xp_pool,
      (
        SELECT jsonb_build_object(
          'rafi',  COALESCE(xe.xp_rafi,  0),
          'ellie', COALESCE(xe.xp_ellie, 0),
          'gerry', COALESCE(xe.xp_gerry, 0),
          'zena',  COALESCE(xe.xp_zena,  0)
        )
        FROM xp_events xe
        WHERE xe.reference_id = hr.session_id
          AND xe.event_type = 'reflection_split'
        ORDER BY xe.created_at DESC LIMIT 1
      ) AS xp_split
    FROM hero_recaps hr
    WHERE hr.child_id = p_child_id
      AND hr.reflection_status = 'reflected'
      AND hr.reflection_at IS NOT NULL
  ),
  refl_expanded AS (
    SELECT
      r.kind, r.event_at, r.reflection_id, r.session_id, r.submission_id,
      r.xp_pool, r.xp_split,
      (
        SELECT COALESCE(jsonb_agg(entry ORDER BY ord), '[]'::jsonb)
        FROM (
          SELECT
            ord,
            CASE
              WHEN tag LIKE 'custom:%' THEN jsonb_build_object(
                'trait', split_part(tag, ':', 2),
                'text',  substring(tag FROM length('custom:' || split_part(tag, ':', 2) || ':') + 1),
                'source','custom'
              )
              ELSE (
                SELECT jsonb_build_object(
                  'trait', rm.primary_trait,
                  'text',  rm.display_text,
                  'source','preset'
                )
                FROM reflection_moments rm WHERE rm.tag = t.tag
              )
            END AS entry
          FROM unnest(r.moment_tags) WITH ORDINALITY t(tag, ord)
        ) sub
        WHERE entry IS NOT NULL
      ) AS moments
    FROM refl r
  ),
  parent_logs AS (
    SELECT
      'parent_log'::TEXT AS kind,
      MAX(plm.logged_at) AS event_at,
      NULL::UUID         AS reflection_id,
      NULL::UUID         AS session_id,
      plm.pool_submission_id AS submission_id,
      NULL::TEXT[]       AS moment_tags,
      NULL::INTEGER      AS xp_pool,
      (
        SELECT jsonb_build_object(
          'rafi',  COALESCE(xe.xp_rafi,  0),
          'ellie', COALESCE(xe.xp_ellie, 0),
          'gerry', COALESCE(xe.xp_gerry, 0),
          'zena',  COALESCE(xe.xp_zena,  0)
        )
        FROM xp_events xe
        WHERE xe.event_type = 'parent_log_pool'
          AND xe.metadata->>'pool_submission_id' = plm.pool_submission_id::TEXT
        ORDER BY xe.created_at DESC LIMIT 1
      ) AS xp_split,
      jsonb_agg(
        jsonb_build_object(
          'trait', plm.hero,
          'text', plm.moment_text,
          'source', plm.source
        ) ORDER BY plm.logged_at, plm.id
      ) AS moments
    FROM parent_logged_moments plm
    WHERE plm.child_id = p_child_id
      AND plm.pool_submission_id IS NOT NULL
    GROUP BY plm.pool_submission_id
  )
  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'event_at') DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'kind',           kind,
      'event_at',       event_at,
      'reflection_id',  reflection_id,
      'session_id',     session_id,
      'submission_id',  submission_id,
      'moments',        moments,
      'xp_split',       xp_split,
      'xp_pool',        xp_pool
    ) AS row
    FROM (
      SELECT kind, event_at, reflection_id, session_id, submission_id,
             moments, xp_split, xp_pool FROM refl_expanded
      UNION ALL
      SELECT kind, event_at, reflection_id, session_id, submission_id,
             moments, xp_split, xp_pool FROM parent_logs
    ) merged
    WHERE event_at IS NOT NULL
    ORDER BY event_at DESC
    LIMIT p_limit
  ) limited;

  RETURN jsonb_build_object('rows', COALESCE(v_rows, '[]'::jsonb));
END $$;

GRANT EXECUTE ON FUNCTION public.admin_kid_diary(UUID, INTEGER) TO authenticated;
