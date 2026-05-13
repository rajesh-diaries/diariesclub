-- 0133 — admin_family_diary RPC.
--
-- Combined timeline across ALL kids in a family. Same shape as
-- admin_kid_diary (reflections + parent-log pool submissions, both
-- ordered by event_at DESC), but each entry also carries child_id +
-- child_name so the admin UI can label "Anaya · Reflection ...",
-- "Vihaan · Parent-log ..." in one scroll.

CREATE OR REPLACE FUNCTION public.admin_family_diary(
  p_family_id UUID,
  p_limit     INTEGER DEFAULT 30
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_limit IS NULL OR p_limit < 1 THEN p_limit := 30; END IF;
  IF p_limit > 200 THEN p_limit := 200; END IF;

  WITH family_kids AS (
    SELECT id, name FROM children
    WHERE family_id = p_family_id
      AND deleted_at IS NULL
  ),
  refl AS (
    SELECT
      'reflection'::TEXT AS kind,
      hr.reflection_at   AS event_at,
      hr.child_id        AS child_id,
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
    WHERE hr.child_id IN (SELECT id FROM family_kids)
      AND hr.reflection_status = 'reflected'
      AND hr.reflection_at IS NOT NULL
  ),
  refl_expanded AS (
    SELECT
      r.kind, r.event_at, r.child_id, r.reflection_id, r.session_id,
      r.submission_id, r.xp_pool, r.xp_split,
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
      plm.child_id       AS child_id,
      NULL::UUID         AS reflection_id,
      NULL::UUID         AS session_id,
      plm.pool_submission_id AS submission_id,
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
    WHERE plm.child_id IN (SELECT id FROM family_kids)
      AND plm.pool_submission_id IS NOT NULL
    GROUP BY plm.pool_submission_id, plm.child_id
  )
  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'event_at') DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'kind',           kind,
      'event_at',       event_at,
      'child_id',       child_id,
      'child_name',     (SELECT name FROM family_kids WHERE id = child_id),
      'reflection_id',  reflection_id,
      'session_id',     session_id,
      'submission_id',  submission_id,
      'moments',        moments,
      'xp_split',       xp_split,
      'xp_pool',        xp_pool
    ) AS row
    FROM (
      SELECT kind, event_at, child_id, reflection_id, session_id,
             submission_id, moments, xp_split, xp_pool
      FROM refl_expanded
      UNION ALL
      SELECT kind, event_at, child_id, reflection_id, session_id,
             submission_id, moments, xp_split, xp_pool
      FROM parent_logs
    ) merged
    WHERE event_at IS NOT NULL
    ORDER BY event_at DESC
    LIMIT p_limit
  ) limited;

  RETURN jsonb_build_object('rows', COALESCE(v_rows, '[]'::jsonb));
END $$;

GRANT EXECUTE ON FUNCTION public.admin_family_diary(UUID, INTEGER) TO authenticated;
