-- ===========================================================================
--  Migration 0014 — Birthday funnel (Session 9)
--
--  Locked decisions for v1:
--    * NO online deposit. Reservation flow submits "interest"; admin
--      collects deposit offline and progresses status manually.
--    * Status state machine simplified to:
--        interested → admin_contacted → confirmed → completed
--                                              → cancelled / no_show
--    * Birthday-exclusive hero card auto-awarded on completion (1 per hero
--      = 4 cards) + 1000 XP split across 4 traits.
--    * Album published by admin via separate RPC; flips `album_ready_at`.
--    * Stage-transition + nearby-birthday triggers a one-time funnel nudge
--      via xp_credit_with_split (dedupe on
--      birthday_journey_state.hero_progression_trigger_sent).
--
--  Includes:
--    1) Status enum migration with row mapping.
--    2) Schema additions: preferred_month / preferred_window /
--       special_requests; nullable slot_date trio.
--    3) birthday_party_photos.uploaded_by_pin → nullable + uploaded_by_admin
--       column + check constraint.
--    4) 4 birthday-exclusive hero cards seeded (placeholder names + URLs).
--    5) DROP + CREATE birthday_reservation_create with the new signature.
--    6) NEW birthday_reservation_complete (admin-only).
--    7) NEW birthday_album_publish (admin-only).
--    8) NEW birthday_reservation_cancel (customer-callable; rejects on
--       confirmed → 'cancel_requires_admin').
--    9) CREATE OR REPLACE xp_credit_with_split with inline hero-progression
--       nudge.
--   10) supabase_realtime publication adds for birthday_reservations,
--       birthday_party_photos, birthday_journey_state.
--
--  TODO(founder): wordsmith the 4 birthday-exclusive card names + commission
--  cake-themed artwork (currently placehold.co URLs).
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. Status enum migration
-- ---------------------------------------------------------------------------
ALTER TABLE birthday_reservations
  DROP CONSTRAINT IF EXISTS birthday_reservations_status_check;

UPDATE birthday_reservations
   SET status = 'interested'
 WHERE status = 'reserved';

UPDATE birthday_reservations
   SET status = 'admin_contacted'
 WHERE status = 'deposit_paid';

ALTER TABLE birthday_reservations
  ADD CONSTRAINT birthday_reservations_status_check
  CHECK (status IN (
    'interested',
    'admin_contacted',
    'confirmed',
    'completed',
    'cancelled',
    'no_show'
  ));

ALTER TABLE birthday_reservations
  ALTER COLUMN status SET DEFAULT 'interested';

-- ---------------------------------------------------------------------------
--  2. Schema additions on birthday_reservations
-- ---------------------------------------------------------------------------
ALTER TABLE birthday_reservations
  ALTER COLUMN slot_date       DROP NOT NULL,
  ALTER COLUMN slot_start_time DROP NOT NULL,
  ALTER COLUMN slot_end_time   DROP NOT NULL;

ALTER TABLE birthday_reservations
  ADD COLUMN IF NOT EXISTS preferred_month   TEXT,
  ADD COLUMN IF NOT EXISTS preferred_window  TEXT
    CHECK (preferred_window IS NULL
           OR preferred_window IN (
             'weekend_morning',
             'weekend_afternoon',
             'weekend_evening',
             'weekday_evening'
           )),
  ADD COLUMN IF NOT EXISTS special_requests  TEXT
    CHECK (special_requests IS NULL OR length(special_requests) <= 200);

COMMENT ON COLUMN birthday_reservations.deposit_paid_paise IS
  'Informational only — admin records this after collecting deposit offline (cash/UPI).';
COMMENT ON COLUMN birthday_reservations.reservation_expires_at IS
  'Auto-cancel if status remains interested past this. Default: 72h after submission. Cron in Session 13 enforces.';

-- ---------------------------------------------------------------------------
--  3. birthday_party_photos: admin uploader path
-- ---------------------------------------------------------------------------
ALTER TABLE birthday_party_photos
  ALTER COLUMN uploaded_by_pin DROP NOT NULL;

