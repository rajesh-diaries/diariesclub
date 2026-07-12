-- 0233 — Resolve FIT meal selections to names for the staff kitchen
--
-- Orders store FIT selections as {category_id: option_id} UUID maps
-- (order_items.selections_jsonb / fit_meal_orders.selections_jsonb), so the
-- staff kitchen could only show "Power Meal" with no idea what to actually
-- make. This SECURITY DEFINER lookup returns every option's display name +
-- its category order, so the staff app can render the real build
-- ("Palak Cream · Herb Quinoa · Classic Herb Paneer · Hummus"). DEFINER so it
-- resolves even options that have since been unpublished, and so staff don't
-- need direct RLS on the FIT config tables.

CREATE OR REPLACE FUNCTION public.staff_fit_option_labels()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
 STABLE
AS $function$
  SELECT COALESCE(
    jsonb_object_agg(
      o.id::text,
      jsonb_build_object('name', o.name, 'order', COALESCE(c.display_order, 0))
    ),
    '{}'::jsonb
  )
  FROM fit_meal_options o
  LEFT JOIN fit_meal_categories c ON c.id = o.category_id;
$function$;

REVOKE EXECUTE ON FUNCTION public.staff_fit_option_labels() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.staff_fit_option_labels() TO authenticated, service_role;
