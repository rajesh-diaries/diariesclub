-- ===========================================================================
--  Migration 0009 — Profile tab support (Session 5b)
--
--  Adds:
--    1) families.notification_preferences JSONB (per-category toggles)
--    2) children.deleted_at TIMESTAMPTZ (soft-delete)
--    3) venue_config.pre_booking_slots_per_day JSONB (admin-tunable hourly slots)
--    4) RPCs: family_update, child_update, child_deactivate
--    5) supabase_realtime publication adds children + families
--
--  All RPCs SECURITY DEFINER, audit-logged, REVOKE-then-GRANT'd to
--  authenticated only.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. Schema additions
-- ---------------------------------------------------------------------------
ALTER TABLE families
  ADD COLUMN IF NOT EXISTS notification_preferences JSONB NOT NULL DEFAULT '{
    "session_reminders": true,
    "hero_progression": true,
    "birthday_reminders": true,
    "order_status": true,
    "wallet_alerts": true,
    "marketing": false,
    "streaks_milestones": true,
    "workshop_reminders": true
  }'::jsonb;

ALTER TABLE children
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_children_family_active
  ON children(family_id) WHERE deleted_at IS NULL;

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS pre_booking_slots_per_day JSONB NOT NULL DEFAULT
    '["10:00","11:00","12:00","13:00","14:00","15:00","16:00","17:00","18:00","19:00"]'::jsonb;

-- ---------------------------------------------------------------------------
--  2. family_update — edit family-owned profile fields
--
--  Phone is intentionally NOT editable here (changing phone == changing
--  auth identity, which means re-OTP). The Profile UI directs users to
--  contact support for phone changes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION family_update(
  p_name  TEXT,
  p_email TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_family_id UUID := auth.uid();
  v_old families%ROWTYPE;
BEGIN
  IF v_family_id IS NULL THEN RAISE EXCEPTION 'not_authorised'; END IF;

  -- Trim + validate name. RAISE captures empty / whitespace-only.
  p_name := btrim(p_name);
  IF p_name IS NULL OR length(p_name) = 0 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;
  IF length(p_name) > 80 THEN
    RAISE EXCEPTION 'invalid_name';
  END IF;

  -- Email is optional; trim + lightweight regex if non-empty.
  IF p_email IS NOT NULL THEN
    p_email := btrim(p_email);
    IF length(p_email) = 0 THEN
      p_email := NULL;
    ELSIF p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
      RAISE EXCEPTION 'invalid_email';
    END IF;
  END IF;

  SELECT * INTO v_old FROM families WHERE id = v_family_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE families SET
    name  = p_name,
    email = p_email
  WHERE id = v_family_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    v_family_id, 'customer', 'family.update', 'family', v_family_id,
    jsonb_build_object('name', v_old.name, 'email', v_old.email),
    jsonb_build_object('name', p_name,    'email', p_email)
  );

  RETURN jsonb_build_object('success', true);
END $$;

