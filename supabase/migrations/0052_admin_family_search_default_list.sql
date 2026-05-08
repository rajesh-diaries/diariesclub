-- ===========================================================================
--  Migration 0052 — admin_family_search returns recent families when
--                   the query is empty, so the Customers admin tab has a
--                   useful default list on first open.
--
--  Founder UX feedback (BUG-052):
--    The Customers tab opened blank with "No results yet. Search by
--    phone, family name, or child name." Founder expected to see a list
--    of existing customers immediately, then narrow with the search.
--
--  Behaviour change:
--    p_query NULL or trimmed length < 2 →
--      previously returned an empty list.
--      now returns the most-recently-active non-walk-in, non-deleted
--      families up to p_limit, sorted by last_visit DESC NULLS LAST.
--    p_query length >= 2 → unchanged (substring match on phone /
--      family name / child name).
--
--  Permission unchanged — still requires is_admin() on the caller.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.admin_family_search(
  p_query text,
  p_limit integer DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_q       TEXT;
  v_default BOOLEAN;
  v_results JSONB;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  v_q := lower(trim(coalesce(p_query, '')));
  v_default := (length(v_q) < 2);

  SELECT COALESCE(jsonb_agg(t ORDER BY t->>'last_visit' DESC NULLS LAST), '[]'::jsonb)
    INTO v_results
    FROM (
      SELECT jsonb_build_object(
        'id', f.id,
        'name', f.name,
        'phone', f.phone,
        'is_walk_in', f.is_walk_in,
        'is_anonymised', f.is_anonymised,
        'children', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name))
            FROM children c
           WHERE c.family_id = f.id AND c.deleted_at IS NULL
        ), '[]'::jsonb),
        'wallet_balance_paise', COALESCE(
          (SELECT balance_paise FROM wallets w WHERE w.family_id = f.id), 0
        ),
        'last_visit', (
          SELECT MAX(s.created_at)::TEXT FROM sessions s WHERE s.family_id = f.id
        )
      ) AS t
        FROM families f
       WHERE f.deleted_at IS NULL
         AND f.is_walk_in = false
         AND (
              v_default
           OR f.phone LIKE '%' || v_q || '%'
           OR lower(f.name) LIKE '%' || v_q || '%'
           OR EXISTS (
                SELECT 1 FROM children c
                 WHERE c.family_id = f.id
                   AND c.deleted_at IS NULL
                   AND lower(c.name) LIKE '%' || v_q || '%'
              )
         )
       LIMIT p_limit
    ) sub;

  RETURN jsonb_build_object(
    'results', v_results,
    'is_default_list', v_default
  );
END $function$;
