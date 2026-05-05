-- ===========================================================================
--  Migration 0031 — admin_workshop_{create,update,delete} (Module 2.2)
--
--  Three RPCs gated on admin_users (active admin or super_admin).
--  All SECURITY DEFINER, audit-logged, idempotent on create.
--
--  Push fan-out on publish: rather than a dedicated Edge Function, the
--  create/update RPCs INSERT one row per opted-in family into
--  notifications when is_published flips from FALSE→TRUE. The existing
--  notify_push_dispatch trigger (0017) picks them up and fires send-push
--  via FCM — same pattern that already works for FEATURE-001 wishes.
--  Cleaner than a parallel Edge Function: one less moving part, one
--  less deploy, identical end-user behaviour.
--
--  Reversibility:
--    DROP FUNCTION IF EXISTS admin_workshop_create(...);
--    DROP FUNCTION IF EXISTS admin_workshop_update(...);
--    DROP FUNCTION IF EXISTS admin_workshop_delete(UUID);
-- ===========================================================================

BEGIN;

-- Helper: require active admin. Used by all three RPCs. Returns the
-- admin_users.id for audit_log; throws if not authorised.
CREATE OR REPLACE FUNCTION _assert_active_admin() RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
BEGIN
  SELECT id INTO v_admin_id FROM admin_users
   WHERE auth_user_id = auth.uid() AND is_active = TRUE
   LIMIT 1;
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'not_admin'; END IF;
  RETURN v_admin_id;
END $$;

REVOKE EXECUTE ON FUNCTION _assert_active_admin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION _assert_active_admin() TO authenticated, service_role;

