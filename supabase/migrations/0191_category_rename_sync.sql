BEGIN;

-- 1. Keep menu_categories in sync when a category is renamed via the admin UI.
CREATE OR REPLACE FUNCTION public.admin_menu_category_rename(
  p_brand TEXT,
  p_from TEXT,
  p_to TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated INT;
  v_trimmed_from TEXT;
  v_trimmed_to   TEXT;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  v_trimmed_from := trim(p_from);
  v_trimmed_to   := trim(p_to);

  IF v_trimmed_from IS NULL OR v_trimmed_to IS NULL OR
     length(v_trimmed_from) = 0 OR length(v_trimmed_to) = 0 THEN
    RAISE EXCEPTION 'invalid_category';
  END IF;

  IF v_trimmed_from = v_trimmed_to THEN
    RETURN jsonb_build_object('success', true, 'updated', 0);
  END IF;

  UPDATE menu_items SET
    category = v_trimmed_to,
    updated_at = now()
  WHERE menu_id IN (SELECT id FROM menus WHERE brand = p_brand)
    AND category = v_trimmed_from;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- Merge: if the target category already exists for a menu, drop the old one.
  DELETE FROM menu_categories
  WHERE menu_id IN (SELECT id FROM menus WHERE brand = p_brand)
    AND name = v_trimmed_from
    AND EXISTS (
      SELECT 1 FROM menu_categories mc2
      WHERE mc2.menu_id = menu_categories.menu_id
        AND mc2.name = v_trimmed_to
    );

  -- Rename any remaining managed category rows.
  UPDATE menu_categories SET
    name = v_trimmed_to,
    sort_order = COALESCE(
      (SELECT sort_order FROM menu_categories mc2
       WHERE mc2.menu_id = menu_categories.menu_id
         AND mc2.name = v_trimmed_to),
      sort_order
    )
  WHERE menu_id IN (SELECT id FROM menus WHERE brand = p_brand)
    AND name = v_trimmed_from;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'menu_category.rename', 'menus', NULL,
    jsonb_build_object(
      'brand', p_brand, 'from', v_trimmed_from, 'to', v_trimmed_to, 'updated', v_updated
    )
  );

  RETURN jsonb_build_object('success', true, 'updated', v_updated);
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_menu_category_rename(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_menu_category_rename(text, text, text)
  TO authenticated, service_role;

-- 2. Remove redundant authenticated-read policy now that public read exists.
DROP POLICY IF EXISTS "menu_categories_customer_read" ON menu_categories;

COMMIT;
