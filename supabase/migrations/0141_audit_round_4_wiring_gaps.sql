-- 0141 — round 4 customer/staff/admin wiring gaps.
--
-- 1. Add stage_perk_grants to supabase_realtime so the customer's profile
--    immediately reflects a staff redemption (clears the perk card).
-- 2. staff_workshop_mark_attended — staff app wrapper around the
--    existing workshop_attend RPC. workshop_attend is service-role only;
--    the staff app runs as `authenticated` via a tablet device, so we
--    need a SECURITY DEFINER wrapper that asserts tablet auth and
--    forwards to workshop_attend. This credits XP via the standard
--    splitter, marks attended=TRUE, and fires the quest hooks.
-- 3. staff_workshop_list_registrations — list view for the staff
--    workshop-attendance screen. Returns kid name + age + attended
--    state. Tablet-gated.
-- 4. admin_notification_broadcast — admin composes a notification once,
--    fans out one row per family in `notifications`. The customer inbox
--    is already wired to that table, so the notification + unread badge
--    appears the moment the broadcast lands.

BEGIN;

-- 1. Realtime publication ----------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND tablename = 'stage_perk_grants'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE stage_perk_grants';
  END IF;
END $$;

-- 2. staff_workshop_mark_attended -------------------------------------------

CREATE OR REPLACE FUNCTION public.staff_workshop_mark_attended(
  p_registration_id UUID,
  p_staff_pin_id    UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reg     workshop_registrations%ROWTYPE;
  v_wshop   workshops%ROWTYPE;
  v_result  JSONB;
BEGIN
  SELECT * INTO v_reg FROM workshop_registrations
    WHERE id = p_registration_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'registration_not_found'; END IF;

  SELECT * INTO v_wshop FROM workshops WHERE id = v_reg.workshop_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'workshop_not_found'; END IF;

  IF NOT _is_active_tablet_for_venue(v_wshop.venue_id) THEN
    RAISE EXCEPTION 'not_authorised_for_venue';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = v_wshop.venue_id
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'staff_pin_invalid';
  END IF;

  -- Forward to the existing service-role function. workshop_attend
  -- handles idempotency (returns idempotent=true if already marked),
  -- credits XP via xp_credit_with_split, and flips attended=TRUE.
  v_result := workshop_attend(p_registration_id, p_staff_pin_id);
  RETURN v_result;
END $$;

REVOKE EXECUTE ON FUNCTION public.staff_workshop_mark_attended(UUID, UUID)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.staff_workshop_mark_attended(UUID, UUID)
  TO authenticated, service_role;

-- 3. staff_workshop_list_registrations --------------------------------------

CREATE OR REPLACE FUNCTION public.staff_workshop_list_registrations(
  p_workshop_id UUID
) RETURNS TABLE (
  id              UUID,
  child_id        UUID,
  child_name      TEXT,
  child_dob       DATE,
  family_phone    TEXT,
  attended        BOOLEAN,
  cancelled_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue UUID;
BEGIN
  SELECT venue_id INTO v_venue FROM workshops WHERE id = p_workshop_id;
  IF v_venue IS NULL THEN RAISE EXCEPTION 'workshop_not_found'; END IF;
  IF NOT _is_active_tablet_for_venue(v_venue) THEN
    RAISE EXCEPTION 'not_authorised_for_venue';
  END IF;

  RETURN QUERY
    SELECT
      r.id, r.child_id,
      c.name AS child_name,
      c.date_of_birth AS child_dob,
      f.phone AS family_phone,
      r.attended, r.cancelled_at, r.created_at
    FROM workshop_registrations r
    JOIN children c ON c.id = r.child_id
    JOIN families f ON f.id = r.family_id
    WHERE r.workshop_id = p_workshop_id
    ORDER BY r.created_at ASC;
END $$;

REVOKE EXECUTE ON FUNCTION public.staff_workshop_list_registrations(UUID)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.staff_workshop_list_registrations(UUID)
  TO authenticated, service_role;

-- 4. admin_notification_broadcast -------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_notification_broadcast(
  p_title     TEXT,
  p_body      TEXT,
  p_deep_link TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RAISE EXCEPTION 'title_required';
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RAISE EXCEPTION 'body_required';
  END IF;
  IF length(p_title) > 80 THEN RAISE EXCEPTION 'title_too_long (max 80)'; END IF;
  IF length(p_body) > 240 THEN RAISE EXCEPTION 'body_too_long (max 240)'; END IF;

  -- Fan out: one notification row per active family. The customer inbox
  -- listens to `notifications` and shows the unread badge automatically.
  INSERT INTO notifications(family_id, title, body, deep_link, is_read)
  SELECT f.id, p_title, p_body, p_deep_link, FALSE
  FROM families f
  WHERE f.deleted_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, new_value)
  VALUES (
    auth.uid(), 'admin', 'notification.broadcast', 'notification',
    jsonb_build_object(
      'title', p_title,
      'body', p_body,
      'deep_link', p_deep_link,
      'recipient_count', v_count
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'recipient_count', v_count
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_notification_broadcast(TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_notification_broadcast(TEXT, TEXT, TEXT)
  TO authenticated, service_role;

COMMIT;
