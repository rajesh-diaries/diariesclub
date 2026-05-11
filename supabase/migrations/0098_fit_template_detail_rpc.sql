-- 0098 — fit_template_detail RPC
--
-- The customer builder screen was reading fit_meal_templates,
-- fit_meal_template_categories, fit_meal_categories, and
-- fit_meal_options via four separate PostgREST round-trips and
-- something on the RLS chain was returning empty for the linker
-- table (despite identical SQL working as authenticated when run
-- from MCP). Replace with a single SECURITY DEFINER RPC that
-- bypasses RLS and returns the entire builder payload.

CREATE OR REPLACE FUNCTION public.fit_template_detail(
  p_template_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_template JSONB;
  v_sections JSONB := '[]'::jsonb;
BEGIN
  SELECT to_jsonb(t) INTO v_template
    FROM fit_meal_templates t
   WHERE t.id = p_template_id
     AND t.is_published = true
     AND t.is_available = true;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'template_not_found_or_unavailable';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'category',  to_jsonb(c.*),
    'linker',    to_jsonb(tc.*),
    'options',   COALESCE(opts_arr, '[]'::jsonb)
  ) ORDER BY tc.display_order), '[]'::jsonb)
  INTO v_sections
  FROM fit_meal_template_categories tc
  JOIN fit_meal_categories c ON c.id = tc.category_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(to_jsonb(o.*) ORDER BY o.display_order, o.name) AS opts_arr
      FROM fit_meal_options o
     WHERE o.category_id = c.id
       AND o.is_published = true
       AND o.is_available = true
  ) opts ON true
  WHERE tc.template_id = p_template_id;

  RETURN jsonb_build_object(
    'template', v_template,
    'sections', v_sections
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.fit_template_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fit_template_detail(uuid) TO authenticated, anon;
