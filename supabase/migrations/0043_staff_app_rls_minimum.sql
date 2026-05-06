-- BUG-026 minimum-fix migration. The staff app's client-side providers
-- (`currentTabletDeviceProvider`, `venueActiveSessionsProvider`,
-- `venueOrdersProvider`) read tables directly via `.from(...).select()`.
-- RLS was enabled on those tables but no staff/tablet-aware policies
-- existed, so the reads returned empty for any authenticated staff
-- user. The login screen then sees `device == null` and signs the user
-- back out — visible on web today, masked on phone earlier by a router
-- redirect race.
--
-- Scope of this migration: ONLY enough to unblock login + the home-screen
-- realtime streams. The wider design pass (SECURITY DEFINER RPCs vs full
-- staff-role policies) is still pending; treat this as the unblocker, not
-- the final answer.

-- ---------------------------------------------------------------------
-- 1. tablet_devices — a signed-in user can read their own active row.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS tablet_devices_self_read ON public.tablet_devices;
CREATE POLICY tablet_devices_self_read ON public.tablet_devices
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

COMMENT ON POLICY tablet_devices_self_read ON public.tablet_devices IS
'BUG-026 unblocker — staff app login screen reads its own device row '
'via currentTabletDeviceProvider. is_active filter is applied client-side '
'so admins can audit revoked devices without changing the policy.';

-- ---------------------------------------------------------------------
-- 2. sessions — staff at a venue can read live sessions there.
-- ---------------------------------------------------------------------
-- We layer on top of the existing `sessions_family` policy (each policy
-- is OR'd), so families keep their existing read access AND staff/tablet
-- users get venue-scoped reads. The "is the caller a staff/tablet user
-- for this venue" check is: their auth.uid() owns an active row in
-- tablet_devices for this venue.
CREATE OR REPLACE FUNCTION public._is_active_tablet_for_venue(p_venue_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM tablet_devices
    WHERE auth_user_id = auth.uid()
      AND venue_id = p_venue_id
      AND is_active = true
  );
$$;

REVOKE EXECUTE ON FUNCTION public._is_active_tablet_for_venue(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public._is_active_tablet_for_venue(uuid) TO authenticated;

DROP POLICY IF EXISTS sessions_staff_venue_read ON public.sessions;
CREATE POLICY sessions_staff_venue_read ON public.sessions
  FOR SELECT TO authenticated
  USING (_is_active_tablet_for_venue(venue_id));

DROP POLICY IF EXISTS orders_staff_venue_read ON public.orders;
CREATE POLICY orders_staff_venue_read ON public.orders
  FOR SELECT TO authenticated
  USING (_is_active_tablet_for_venue(venue_id));

COMMENT ON POLICY sessions_staff_venue_read ON public.sessions IS
'BUG-026 unblocker — staff/tablet users can read sessions at their own '
'venue. Layered with sessions_family (families read their own).';

COMMENT ON POLICY orders_staff_venue_read ON public.orders IS
'BUG-026 unblocker — staff/tablet users can read orders at their own venue.';

-- ---------------------------------------------------------------------
-- 3. staff table intentionally NOT exposed via RLS. PIN verification
--    runs server-side via verify_staff_pin RPC; the client has no
--    legitimate reason to read pin_hash directly. Leave as-is.
-- ---------------------------------------------------------------------
