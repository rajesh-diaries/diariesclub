-- BUG-026: Close remaining staff RLS gaps so the staff app can read its own
-- data end-to-end. Earlier rounds added staff policies on `sessions`,
-- `orders`, `tablet_devices`, `menus`, `menu_items` SELECT, `workshops`
-- (upcoming-only) and `hero_card_definitions`. This migration covers the
-- last surface area:
--
--   * `order_items`           — KDS reads items for venue orders
--   * `families`              — KDS shows family name/phone for an order
--   * `refunds`               — shift_close aggregates today's refunds
--   * `workshops`             — workshop_attendance lists all published
--                               workshops at the venue (not just upcoming)
--   * `menu_items` UPDATE     — menu_availability toggles is_available
--   * `audit_log` INSERT      — menu_availability writes audit entries
--
-- Pattern: each policy is keyed off `_is_active_tablet_for_venue(...)`
-- (existing SECURITY DEFINER helper) so the venue scope is enforced
-- by the same logic admin uses elsewhere. Sensitive surfaces (the
-- `staff` table with its pin_hash, anything mutating money) stay on
-- their existing RPC-only path.

-- order_items: items for orders at this staff's venue
DROP POLICY IF EXISTS order_items_staff_venue_read ON public.order_items;
CREATE POLICY order_items_staff_venue_read ON public.order_items
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.id = order_items.order_id
        AND public._is_active_tablet_for_venue(o.venue_id)
    )
  );

-- families: families that have placed an order or session at this venue.
-- KDS queries by specific family_id, so the EXISTS is a fast index lookup.
DROP POLICY IF EXISTS families_staff_venue_read ON public.families;
CREATE POLICY families_staff_venue_read ON public.families
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.family_id = families.id
        AND public._is_active_tablet_for_venue(o.venue_id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.sessions s
      WHERE s.family_id = families.id
        AND public._is_active_tablet_for_venue(s.venue_id)
    )
  );

-- refunds: refunds tied to a session or order at this staff's venue.
DROP POLICY IF EXISTS refunds_staff_venue_read ON public.refunds;
CREATE POLICY refunds_staff_venue_read ON public.refunds
  FOR SELECT
  TO authenticated
  USING (
    (
      refunds.reference_type = 'session'
      AND EXISTS (
        SELECT 1 FROM public.sessions s
        WHERE s.id = refunds.reference_id
          AND public._is_active_tablet_for_venue(s.venue_id)
      )
    )
    OR (
      refunds.reference_type = 'order'
      AND EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.id = refunds.reference_id
          AND public._is_active_tablet_for_venue(o.venue_id)
      )
    )
  );

-- workshops: staff at a venue can read all published workshops at that
-- venue regardless of status. The existing `workshops_public_read`
-- (status = 'upcoming') stays in place for customers; staff need to
-- see active/completed workshops too for attendance marking.
DROP POLICY IF EXISTS workshops_staff_venue_read ON public.workshops;
CREATE POLICY workshops_staff_venue_read ON public.workshops
  FOR SELECT
  TO authenticated
  USING (
    is_published = true
    AND public._is_active_tablet_for_venue(venue_id)
  );

-- menu_items: staff toggles is_available via the menu_availability
-- screen. menu_items has no venue_id (menus are global), so the policy
-- scopes by "active tablet signed in" without venue filtering. The
-- staff PIN gate in-app (StaffPinSheet) provides the per-action check.
DROP POLICY IF EXISTS menu_items_staff_toggle ON public.menu_items;
CREATE POLICY menu_items_staff_toggle ON public.menu_items
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tablet_devices td
      WHERE td.auth_user_id = auth.uid()
        AND td.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tablet_devices td
      WHERE td.auth_user_id = auth.uid()
        AND td.is_active = true
    )
  );

-- audit_log: staff can insert audit entries scoped to their own venue.
-- This lets the menu_availability toggle write its audit trail.
DROP POLICY IF EXISTS audit_log_staff_insert ON public.audit_log;
CREATE POLICY audit_log_staff_insert ON public.audit_log
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tablet_devices td
      WHERE td.auth_user_id = auth.uid()
        AND td.is_active = true
        AND td.venue_id = audit_log.venue_id
    )
  );