-- Helper: fan out workshop-published notifications. Called from
-- create/update when is_published flips TRUE.
CREATE OR REPLACE FUNCTION _fanout_workshop_published(
  p_workshop_id UUID,
  p_title TEXT,
  p_scheduled_at TIMESTAMPTZ
) RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- One notification row per family with workshop_reminders=true. The
  -- notify_push_dispatch AFTER INSERT trigger handles the FCM call per
  -- row. Walk-in / deleted / anonymised families are excluded.
  WITH inserted AS (
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    SELECT
      f.id,
      'workshop_reminder',
      'New workshop: ' || p_title,
      to_char(p_scheduled_at AT TIME ZONE 'Asia/Kolkata', 'Dy Mon DD, HH12:MIam'),
      '/club/workshops',
      p_workshop_id
    FROM families f
    WHERE f.deleted_at IS NULL
      AND f.is_anonymised = FALSE
      AND f.is_walk_in = FALSE
      AND COALESCE((f.notification_preferences->>'workshop_reminders')::BOOLEAN, TRUE) = TRUE
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_count FROM inserted;
  RETURN v_count;
END $$;

REVOKE EXECUTE ON FUNCTION _fanout_workshop_published(UUID, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _fanout_workshop_published(UUID, TEXT, TIMESTAMPTZ)
  TO service_role;

-- 1. admin_workshop_create
CREATE OR REPLACE FUNCTION admin_workshop_create(
  p_venue_id          UUID,
  p_title             TEXT,
  p_description       TEXT,
  p_scheduled_at      TIMESTAMPTZ,
  p_duration_minutes  INTEGER,
  p_age_group_min     INTEGER,
  p_age_group_max     INTEGER,
  p_capacity          INTEGER,
  p_price_paise       INTEGER,
  p_primary_trait     TEXT,
  p_xp_award          INTEGER,
  p_cover_image_url   TEXT,
  p_is_published      BOOLEAN,
  p_idempotency_key   TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id  UUID;
  v_workshop  workshops%ROWTYPE;
  v_existing  workshops%ROWTYPE;
  v_fanout    INTEGER := 0;
BEGIN
  v_admin_id := _assert_active_admin();

  IF p_capacity <= 0 THEN RAISE EXCEPTION 'invalid_capacity'; END IF;
  IF p_duration_minutes <= 0 THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  IF p_scheduled_at <= now() THEN RAISE EXCEPTION 'scheduled_at_in_past'; END IF;
  IF p_primary_trait IS NOT NULL
     AND p_primary_trait NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_primary_trait';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    -- Idempotency via title+scheduled_at lookup (workshops table has no
    -- idempotency_key column; we don't add one for a low-frequency
    -- admin action). Match on the natural key for the same admin run.
    SELECT * INTO v_existing FROM workshops
     WHERE title = p_title
       AND scheduled_at = p_scheduled_at
       AND venue_id = p_venue_id
     LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'workshop_id', v_existing.id
      );
    END IF;
  END IF;

  INSERT INTO workshops(
    venue_id, title, description, cover_image_url,
    scheduled_at, duration_minutes,
    age_group_min, age_group_max,
    capacity, spots_remaining, price_paise,
    primary_trait, xp_award, status, is_published
  ) VALUES (
    p_venue_id, p_title, p_description, p_cover_image_url,
    p_scheduled_at, p_duration_minutes,
    p_age_group_min, p_age_group_max,
    p_capacity, p_capacity, p_price_paise,
    p_primary_trait, COALESCE(p_xp_award, 100), 'upcoming',
    COALESCE(p_is_published, TRUE)
  ) RETURNING * INTO v_workshop;

  IF v_workshop.is_published THEN
    v_fanout := _fanout_workshop_published(
      v_workshop.id, v_workshop.title, v_workshop.scheduled_at
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_admin_id, 'admin', 'workshop.create', 'workshop',
    v_workshop.id, p_venue_id,
    jsonb_build_object(
      'title', p_title,
      'scheduled_at', p_scheduled_at,
      'capacity', p_capacity,
      'price_paise', p_price_paise,
      'is_published', v_workshop.is_published,
      'notifications_fanned_out', v_fanout
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'workshop_id', v_workshop.id,
    'notifications_fanned_out', v_fanout
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_workshop_create(
  UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER,
  INTEGER, INTEGER, TEXT, INTEGER, TEXT, BOOLEAN, TEXT
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_workshop_create(
  UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER,
  INTEGER, INTEGER, TEXT, INTEGER, TEXT, BOOLEAN, TEXT
) TO authenticated, service_role;

-- 2. admin_workshop_update
CREATE OR REPLACE FUNCTION admin_workshop_update(
  p_workshop_id       UUID,
  p_title             TEXT,
  p_description       TEXT,
  p_scheduled_at      TIMESTAMPTZ,
  p_duration_minutes  INTEGER,
  p_age_group_min     INTEGER,
  p_age_group_max     INTEGER,
  p_capacity          INTEGER,
  p_price_paise       INTEGER,
  p_primary_trait     TEXT,
  p_xp_award          INTEGER,
  p_cover_image_url   TEXT,
  p_is_published      BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id   UUID;
  v_old        workshops%ROWTYPE;
  v_new        workshops%ROWTYPE;
  v_fanout     INTEGER := 0;
  v_was_pub    BOOLEAN;
  v_taken      INTEGER;
BEGIN
  v_admin_id := _assert_active_admin();

  SELECT * INTO v_old FROM workshops WHERE id = p_workshop_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'workshop_not_found'; END IF;

  IF p_capacity <= 0 THEN RAISE EXCEPTION 'invalid_capacity'; END IF;

  -- spots_taken = capacity - spots_remaining. Resize with care: don't
  -- let new capacity drop below already-registered count.
  v_taken := v_old.capacity - v_old.spots_remaining;
  IF p_capacity < v_taken THEN
    RAISE EXCEPTION 'capacity_below_registrations';
  END IF;

  v_was_pub := v_old.is_published;

  UPDATE workshops SET
    title = p_title,
    description = p_description,
    cover_image_url = p_cover_image_url,
    scheduled_at = p_scheduled_at,
    duration_minutes = p_duration_minutes,
    age_group_min = p_age_group_min,
    age_group_max = p_age_group_max,
    capacity = p_capacity,
    spots_remaining = p_capacity - v_taken,
    price_paise = p_price_paise,
    primary_trait = p_primary_trait,
    xp_award = COALESCE(p_xp_award, v_old.xp_award),
    is_published = COALESCE(p_is_published, v_old.is_published)
  WHERE id = p_workshop_id RETURNING * INTO v_new;

  -- Fan out only on FALSE→TRUE transition.
  IF NOT v_was_pub AND v_new.is_published THEN
    v_fanout := _fanout_workshop_published(
      v_new.id, v_new.title, v_new.scheduled_at
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value, new_value)
  VALUES (
    v_admin_id, 'admin', 'workshop.update', 'workshop',
    v_new.id, v_new.venue_id,
    jsonb_build_object('was_published', v_was_pub),
    jsonb_build_object(
      'title', v_new.title,
      'scheduled_at', v_new.scheduled_at,
      'capacity', v_new.capacity,
      'price_paise', v_new.price_paise,
      'is_published', v_new.is_published,
      'notifications_fanned_out', v_fanout
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'workshop_id', v_new.id,
    'notifications_fanned_out', v_fanout
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_workshop_update(
  UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER,
  INTEGER, INTEGER, TEXT, INTEGER, TEXT, BOOLEAN
) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_workshop_update(
  UUID, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, INTEGER,
  INTEGER, INTEGER, TEXT, INTEGER, TEXT, BOOLEAN
) TO authenticated, service_role;

-- 3. admin_workshop_delete (soft via is_published=false)
CREATE OR REPLACE FUNCTION admin_workshop_delete(
  p_workshop_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_old      workshops%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();

  SELECT * INTO v_old FROM workshops WHERE id = p_workshop_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'workshop_not_found'; END IF;

  IF NOT v_old.is_published THEN
    -- Already unpublished — idempotent.
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'workshop_id', v_old.id
    );
  END IF;

  UPDATE workshops SET is_published = FALSE WHERE id = p_workshop_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value)
  VALUES (
    v_admin_id, 'admin', 'workshop.unpublish', 'workshop',
    v_old.id, v_old.venue_id,
    jsonb_build_object('was_published', TRUE, 'title', v_old.title)
  );

  RETURN jsonb_build_object(
    'success', true,
    'workshop_id', v_old.id,
    'is_published', FALSE
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_workshop_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_workshop_delete(UUID) TO authenticated, service_role;

COMMIT;
