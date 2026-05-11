-- 0105 — reflection screen was sampling 3-of-6 per character. Show all 6.
-- The randomization made sense when we wanted variety per recap; the bigger
-- problem is the screen feels thin, so just surface everything we have.

CREATE OR REPLACE FUNCTION public.reflection_moments_for_recap(p_recap_id uuid)
RETURNS TABLE(id uuid, tag text, display_text text, primary_trait text,
              icon text, xp_weight numeric, sort_order integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  RETURN QUERY
  SELECT rm.id, rm.tag, rm.display_text, rm.primary_trait,
         rm.icon, rm.xp_weight, rm.sort_order
    FROM reflection_moments rm
   WHERE rm.is_active = true
   ORDER BY rm.primary_trait, rm.sort_order;
END $function$;
