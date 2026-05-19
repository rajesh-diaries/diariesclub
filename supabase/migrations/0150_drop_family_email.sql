-- 0150 — Drop families.email column.
--
-- We never asked for an email at signup (only phone OTP) and decided not to
-- start. The column was nullable and only writable through family_update;
-- existing rows are all NULL. See docs/POLICY_INVENTORY.md §2.5 — "we
-- deliberately do not collect or store email".
--
-- This migration:
--   1. Drops the old family_update(text, text) signature.
--   2. Re-creates family_update(p_name text) — single-arg, name only.
--   3. Drops families.email column.

DROP FUNCTION IF EXISTS public.family_update(text, text);

CREATE OR REPLACE FUNCTION public.family_update(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_family_id UUID := auth.uid();
  v_old families%ROWTYPE;
BEGIN
  IF v_family_id IS NULL THEN RAISE EXCEPTION 'not_authorised'; END IF;

  p_name := btrim(p_name);
  IF p_name IS NULL OR length(p_name) = 0 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;
  IF length(p_name) > 80 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;

  SELECT * INTO v_old FROM families WHERE id = v_family_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE families SET name = p_name WHERE id = v_family_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    v_family_id, 'customer', 'family.update', 'family', v_family_id,
    jsonb_build_object('name', v_old.name),
    jsonb_build_object('name', p_name)
  );

  RETURN jsonb_build_object('success', true);
END $function$;

ALTER TABLE public.families DROP COLUMN IF EXISTS email;