ALTER TABLE birthday_party_photos
  ADD COLUMN IF NOT EXISTS uploaded_by_admin UUID REFERENCES auth.users(id);

ALTER TABLE birthday_party_photos
  DROP CONSTRAINT IF EXISTS photo_uploader_required;
ALTER TABLE birthday_party_photos
  ADD CONSTRAINT photo_uploader_required
  CHECK (uploaded_by_pin IS NOT NULL OR uploaded_by_admin IS NOT NULL);

-- ---------------------------------------------------------------------------
--  4. Seed 4 birthday-exclusive hero cards (1 per hero, common rarity)
--     TODO(founder): wordsmith names + commission cake-themed artwork.
-- ---------------------------------------------------------------------------
INSERT INTO hero_card_definitions (name, hero, is_rare, is_birthday_exclusive, image_url, description)
VALUES
  ('Birthday Brave',              'rafi',  false, true,
   'https://placehold.co/600x800/E8524A/FFE066.png?text=Birthday+Brave',
   "A birthday courage card. Earned on a Diaries Club celebration."),
  ('Birthday Hero of Kindness',   'ellie', false, true,
   'https://placehold.co/600x800/5BC8E8/FFE066.png?text=Birthday+Kindness',
   "A birthday kindness card. Earned on a Diaries Club celebration."),
  ('Birthday Discovery',          'gerry', false, true,
   'https://placehold.co/600x800/F0A830/FFE066.png?text=Birthday+Discovery',
   "A birthday curiosity card. Earned on a Diaries Club celebration."),
  ('Birthday Imagination',        'zena',  false, true,
   'https://placehold.co/600x800/7BC74D/FFE066.png?text=Birthday+Imagination',
   "A birthday creativity card. Earned on a Diaries Club celebration.")
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
--  5. birthday_reservation_create — new signature
--
--  Old function had (uuid, uuid, uuid, uuid, date, time, integer, integer,
--  text, text). The signature change means a CREATE OR REPLACE alone
--  doesn't replace the old function — drop it explicitly first so the
--  GRANTs reset cleanly too.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS birthday_reservation_create(
  UUID, UUID, UUID, UUID, DATE, TIME, INTEGER, INTEGER, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION birthday_reservation_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_package_id UUID,
  p_preferred_month TEXT,
  p_preferred_window TEXT,
  p_num_kids INTEGER,
  p_num_adults INTEGER,
  p_special_requests TEXT DEFAULT NULL,
  p_triggered_by TEXT DEFAULT 'manual',
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
  v_res birthday_reservations%ROWTYPE;
  v_birthday_year INTEGER;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'reservation_id', v_existing.id,
        'expires_at', v_existing.reservation_expires_at
      );
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages
    WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  -- Block: already an active reservation for this child this birthday year?
  IF EXISTS (
    SELECT 1 FROM birthday_reservations
     WHERE child_id = p_child_id
       AND status IN ('interested', 'admin_contacted', 'confirmed')
       AND created_at > now() - INTERVAL '1 year'
  ) THEN
    RAISE EXCEPTION 'reservation_exists';
  END IF;

  IF p_num_kids   <= 0 OR p_num_kids   > v_pkg.max_kids   THEN RAISE EXCEPTION 'invalid_kids';   END IF;
  IF p_num_adults <  0 OR p_num_adults > v_pkg.max_adults THEN RAISE EXCEPTION 'invalid_adults'; END IF;

  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    preferred_month, preferred_window, special_requests,
    num_kids, num_adults,
    package_price_paise, balance_paise,
    triggered_by, reservation_expires_at,
    idempotency_key, status
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_package_id,
    p_preferred_month, p_preferred_window, p_special_requests,
    p_num_kids, p_num_adults,
    v_pkg.price_paise, v_pkg.price_paise, -- balance = full until admin records deposit
    p_triggered_by,
    now() + INTERVAL '72 hours',
    p_idempotency_key, 'interested'
  ) RETURNING * INTO v_res;

  -- Create or update the journey-state row so the Session 13 cron knows
  -- this child is now in the funnel (arc_type='reserved') and skips
  -- generic D-N nudges that have already been swept up by the funnel.
  -- birthday_year is just the calendar year the row was last about; the
  -- cron computes day-N math from children.date_of_birth at runtime.
  v_birthday_year := EXTRACT(YEAR FROM now())::INTEGER;

  INSERT INTO birthday_journey_state(child_id, reservation_id, birthday_year, arc_type)
  VALUES (p_child_id, v_res.id, v_birthday_year, 'reserved')
  ON CONFLICT (child_id) DO UPDATE
    SET reservation_id = EXCLUDED.reservation_id,
        arc_type       = 'reserved',
        updated_at     = now();

  -- Acknowledgement notification.
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    p_family_id, 'birthday_d_minus_90',
    'Reservation request received!',
    'Our team will WhatsApp you within 24 hours to confirm.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'birthday.reserve_interest', 'birthday_reservation',
          v_res.id, p_venue_id,
          jsonb_build_object(
            'package_id', p_package_id,
            'kids', p_num_kids, 'adults', p_num_adults,
            'preferred_month', p_preferred_month,
            'preferred_window', p_preferred_window,
            'triggered_by', p_triggered_by
          ));

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id,
    'expires_at', v_res.reservation_expires_at
  );