-- ---------------------------------------------------------------------------
--  3. child_update — edit a child's name/dob/photo/hero/address
--
--  Caller must own the child (family_id == auth.uid()). Each parameter is
--  optional; NULL means "leave unchanged". Empty/blank name is rejected
--  the same way family_update handles it.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION child_update(
  p_child_id          UUID,
  p_name              TEXT DEFAULT NULL,
  p_dob               DATE DEFAULT NULL,
  p_photo_url         TEXT DEFAULT NULL,
  p_favourite_hero    TEXT DEFAULT NULL,
  p_delivery_address  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_family_id UUID := auth.uid();
  v_child children%ROWTYPE;
  v_old   children%ROWTYPE;
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
BEGIN
  IF v_family_id IS NULL THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_child FROM children
    WHERE id = p_child_id AND family_id = v_family_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_child.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'child_archived'; END IF;
  v_old := v_child;

  IF p_name IS NOT NULL THEN
    p_name := btrim(p_name);
    IF length(p_name) = 0 OR length(p_name) > 60 THEN
      RAISE EXCEPTION 'invalid_name';
    END IF;
  END IF;

  IF p_dob IS NOT NULL THEN
    -- Same DOB sanity check as child_create: within last 14 years and
    -- not in the future.
    IF p_dob > v_today OR p_dob < (v_today - INTERVAL '14 years') THEN
      RAISE EXCEPTION 'invalid_dob';
    END IF;
  END IF;

  IF p_favourite_hero IS NOT NULL
     AND p_favourite_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero';
  END IF;

  UPDATE children SET
    name             = COALESCE(p_name, name),
    date_of_birth    = COALESCE(p_dob, date_of_birth),
    photo_url        = COALESCE(p_photo_url, photo_url),
    favourite_hero   = COALESCE(p_favourite_hero, favourite_hero),
    delivery_address = COALESCE(p_delivery_address, delivery_address)
  WHERE id = p_child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    v_family_id, 'customer', 'child.update', 'child', p_child_id,
    jsonb_build_object(
      'name', v_old.name, 'dob', v_old.date_of_birth,
      'photo_url', v_old.photo_url, 'favourite_hero', v_old.favourite_hero,
      'delivery_address', v_old.delivery_address
    ),
    jsonb_build_object(
      'name', COALESCE(p_name, v_old.name),
      'dob', COALESCE(p_dob, v_old.date_of_birth),
      'photo_url', COALESCE(p_photo_url, v_old.photo_url),
      'favourite_hero', COALESCE(p_favourite_hero, v_old.favourite_hero),
      'delivery_address', COALESCE(p_delivery_address, v_old.delivery_address)
    )
  );

  RETURN jsonb_build_object('success', true, 'child_id', p_child_id);
END $$;

-- ---------------------------------------------------------------------------
--  4. child_deactivate — soft-delete a child
--
--  Sets deleted_at; preserves total_xp / hero progress / history (per
--  spec: "archived but kept for records"). Blocks the last-child case
--  unless the family is_cafe_only=true (parent has explicitly opted into
--  the no-children path).
--
--  If the family had has_children=true, recompute the flag based on
--  remaining live children.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION child_deactivate(
  p_child_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_family_id    UUID := auth.uid();
  v_child        children%ROWTYPE;
  v_remaining    INTEGER;
  v_is_cafe_only BOOLEAN;
BEGIN
  IF v_family_id IS NULL THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_child FROM children
    WHERE id = p_child_id AND family_id = v_family_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_child.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  -- Last-child guard: must have another live child OR family must be
  -- explicitly cafe-only.
  SELECT COUNT(*) INTO v_remaining FROM children
    WHERE family_id = v_family_id
      AND deleted_at IS NULL
      AND id <> p_child_id;
  SELECT is_cafe_only INTO v_is_cafe_only FROM families WHERE id = v_family_id;
  IF v_remaining = 0 AND v_is_cafe_only IS NOT TRUE THEN
    RAISE EXCEPTION 'cannot_remove_only_child';
  END IF;

  UPDATE children SET deleted_at = now() WHERE id = p_child_id;

  -- Maintain families.has_children mirror.
  IF v_remaining = 0 THEN
    UPDATE families SET has_children = false WHERE id = v_family_id;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (
    v_family_id, 'customer', 'child.deactivate', 'child', p_child_id,
    jsonb_build_object('name', v_child.name),
    jsonb_build_object('deleted_at', now())
  );

  RETURN jsonb_build_object('success', true);
END $$;

-- ---------------------------------------------------------------------------
--  5. Permissions — REVOKE-then-GRANT pattern (matches 0003/0006).
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION family_update(TEXT, TEXT)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION child_update(UUID, TEXT, DATE, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION child_deactivate(UUID)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION family_update(TEXT, TEXT)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION child_update(UUID, TEXT, DATE, TEXT, TEXT, TEXT)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION child_deactivate(UUID)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
--  6. Realtime publication — children + families.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY['children', 'families'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
        v_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
