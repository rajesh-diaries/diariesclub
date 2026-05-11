-- 0092 — fix menu_items RLS so 'Hide' actually hides from customer
--
-- Bug: 'Hide item' in admin set is_published=false but the customer's
-- /club menu kept showing the row because the public-read policy only
-- checked is_available=true. Tighten the predicate so unpublished
-- items disappear from customer-facing reads.
--
-- Add an explicit is_active_admin() policy so admin can still see +
-- toggle hidden items in the catalog list. Same for menus join.

DROP POLICY IF EXISTS menu_items_public_read ON menu_items;
CREATE POLICY menu_items_public_read ON menu_items
  FOR SELECT USING (is_available = true AND is_published = true);

DROP POLICY IF EXISTS menu_items_admin_read ON menu_items;
CREATE POLICY menu_items_admin_read ON menu_items
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS menus_admin_read ON menus;
CREATE POLICY menus_admin_read ON menus
  FOR SELECT USING (is_active_admin());