END $$;

REVOKE EXECUTE ON FUNCTION birthday_reservation_create(
  UUID, UUID, UUID, UUID, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION birthday_reservation_create(
  UUID, UUID, UUID, UUID, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT
) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
--  6. birthday_reservation_complete (admin-only)
--
--  Awards 4 birthday-exclusive cards (1 per hero) + 1000 XP split equally.
--  Picks the matching is_birthday_exclusive=true card per hero; if a child
--  has already collected one (re-running by mistake), ON CONFLICT skips.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION birthday_reservation_complete(
  p_reservation_id UUID,
  p_admin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_card_ids UUID[] := ARRAY[]::UUID[];
  v_hero TEXT;
  v_card hero_card_definitions%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('confirmed') THEN
    RAISE EXCEPTION 'invalid_state_for_completion';
  END IF;

  -- Award one birthday-exclusive card per hero.
  FOREACH v_hero IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = true
        AND hero = v_hero
        AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection
                        WHERE child_id = v_res.child_id)
      ORDER BY random() LIMIT 1;

    IF FOUND THEN
      INSERT INTO hero_card_collection(child_id, card_id, birthday_booking_id)
      VALUES (v_res.child_id, v_card.id, v_res.id)
      ON CONFLICT (child_id, card_id) DO NOTHING;
      v_card_ids := array_append(v_card_ids, v_card.id);
    END IF;
  END LOOP;

  -- 1000 XP split equally across the 4 traits.
  PERFORM xp_credit_with_split(
    v_res.child_id, v_res.family_id, v_res.venue_id,
    'birthday_hosted',
    250, 250, 250, 250,
    v_res.id,
    jsonb_build_object('reservation_id', v_res.id)
  );

  -- Pick a representative card_id for the legacy birthday_hero_card_id
  -- column (kept for downstream code that expected a single card).
  UPDATE birthday_reservations SET
    status = 'completed',
    birthday_hero_card_id = COALESCE(v_card_ids[1], birthday_hero_card_id)
  WHERE id = p_reservation_id;

  -- Notify parent.
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_plus_1',
    'Thank you for celebrating with us!',
    'Special birthday hero cards have been added to your collection. '
    'Photos coming in 3-5 days.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_admin_id, 'admin', 'birthday.complete', 'birthday_reservation',
          v_res.id, v_res.venue_id,
          jsonb_build_object('hero_card_ids', to_jsonb(v_card_ids)));

  RETURN jsonb_build_object(
    'success', true,
    'card_ids', to_jsonb(v_card_ids)
  );
END $$;

REVOKE EXECUTE ON FUNCTION birthday_reservation_complete(UUID, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION birthday_reservation_complete(UUID, UUID)
  TO service_role;

-- ---------------------------------------------------------------------------
--  7. birthday_album_publish (admin-only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION birthday_album_publish(
  p_reservation_id UUID,
  p_admin_id UUID,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_photo_count INTEGER;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status <> 'completed' THEN RAISE EXCEPTION 'invalid_state_for_album'; END IF;

  IF v_res.album_ready_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'album_ready_at', v_res.album_ready_at
    );
  END IF;

  SELECT COUNT(*) INTO v_photo_count FROM birthday_party_photos
    WHERE reservation_id = p_reservation_id;
  IF v_photo_count = 0 THEN RAISE EXCEPTION 'no_photos'; END IF;

  UPDATE birthday_reservations SET album_ready_at = now()
   WHERE id = p_reservation_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_album_ready',
    'Photo album is ready!',
    'See ' || v_photo_count || ' photo' || CASE WHEN v_photo_count = 1 THEN '' ELSE 's' END
      || ' from the celebration.',
    '/birthday/album/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_admin_id, 'admin', 'birthday.album_publish', 'birthday_reservation',
          v_res.id, v_res.venue_id,
          jsonb_build_object('photo_count', v_photo_count));

  RETURN jsonb_build_object('success', true, 'photo_count', v_photo_count);
END $$;

REVOKE EXECUTE ON FUNCTION birthday_album_publish(UUID, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION birthday_album_publish(UUID, UUID, TEXT)
  TO service_role;

-- ---------------------------------------------------------------------------
--  8. birthday_reservation_cancel (customer-callable)
--
--  Customer can cancel their own reservation only when it's still in
--  'interested' or 'admin_contacted'. 'confirmed' raises
--  'cancel_requires_admin' — the client maps that to a "Contact us"
--  WhatsApp deep link. Terminal statuses raise 'already_terminal'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION birthday_reservation_cancel(
  p_reservation_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  PERFORM assert_caller_authority(v_res.family_id, NULL);

  IF v_res.status IN ('completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'already_terminal';
  END IF;
  IF v_res.status = 'confirmed' THEN
    RAISE EXCEPTION 'cancel_requires_admin';
  END IF;

  UPDATE birthday_reservations SET
    status = 'cancelled',
    cancelled_reason = p_reason,
    cancelled_at = now()
  WHERE id = p_reservation_id;

  -- Mark the journey state paused so cron stops nudging.
  UPDATE birthday_journey_state SET
    arc_type = 'paused',
    updated_at = now()
  WHERE child_id = v_res.child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (v_res.family_id, 'customer', 'birthday.cancel', 'birthday_reservation',
          v_res.id, v_res.venue_id,
          jsonb_build_object('reason', p_reason));

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION birthday_reservation_cancel(UUID, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION birthday_reservation_cancel(UUID, TEXT)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
--  9. xp_credit_with_split — add inline hero-progression nudge
--
--  After the existing transitions/imminent logic, check if any transition
--  fired AND the child has a birthday in 14-90 days AND no active
--  reservation AND birthday_journey_state.hero_progression_trigger_sent
--  is false. If so, push a "your child just leveled up + birthday in N
--  days" notification and flip the dedupe flag.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION xp_credit_with_split(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_event_type TEXT,
  p_xp_rafi  INTEGER DEFAULT 0,
  p_xp_ellie INTEGER DEFAULT 0,
  p_xp_gerry INTEGER DEFAULT 0,
  p_xp_zena  INTEGER DEFAULT 0,
  p_reference_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_overall_thresholds JSONB;
  v_trait_thresholds   JSONB;
  v_imminent_gap INTEGER;
  v_new_total INTEGER;
  v_new_level INTEGER := 1;
  v_new_overall_stage TEXT;
  v_old_stages JSONB;
  v_new_stages JSONB := '{}'::JSONB;
  v_transitions JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_next_threshold INTEGER;
  v_next_stage_label TEXT;
  v_dob DATE;
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_next_birthday DATE;
  v_days_until INTEGER;
  v_already_sent BOOLEAN;
  i INTEGER;
BEGIN
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds   := v_config.stage_thresholds_per_trait;
  v_imminent_gap       := v_config.stage_imminent_xp_gap;

  SELECT * INTO v_child FROM children WHERE id = p_child_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  v_old_stages := jsonb_build_object(
    'rafi',  v_child.stage_rafi,  'ellie', v_child.stage_ellie,
    'gerry', v_child.stage_gerry, 'zena',  v_child.stage_zena
  );

  UPDATE children SET
    xp_rafi  = xp_rafi  + p_xp_rafi,
    xp_ellie = xp_ellie + p_xp_ellie,
    xp_gerry = xp_gerry + p_xp_gerry,
    xp_zena  = xp_zena  + p_xp_zena
  WHERE id = p_child_id RETURNING * INTO v_child;

  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;
    v_new_stage := 'seedling';
    FOR i IN 0..(jsonb_array_length(v_trait_thresholds) - 1) LOOP
      IF v_trait_xp >= (v_trait_thresholds->>i)::INTEGER THEN
        v_new_stage := CASE i
          WHEN 0 THEN 'seedling'  WHEN 1 THEN 'explorer'
          WHEN 2 THEN 'adventurer' WHEN 3 THEN 'champion'
          ELSE 'legend'
        END;
      END IF;
    END LOOP;
    v_new_stages := v_new_stages || jsonb_build_object(v_trait, v_new_stage);
    v_old_stage := v_old_stages->>v_trait;
    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_array(
        jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage)
      );
    END IF;
  END LOOP;

  v_new_total := v_child.xp_rafi + v_child.xp_ellie + v_child.xp_gerry + v_child.xp_zena;
  FOR i IN 0..(jsonb_array_length(v_overall_thresholds) - 1) LOOP
    IF v_new_total >= (v_overall_thresholds->>i)::INTEGER THEN
      v_new_level := i + 1;
    END IF;
  END LOOP;

  v_new_overall_stage := CASE
    WHEN v_new_level <= 3  THEN 'seedling'
    WHEN v_new_level <= 6  THEN 'explorer'
    WHEN v_new_level <= 12 THEN 'adventurer'
    WHEN v_new_level <= 18 THEN 'champion'
    ELSE 'legend'
  END;

  UPDATE children SET
    stage_rafi  = v_new_stages->>'rafi',
    stage_ellie = v_new_stages->>'ellie',
    stage_gerry = v_new_stages->>'gerry',
    stage_zena  = v_new_stages->>'zena',
    total_xp = v_new_total,
    current_level = v_new_level,
    current_overall_stage = v_new_overall_stage
  WHERE id = p_child_id;

  INSERT INTO xp_events(
    child_id, family_id, venue_id, event_type,
    xp_rafi, xp_ellie, xp_gerry, xp_zena,
    reference_id, metadata
  ) VALUES (
    p_child_id, p_family_id, p_venue_id, p_event_type,
    p_xp_rafi, p_xp_ellie, p_xp_gerry, p_xp_zena,
    p_reference_id, p_metadata || jsonb_build_object('stage_transitions', v_transitions)
  );

  IF jsonb_array_length(v_transitions) > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      v_child.name || ' just leveled up!',
      'See the new look in their adventure tab.',
      '/adventure', p_child_id
    );
  END IF;

  -- Stage-imminent notifications (existing 0010 logic).
  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;
    v_next_threshold := NULL;
    v_next_stage_label := NULL;
    FOR i IN 0..(jsonb_array_length(v_trait_thresholds) - 1) LOOP
      IF (v_trait_thresholds->>i)::INTEGER > v_trait_xp THEN
        v_next_threshold := (v_trait_thresholds->>i)::INTEGER;
        v_next_stage_label := CASE i
          WHEN 1 THEN 'explorer'  WHEN 2 THEN 'adventurer'
          WHEN 3 THEN 'champion'  WHEN 4 THEN 'legend'
          ELSE NULL
        END;
        EXIT;
      END IF;
    END LOOP;

    IF v_next_threshold IS NOT NULL
       AND v_next_stage_label IS NOT NULL
       AND (v_next_threshold - v_trait_xp) <= v_imminent_gap
       AND NOT EXISTS (
         SELECT 1 FROM notifications
          WHERE family_id = p_family_id
            AND type = 'stage_transition_imminent'
            AND reference_id = p_child_id
            AND metadata->>'trait' = v_trait
            AND metadata->>'threshold_label' = v_next_stage_label
            AND created_at > now() - INTERVAL '24 hours'
       )
    THEN
      INSERT INTO notifications(
        family_id, type, title, body, deep_link, reference_id, metadata
      ) VALUES (
        p_family_id, 'stage_transition_imminent',
        v_child.name || ' is close to a milestone',
        'One good session away from ' || v_next_stage_label || '.',
        '/adventure', p_child_id,
        jsonb_build_object(
          'trait', v_trait,
          'threshold_label', v_next_stage_label,
          'current_xp', v_trait_xp,
          'threshold_xp', v_next_threshold
        )
      );
    END IF;
  END LOOP;

  -- Hero-progression-triggered birthday nudge (Session 9 addition).
  -- Only fires when an actual stage transition occurred this credit-call.
  IF jsonb_array_length(v_transitions) > 0 THEN
    v_dob := v_child.date_of_birth;
    IF v_dob IS NOT NULL THEN
      -- Same day-of-year in the current calendar year. Feb 29 babies in a
      -- non-leap year drift by one day, which is acceptable for funnel
      -- nudge timing.
      v_next_birthday := DATE_TRUNC('year', v_today)::DATE
        + (EXTRACT(DOY FROM v_dob)::INTEGER - 1);
      IF v_next_birthday < v_today THEN
        v_next_birthday := (v_next_birthday + INTERVAL '1 year')::DATE;
      END IF;
      v_days_until := (v_next_birthday - v_today);

      IF v_days_until BETWEEN 14 AND 90 THEN
        SELECT COALESCE(hero_progression_trigger_sent, false)
          INTO v_already_sent
          FROM birthday_journey_state WHERE child_id = p_child_id;
        IF v_already_sent IS NULL THEN v_already_sent := false; END IF;

        IF NOT v_already_sent
           AND NOT EXISTS (
             SELECT 1 FROM birthday_reservations
              WHERE child_id = p_child_id
                AND status IN ('interested','admin_contacted','confirmed')
           )
        THEN
          INSERT INTO notifications(
            family_id, type, title, body, deep_link, reference_id, metadata
          ) VALUES (
            p_family_id, 'birthday_hero_progression_trigger',
            v_child.name || ' just hit a new milestone!',
            'Their birthday is in ' || v_days_until ||
              ' days. Want to celebrate at Diaries?',
            '/birthday', p_child_id,
            jsonb_build_object('days_until', v_days_until)
          );

          INSERT INTO birthday_journey_state(
            child_id, birthday_year, hero_progression_trigger_sent
          ) VALUES (
            p_child_id, EXTRACT(YEAR FROM v_next_birthday)::INTEGER, true
          )
          ON CONFLICT (child_id) DO UPDATE
            SET hero_progression_trigger_sent = true,
                updated_at = now();
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_total_xp', v_new_total,
    'new_level', v_new_level,
    'new_overall_stage', v_new_overall_stage,
    'new_stages', v_new_stages,
    'transitions', v_transitions
  );
END $$;

-- ---------------------------------------------------------------------------
-- 10. Realtime publication adds
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'birthday_reservations',
    'birthday_party_photos',
    'birthday_journey_state'
  ];
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
