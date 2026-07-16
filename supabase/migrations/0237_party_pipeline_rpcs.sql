-- ===========================================================================
--  Migration 0237 — Party/Events pipeline: RPCs + crons + report (Phase 0, 2/2)
--
--  Companion to 0236 (schema). All staff RPCs use the house tablet lane
--  (tablet_devices.auth_user_id = auth.uid() → venue; p_staff_pin_id
--  verified against active staff at that venue — same as 0015/0232/0234).
--  Crons are grant-gated to service_role (same as force_close_grace_sessions).
--  Every mutation writes audit_log.
--
--  Surface:
--    party_lead_create        — ≤10s phone-call capture; dedupes repeat calls
--    party_lead_advance       — follow-up state machine ('won' unreachable here)
--    party_lead_convert       — lead → confirmed booking (idempotent); creates/
--                               links family via the walk-in path (phone = key);
--                               instantiates the 11 checklist items
--    party_payment_record     — advance/balance/refund into party_payments;
--                               idempotency-keyed double-charge guard
--    party_slot_check         — conflicts + venue blocks + weekend flag;
--                               INFORMATIONAL ONLY, never blocks
--    party_checklist_toggle   — day-of checklist with done_by/done_at audit
--    party_stale_sweep        — cron: open + untouched 7 days → stale
--    party_repeat_lead_generate — cron: completed parties 315–380 days ago →
--                               one repeat lead each, ever (source repeat_customer)
--    admin_party_pipeline_report — owner report (by_source / funnel /
--                               bookings_ahead_4w / lost_reasons / money)
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  0. Shared staff-lane helper: resolve tablet venue + verify actor
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _party_staff_gate(p_staff_pin_id UUID)
RETURNS UUID  -- venue_id
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF p_staff_pin_id IS NULL THEN RAISE EXCEPTION 'staff_pin_required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = v_tablet.venue_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  RETURN v_tablet.venue_id;
END $$;

REVOKE EXECUTE ON FUNCTION _party_staff_gate(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION _party_staff_gate(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
--  1. party_lead_create — the ≤10 second capture
--
--  Same open (phone, requested-date) → append a note to the existing lead
--  and return it (deduped: true). No duplicate rows for repeat calls.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_lead_create(
  p_source               TEXT,
  p_parent_name          TEXT,
  p_phone                TEXT,
  p_staff_pin_id         UUID,
  p_event_type           TEXT DEFAULT 'birthday',
  p_child_name           TEXT DEFAULT NULL,
  p_child_dob            DATE DEFAULT NULL,
  p_guest_estimate       INTEGER DEFAULT NULL,
  p_event_date_requested DATE DEFAULT NULL,
  p_slot_pref            TEXT DEFAULT NULL,
  p_package_id           UUID DEFAULT NULL,
  p_note                 TEXT DEFAULT NULL,
  p_next_follow_up_at    TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue_id UUID;
  v_phone    TEXT;
  v_existing party_leads%ROWTYPE;
  v_lead     party_leads%ROWTYPE;
BEGIN
  v_venue_id := _party_staff_gate(p_staff_pin_id);

  v_phone := regexp_replace(COALESCE(p_phone, ''), '\s', '', 'g');
  IF v_phone !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'invalid_phone' USING DETAIL = 'expect E.164, e.g. +9198...';
  END IF;
  IF p_parent_name IS NULL OR length(trim(p_parent_name)) = 0 THEN
    RAISE EXCEPTION 'parent_name_required';
  END IF;
  IF p_source IS NULL OR p_source NOT IN (
    'phone','walkin','whatsapp','instagram','referral','app_enquiry',
    'repeat_customer','other'
  ) THEN
    RAISE EXCEPTION 'invalid_source';
  END IF;

  -- Dedupe: an OPEN lead for the same phone + same requested date is the
  -- same conversation. Lock it, log the repeat call, return it.
  SELECT * INTO v_existing FROM party_leads
    WHERE phone = v_phone
      AND COALESCE(event_date_requested, DATE '1900-01-01')
          = COALESCE(p_event_date_requested, DATE '1900-01-01')
      AND status IN ('new','contacted','visited','quoted')
    FOR UPDATE;

  IF FOUND THEN
    INSERT INTO party_lead_notes(lead_id, author_staff_id, channel, body)
    VALUES (
      v_existing.id, p_staff_pin_id, 'call',
      'Repeat call' || COALESCE(': ' || NULLIF(trim(p_note), ''), '')
    );
    UPDATE party_leads SET
      last_contacted_at = now(),
      follow_up_count   = follow_up_count + 1
    WHERE id = v_existing.id;

    RETURN jsonb_build_object(
      'success', true, 'lead_id', v_existing.id, 'deduped', true
    );
  END IF;

  BEGIN
    INSERT INTO party_leads(
      venue_id, source, event_type, parent_name, phone,
      child_name, child_dob, guest_estimate,
      event_date_requested, slot_pref, package_id,
      assigned_staff_id, created_by_staff_id,
      last_contacted_at, next_follow_up_at
    ) VALUES (
      v_venue_id, p_source, COALESCE(p_event_type, 'birthday'),
      trim(p_parent_name), v_phone,
      NULLIF(trim(COALESCE(p_child_name, '')), ''), p_child_dob,
      p_guest_estimate,
      p_event_date_requested, p_slot_pref, p_package_id,
      p_staff_pin_id, p_staff_pin_id,
      now(), p_next_follow_up_at
    ) RETURNING * INTO v_lead;
  EXCEPTION WHEN unique_violation THEN
    -- Raced another create for the same (phone, date): converge on theirs.
    SELECT * INTO v_existing FROM party_leads
      WHERE phone = v_phone
        AND COALESCE(event_date_requested, DATE '1900-01-01')
            = COALESCE(p_event_date_requested, DATE '1900-01-01')
        AND status IN ('new','contacted','visited','quoted');
    IF NOT FOUND THEN RAISE; END IF;
    RETURN jsonb_build_object(
      'success', true, 'lead_id', v_existing.id, 'deduped', true
    );
  END;

  IF p_note IS NOT NULL AND length(trim(p_note)) > 0 THEN
    INSERT INTO party_lead_notes(lead_id, author_staff_id, channel, body)
    VALUES (v_lead.id, p_staff_pin_id, 'call', trim(p_note));
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff', 'party.lead_create', 'party_lead',
    v_lead.id, v_venue_id,
    jsonb_build_object('source', p_source, 'phone', v_phone,
                       'event_type', v_lead.event_type)
  );

  RETURN jsonb_build_object(
    'success', true, 'lead_id', v_lead.id, 'deduped', false
  );
END $$;

REVOKE EXECUTE ON FUNCTION party_lead_create(TEXT,TEXT,TEXT,UUID,TEXT,TEXT,DATE,INTEGER,DATE,TEXT,UUID,TEXT,TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_lead_create(TEXT,TEXT,TEXT,UUID,TEXT,TEXT,DATE,INTEGER,DATE,TEXT,UUID,TEXT,TIMESTAMPTZ) TO authenticated;

-- ---------------------------------------------------------------------------
--  2. party_lead_advance — follow-up state machine
--
--  Legal:  new → contacted|visited|quoted|lost
--          contacted → visited|quoted|lost
--          visited → quoted|lost
--          quoted → lost
--          stale → contacted|visited|quoted|lost   (reactivation)
--  'won' is UNREACHABLE here — only party_lead_convert sets it.
--  Every advance appends a system note (the audit trail of the pipeline).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_lead_advance(
  p_lead_id           UUID,
  p_to_status         TEXT,
  p_staff_pin_id      UUID,
  p_next_follow_up_at TIMESTAMPTZ DEFAULT NULL,
  p_lost_reason       TEXT DEFAULT NULL,
  p_lost_reason_note  TEXT DEFAULT NULL,
  p_note              TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue_id UUID;
  v_lead     party_leads%ROWTYPE;
  v_legal    BOOLEAN;
BEGIN
  v_venue_id := _party_staff_gate(p_staff_pin_id);

  SELECT * INTO v_lead FROM party_leads
    WHERE id = p_lead_id AND venue_id = v_venue_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'lead_not_found'; END IF;

  IF p_to_status = 'won' THEN
    RAISE EXCEPTION 'won_only_via_convert';
  END IF;

  v_legal := CASE v_lead.status
    WHEN 'new'       THEN p_to_status IN ('contacted','visited','quoted','lost')
    WHEN 'contacted' THEN p_to_status IN ('visited','quoted','lost')
    WHEN 'visited'   THEN p_to_status IN ('quoted','lost')
    WHEN 'quoted'    THEN p_to_status IN ('lost')
    WHEN 'stale'     THEN p_to_status IN ('contacted','visited','quoted','lost')
    ELSE false  -- won/lost are terminal for advance
  END;
  IF NOT v_legal THEN
    RAISE EXCEPTION 'invalid_transition'
      USING DETAIL = format('%s → %s', v_lead.status, p_to_status);
  END IF;

  IF p_to_status = 'lost' AND (p_lost_reason IS NULL OR p_lost_reason NOT IN (
    'price','date_unavailable','went_elsewhere','no_response','not_serious','other'
  )) THEN
    RAISE EXCEPTION 'lost_reason_required';
  END IF;

  UPDATE party_leads SET
    status            = p_to_status,
    next_follow_up_at = p_next_follow_up_at,
    last_contacted_at = now(),
    follow_up_count   = follow_up_count + 1,
    lost_reason       = CASE WHEN p_to_status = 'lost' THEN p_lost_reason ELSE lost_reason END,
    lost_reason_note  = CASE WHEN p_to_status = 'lost'
                             THEN NULLIF(trim(COALESCE(p_lost_reason_note, '')), '')
                             ELSE lost_reason_note END
  WHERE id = p_lead_id;

  INSERT INTO party_lead_notes(lead_id, author_staff_id, channel, body)
  VALUES (
    p_lead_id, p_staff_pin_id, 'system',
    format('status: %s → %s', v_lead.status, p_to_status)
      || CASE WHEN p_to_status = 'lost' THEN ' (' || p_lost_reason || ')' ELSE '' END
      || COALESCE(' — ' || NULLIF(trim(p_note), ''), '')
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value, new_value)
  VALUES (
    p_staff_pin_id, 'staff', 'party.lead_advance', 'party_lead',
    p_lead_id, v_venue_id,
    jsonb_build_object('status', v_lead.status),
    jsonb_build_object('status', p_to_status, 'lost_reason', p_lost_reason)
  );

  RETURN jsonb_build_object('success', true, 'lead_id', p_lead_id, 'status', p_to_status);
END $$;

REVOKE EXECUTE ON FUNCTION party_lead_advance(UUID,TEXT,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_lead_advance(UUID,TEXT,UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  3. party_lead_convert — lead → confirmed booking (idempotent)
--
--  * Already-won lead returns its reservation_id (replay: true).
--  * Family: p_family_id if given, else matched by phone (the walk-in
--    pattern), else materialised: synthetic auth.users row + families row
--    (0015 §5 precedent). The wallet trigger auto-creates their wallet.
--  * Child: p_child_id if given, else created (name/dob from params or lead;
--    children.date_of_birth is NOT NULL so DOB is required at convert).
--  * Reservation lands status='confirmed', triggered_by = lead source.
--  * The 11 checklist items are instantiated from the venue's template.
--  * Slot conflicts NEVER block here — party_slot_check is the advisory
--    step; staff sees warnings in the UI before confirming.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_lead_convert(
  p_lead_id         UUID,
  p_staff_pin_id    UUID,
  p_package_id      UUID,
  p_slot_date       DATE,
  p_slot            TEXT,
  p_price_paise     INTEGER,
  p_num_kids        INTEGER,
  p_num_adults      INTEGER DEFAULT 0,
  p_slot_start_time TIME DEFAULT NULL,
  p_slot_end_time   TIME DEFAULT NULL,
  p_family_id       UUID DEFAULT NULL,
  p_child_id        UUID DEFAULT NULL,
  p_child_name      TEXT DEFAULT NULL,
  p_child_dob       DATE DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_venue_id   UUID;
  v_lead       party_leads%ROWTYPE;
  v_pkg        birthday_packages%ROWTYPE;
  v_family_id  UUID;
  v_child_id   UUID;
  v_child_name TEXT;
  v_child_dob  DATE;
  v_res_id     UUID;
  v_items      INTEGER;
BEGIN
  v_venue_id := _party_staff_gate(p_staff_pin_id);

  SELECT * INTO v_lead FROM party_leads
    WHERE id = p_lead_id AND venue_id = v_venue_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'lead_not_found'; END IF;

  -- Idempotent replay: converting a won lead returns the existing booking.
  IF v_lead.status = 'won' THEN
    RETURN jsonb_build_object(
      'success', true, 'replay', true,
      'reservation_id', v_lead.reservation_id,
      'family_id', v_lead.family_id, 'child_id', v_lead.child_id
    );
  END IF;

  IF p_slot IS NULL OR p_slot NOT IN ('morning','evening') THEN
    RAISE EXCEPTION 'invalid_slot';
  END IF;
  IF p_slot_date IS NULL THEN RAISE EXCEPTION 'invalid_slot_date'; END IF;
  IF p_price_paise IS NULL OR p_price_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_price';
  END IF;
  IF p_num_kids IS NULL OR p_num_kids < 0
     OR p_num_adults IS NULL OR p_num_adults < 0 THEN
    RAISE EXCEPTION 'invalid_guest_counts';
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages
    WHERE id = p_package_id AND venue_id = v_venue_id AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  -- ── Family: link by id, else by phone, else materialise ────────────────
  IF p_family_id IS NOT NULL THEN
    SELECT id INTO v_family_id FROM families
      WHERE id = p_family_id AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'family_not_found'; END IF;
  ELSE
    SELECT id INTO v_family_id FROM families
      WHERE phone = v_lead.phone AND deleted_at IS NULL
        AND COALESCE(is_walk_in, false) = false;
  END IF;

  IF v_family_id IS NULL THEN
    -- Walk-in precedent (0015 §5): families.id must equal an auth.users id,
    -- so materialise a synthetic auth user. If this parent later signs up
    -- in the app with the same phone, OTP flow finds this family row.
    v_family_id := gen_random_uuid();
    INSERT INTO auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) VALUES (
      v_family_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'party-' || v_family_id || '@diariesclub.local',
      crypt(gen_random_uuid()::text, gen_salt('bf')),
      now(),
      '{"provider":"system","providers":["system"]}'::jsonb,
      jsonb_build_object('is_party_lead', true, 'lead_id', p_lead_id),
      now(), now()
    );
    INSERT INTO families (id, phone, name)
    VALUES (v_family_id, v_lead.phone, v_lead.parent_name);
  END IF;

  -- ── Child: link by id, else create ──────────────────────────────────────
  IF p_child_id IS NOT NULL THEN
    SELECT id INTO v_child_id FROM children
      WHERE id = p_child_id AND family_id = v_family_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;
  ELSE
    v_child_name := COALESCE(NULLIF(trim(COALESCE(p_child_name, '')), ''),
                             v_lead.child_name);
    v_child_dob  := COALESCE(p_child_dob, v_lead.child_dob);
    IF v_child_name IS NULL THEN RAISE EXCEPTION 'child_name_required'; END IF;
    IF v_child_dob  IS NULL THEN RAISE EXCEPTION 'child_dob_required'; END IF;

    INSERT INTO children (family_id, name, date_of_birth)
    VALUES (v_family_id, v_child_name, v_child_dob)
    RETURNING id INTO v_child_id;
  END IF;

  -- ── Booking ─────────────────────────────────────────────────────────────
  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    slot_date, slot, slot_start_time, slot_end_time,
    num_kids, num_adults,
    package_price_paise, deposit_paid_paise, balance_paise, total_paid_paise,
    status, admin_confirmed_at, triggered_by, idempotency_key
  ) VALUES (
    v_venue_id, v_family_id, v_child_id, p_package_id,
    p_slot_date, p_slot, p_slot_start_time, p_slot_end_time,
    p_num_kids, p_num_adults,
    p_price_paise, 0, p_price_paise, 0,
    'confirmed', now(), v_lead.source, p_idempotency_key
  ) RETURNING id INTO v_res_id;

  -- ── Checklist instantiation ─────────────────────────────────────────────
  INSERT INTO party_checklist_items (reservation_id, item_key, label, sort_order)
  SELECT v_res_id,
         item->>'key',
         item->>'label',
         COALESCE((item->>'sort_order')::INTEGER, 0)
    FROM party_checklist_templates t,
         jsonb_array_elements(t.items) AS item
   WHERE t.venue_id = v_venue_id AND t.is_active = true AND t.name = 'default';
  GET DIAGNOSTICS v_items = ROW_COUNT;
  IF v_items = 0 THEN RAISE EXCEPTION 'checklist_template_missing'; END IF;

  -- ── Close the loop on the lead ──────────────────────────────────────────
  UPDATE party_leads SET
    status            = 'won',
    reservation_id    = v_res_id,
    family_id         = v_family_id,
    child_id          = v_child_id,
    last_contacted_at = now(),
    follow_up_count   = follow_up_count + 1
  WHERE id = p_lead_id;

  INSERT INTO party_lead_notes(lead_id, author_staff_id, channel, body)
  VALUES (
    p_lead_id, p_staff_pin_id, 'system',
    format('converted to booking %s — %s on %s (%s), ₹%s',
           v_res_id, v_pkg.name, p_slot_date, p_slot,
           (p_price_paise / 100)::TEXT)
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff', 'party.lead_convert', 'birthday_reservation',
    v_res_id, v_venue_id,
    jsonb_build_object(
      'lead_id', p_lead_id, 'package_id', p_package_id,
      'slot_date', p_slot_date, 'slot', p_slot,
      'price_paise', p_price_paise,
      'family_id', v_family_id, 'child_id', v_child_id
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'replay', false,
    'reservation_id', v_res_id,
    'family_id', v_family_id, 'child_id', v_child_id,
    'checklist_count', v_items
  );
END $$;

REVOKE EXECUTE ON FUNCTION party_lead_convert(UUID,UUID,UUID,DATE,TEXT,INTEGER,INTEGER,INTEGER,TIME,TIME,UUID,UUID,TEXT,DATE,TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_lead_convert(UUID,UUID,UUID,DATE,TEXT,INTEGER,INTEGER,INTEGER,TIME,TIME,UUID,UUID,TEXT,DATE,TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  4. party_payment_record — advance/balance/refund with double-charge guard
--
--  Idempotency-keyed: replaying the same key returns the ORIGINAL row and
--  records nothing. Refunds are direction=-1 rows capped at net collected.
--  The 0236 trigger recomputes the reservation's derived money columns.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_payment_record(
  p_reservation_id      UUID,
  p_kind                TEXT,
  p_amount_paise        INTEGER,
  p_method              TEXT,
  p_staff_pin_id        UUID,
  p_idempotency_key     TEXT,
  p_payment_context     TEXT DEFAULT 'party',
  p_razorpay_payment_id TEXT DEFAULT NULL,
  p_note                TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue_id  UUID;
  v_res       birthday_reservations%ROWTYPE;
  v_existing  party_payments%ROWTYPE;
  v_direction SMALLINT;
  v_net       INTEGER;
  v_invoice   TEXT;
  v_pay_id    UUID;
BEGIN
  v_venue_id := _party_staff_gate(p_staff_pin_id);

  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) = 0 THEN
    RAISE EXCEPTION 'idempotency_key_required';
  END IF;

  -- Replay guard BEFORE any validation drift: same key → original result.
  SELECT * INTO v_existing FROM party_payments
    WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    SELECT * INTO v_res FROM birthday_reservations WHERE id = v_existing.reservation_id;
    RETURN jsonb_build_object(
      'success', true, 'replay', true,
      'payment_id', v_existing.id,
      'invoice_no', v_existing.invoice_no,
      'deposit_paid_paise', v_res.deposit_paid_paise,
      'balance_paise', v_res.balance_paise
    );
  END IF;

  IF p_kind IS NULL OR p_kind NOT IN ('advance','balance','refund') THEN
    RAISE EXCEPTION 'invalid_kind';
  END IF;
  IF p_amount_paise IS NULL OR p_amount_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_method IS NULL OR p_method NOT IN ('cash','card','upi','razorpay','bank_transfer') THEN
    RAISE EXCEPTION 'invalid_method';
  END IF;
  IF p_payment_context IS NULL OR p_payment_context NOT IN ('party','banquet','commission') THEN
    RAISE EXCEPTION 'invalid_payment_context';
  END IF;

  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id AND venue_id = v_venue_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_res.status NOT IN ('confirmed','completed') THEN
    RAISE EXCEPTION 'invalid_reservation_state';
  END IF;

  v_direction := CASE WHEN p_kind = 'refund' THEN -1 ELSE 1 END;

  IF p_kind = 'refund' THEN
    SELECT COALESCE(SUM(amount_paise * direction), 0) INTO v_net
      FROM party_payments WHERE reservation_id = p_reservation_id;
    IF p_amount_paise > v_net THEN
      RAISE EXCEPTION 'refund_exceeds_collected'
        USING DETAIL = format('net collected %s paise', v_net);
    END IF;
  END IF;

  v_invoice := CASE WHEN v_direction = 1 THEN _next_invoice_number() ELSE NULL END;

  BEGIN
    INSERT INTO party_payments(
      reservation_id, kind, direction, amount_paise, method,
      payment_context, razorpay_payment_id, invoice_no,
      collected_by_staff_id, idempotency_key, note
    ) VALUES (
      p_reservation_id, p_kind, v_direction, p_amount_paise, p_method,
      p_payment_context, p_razorpay_payment_id, v_invoice,
      p_staff_pin_id, trim(p_idempotency_key), NULLIF(trim(COALESCE(p_note, '')), '')
    ) RETURNING id INTO v_pay_id;
  EXCEPTION WHEN unique_violation THEN
    -- Raced a concurrent replay of the same key: return the winner.
    SELECT * INTO v_existing FROM party_payments
      WHERE idempotency_key = p_idempotency_key;
    IF NOT FOUND THEN RAISE; END IF;
    SELECT * INTO v_res FROM birthday_reservations WHERE id = v_existing.reservation_id;
    RETURN jsonb_build_object(
      'success', true, 'replay', true,
      'payment_id', v_existing.id,
      'invoice_no', v_existing.invoice_no,
      'deposit_paid_paise', v_res.deposit_paid_paise,
      'balance_paise', v_res.balance_paise
    );
  END;

  -- Trigger has recomputed the derived columns; re-read for the response.
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff', 'party.payment_record', 'party_payment',
    v_pay_id, v_venue_id,
    jsonb_build_object(
      'reservation_id', p_reservation_id, 'kind', p_kind,
      'amount_paise', p_amount_paise, 'direction', v_direction,
      'method', p_method, 'invoice_no', v_invoice
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'replay', false,
    'payment_id', v_pay_id,
    'invoice_no', v_invoice,
    'deposit_paid_paise', v_res.deposit_paid_paise,
    'balance_paise', v_res.balance_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION party_payment_record(UUID,TEXT,INTEGER,TEXT,UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_payment_record(UUID,TEXT,INTEGER,TEXT,UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  5. party_slot_check — INFORMATIONAL conflict/block/weekend probe
--
--  Never blocks anything. Staff (tablet) or admin callable.
--  * conflicts: confirmed bookings at the venue on that date whose slot
--    matches (or is unset on legacy rows).
--  * blocks: birthday_availability rows flagged is_blocked on that date.
--  * is_weekend: Sat/Sun flag for pricing/staffing awareness.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_slot_check(
  p_venue_id  UUID,
  p_slot_date DATE,
  p_slot      TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_is_staff  BOOLEAN;
  v_conflicts JSONB;
  v_blocks    JSONB;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM tablet_devices
     WHERE auth_user_id = auth.uid() AND is_active = true
       AND venue_id = p_venue_id
  ) INTO v_is_staff;
  IF NOT v_is_staff AND NOT is_admin() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  IF p_slot_date IS NULL THEN RAISE EXCEPTION 'invalid_slot_date'; END IF;
  IF p_slot IS NOT NULL AND p_slot NOT IN ('morning','evening') THEN
    RAISE EXCEPTION 'invalid_slot';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'reservation_id', r.id,
           'slot',            r.slot,
           'slot_start_time', r.slot_start_time,
           'slot_end_time',   r.slot_end_time,
           'num_kids',        r.num_kids,
           'package_name',    p.name,
           'hall_name',       to_jsonb(p) ->> 'hall_name'
         ) ORDER BY r.slot_start_time NULLS LAST), '[]'::jsonb)
    INTO v_conflicts
    FROM birthday_reservations r
    JOIN birthday_packages p ON p.id = r.package_id
   WHERE r.venue_id = p_venue_id
     AND r.slot_date = p_slot_date
     AND r.status = 'confirmed'
     AND (p_slot IS NULL OR r.slot IS NULL OR r.slot = p_slot);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'slot_start_time', a.slot_start_time,
           'slot_end_time',   a.slot_end_time,
           'block_reason',    a.block_reason
         ) ORDER BY a.slot_start_time), '[]'::jsonb)
    INTO v_blocks
    FROM birthday_availability a
   WHERE a.venue_id = p_venue_id
     AND a.slot_date = p_slot_date
     AND a.is_blocked = true;

  RETURN jsonb_build_object(
    'success',    true,
    'conflicts',  v_conflicts,
    'blocks',     v_blocks,
    'is_weekend', EXTRACT(ISODOW FROM p_slot_date) IN (6, 7),
    'clear',      jsonb_array_length(v_conflicts) = 0
                  AND jsonb_array_length(v_blocks) = 0
  );
END $$;

REVOKE EXECUTE ON FUNCTION party_slot_check(UUID,DATE,TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_slot_check(UUID,DATE,TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  6. party_checklist_toggle — day-of checklist with per-item attribution
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_checklist_toggle(
  p_reservation_id UUID,
  p_item_key       TEXT,
  p_is_done        BOOLEAN,
  p_staff_pin_id   UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue_id UUID;
  v_item     party_checklist_items%ROWTYPE;
BEGIN
  v_venue_id := _party_staff_gate(p_staff_pin_id);

  IF NOT EXISTS (
    SELECT 1 FROM birthday_reservations
     WHERE id = p_reservation_id AND venue_id = v_venue_id
  ) THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  UPDATE party_checklist_items SET
    is_done          = p_is_done,
    done_at          = CASE WHEN p_is_done THEN now() ELSE NULL END,
    done_by_staff_id = CASE WHEN p_is_done THEN p_staff_pin_id ELSE NULL END
  WHERE reservation_id = p_reservation_id AND item_key = p_item_key
  RETURNING * INTO v_item;
  IF NOT FOUND THEN RAISE EXCEPTION 'checklist_item_not_found'; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff', 'party.checklist_toggle', 'party_checklist_item',
    v_item.id, v_venue_id,
    jsonb_build_object('reservation_id', p_reservation_id,
                       'item_key', p_item_key, 'is_done', p_is_done)
  );

  RETURN jsonb_build_object(
    'success', true,
    'item_key', v_item.item_key,
    'is_done',  v_item.is_done,
    'done_at',  v_item.done_at
  );
END $$;

REVOKE EXECUTE ON FUNCTION party_checklist_toggle(UUID,TEXT,BOOLEAN,UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION party_checklist_toggle(UUID,TEXT,BOOLEAN,UUID) TO authenticated;

-- ---------------------------------------------------------------------------
--  7. party_stale_sweep — cron: open + untouched 7 days → stale
--
--  Idempotent (stale leads no longer match). Returns the row count for
--  job logging. Grant-gated to service_role like force_close_grace_sessions.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_stale_sweep() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER;
BEGIN
  WITH swept AS (
    UPDATE party_leads SET status = 'stale'
     WHERE status IN ('new','contacted','visited','quoted')
       AND updated_at < now() - INTERVAL '7 days'
    RETURNING id
  ),
  noted AS (
    INSERT INTO party_lead_notes(lead_id, channel, body)
    SELECT id, 'system', 'auto-marked stale: no touch in 7 days'
      FROM swept
    RETURNING lead_id
  )
  SELECT COUNT(*) INTO v_count FROM swept;

  IF v_count > 0 THEN
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, venue_id, new_value)
    VALUES (NULL, 'system', 'party.stale_sweep', 'party_lead', NULL,
            jsonb_build_object('swept', v_count));
  END IF;

  RETURN jsonb_build_object('success', true, 'swept', v_count);
END $$;

REVOKE EXECUTE ON FUNCTION party_stale_sweep() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION party_stale_sweep() TO service_role;

-- ---------------------------------------------------------------------------
--  8. party_repeat_lead_generate — cron: the ~10.5-month repeat-birthday lead
--
--  Completed parties whose slot_date is 315–380 days ago get ONE repeat
--  lead each, ever (repeat_of_reservation_id NOT EXISTS guard), with
--  source='repeat_customer' and requested date = party date + 1 year.
--  Skips deleted/anonymised/walk-in families and anyone who already has
--  an open lead for that (phone, date). Idempotent; returns row count.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_repeat_lead_generate() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_count INTEGER;
BEGIN
  INSERT INTO party_leads(
    venue_id, source, status, event_type,
    parent_name, phone, child_name, child_dob,
    event_date_requested, repeat_of_reservation_id
  )
  SELECT r.venue_id, 'repeat_customer', 'new', 'birthday',
         f.name, f.phone, c.name, c.date_of_birth,
         (r.slot_date + INTERVAL '1 year')::DATE, r.id
    FROM birthday_reservations r
    JOIN families f ON f.id = r.family_id
    JOIN children c ON c.id = r.child_id
   WHERE r.status = 'completed'
     AND r.slot_date BETWEEN (v_today - 380) AND (v_today - 315)
     AND f.deleted_at IS NULL
     AND COALESCE(f.is_anonymised, false) = false
     AND COALESCE(f.is_walk_in, false) = false
     -- one repeat lead per completed party, EVER
     AND NOT EXISTS (
       SELECT 1 FROM party_leads pl
        WHERE pl.repeat_of_reservation_id = r.id
     )
     -- don't collide with an open lead for the same phone + date
     AND NOT EXISTS (
       SELECT 1 FROM party_leads pl2
        WHERE pl2.phone = f.phone
          AND COALESCE(pl2.event_date_requested, DATE '1900-01-01')
              = (r.slot_date + INTERVAL '1 year')::DATE
          AND pl2.status IN ('new','contacted','visited','quoted')
     );
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count > 0 THEN
    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, venue_id, new_value)
    VALUES (NULL, 'system', 'party.repeat_lead_generate', 'party_lead', NULL,
            jsonb_build_object('created', v_count));
  END IF;

  RETURN jsonb_build_object('success', true, 'created', v_count);
END $$;

REVOKE EXECUTE ON FUNCTION party_repeat_lead_generate() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION party_repeat_lead_generate() TO service_role;

-- ---------------------------------------------------------------------------
--  9. admin_party_pipeline_report — the owner report
--
--  Single jsonb:
--    by_source          — lead counts by source, created in [from, to] (IST)
--    funnel             — leads / won / lost / open / conversion_pct
--    bookings_ahead_4w  — next 4 weekly buckets of confirmed bookings:
--                         events, confirmed_value_paise, collected_paise,
--                         due_paise
--    lost_reasons       — counts by structured reason
--    money              — collected_paise (net party_payments in period),
--                         avg_ticket_paise (won leads' booking prices)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_party_pipeline_report(
  p_from DATE,
  p_to   DATE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_today       DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_by_source   JSONB;
  v_funnel      JSONB;
  v_weeks       JSONB;
  v_lost        JSONB;
  v_money       JSONB;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
    RAISE EXCEPTION 'invalid_range';
  END IF;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object('source', source, 'leads', n)
           ORDER BY n DESC), '[]'::jsonb)
    INTO v_by_source
    FROM (
      SELECT source, COUNT(*)::INTEGER AS n
        FROM party_leads
       WHERE (created_at AT TIME ZONE 'Asia/Kolkata')::DATE BETWEEN p_from AND p_to
       GROUP BY source
    ) t;

  SELECT jsonb_build_object(
           'leads', COUNT(*),
           'won',   COUNT(*) FILTER (WHERE status = 'won'),
           'lost',  COUNT(*) FILTER (WHERE status = 'lost'),
           'open',  COUNT(*) FILTER (WHERE status IN
                      ('new','contacted','visited','quoted','stale')),
           'conversion_pct',
             CASE WHEN COUNT(*) = 0 THEN 0
                  ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'won')
                             / COUNT(*), 1) END
         )
    INTO v_funnel
    FROM party_leads
   WHERE (created_at AT TIME ZONE 'Asia/Kolkata')::DATE BETWEEN p_from AND p_to;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'week_start',            w.week_start,
           'events',                COALESCE(b.events, 0),
           'confirmed_value_paise', COALESCE(b.confirmed_value, 0),
           'collected_paise',       COALESCE(b.collected, 0),
           'due_paise',             COALESCE(b.due, 0)
         ) ORDER BY w.week_start), '[]'::jsonb)
    INTO v_weeks
    FROM (
      SELECT (v_today + (i * 7))::DATE AS week_start
        FROM generate_series(0, 3) AS i
    ) w
    LEFT JOIN LATERAL (
      SELECT COUNT(*)::INTEGER               AS events,
             SUM(r.package_price_paise)::BIGINT AS confirmed_value,
             SUM(r.total_paid_paise)::BIGINT    AS collected,
             SUM(r.balance_paise)::BIGINT       AS due
        FROM birthday_reservations r
       WHERE r.status = 'confirmed'
         AND r.slot_date >= w.week_start
         AND r.slot_date < w.week_start + 7
    ) b ON true;

  SELECT COALESCE(jsonb_agg(
           jsonb_build_object('reason', lost_reason, 'count', n)
           ORDER BY n DESC), '[]'::jsonb)
    INTO v_lost
    FROM (
      SELECT lost_reason, COUNT(*)::INTEGER AS n
        FROM party_leads
       WHERE status = 'lost'
         AND (created_at AT TIME ZONE 'Asia/Kolkata')::DATE BETWEEN p_from AND p_to
       GROUP BY lost_reason
    ) t;

  SELECT jsonb_build_object(
           'collected_paise', COALESCE((
             SELECT SUM(amount_paise * direction)
               FROM party_payments
              WHERE (received_at AT TIME ZONE 'Asia/Kolkata')::DATE
                    BETWEEN p_from AND p_to
           ), 0),
           'avg_ticket_paise', COALESCE((
             SELECT ROUND(AVG(r.package_price_paise))::BIGINT
               FROM party_leads pl
               JOIN birthday_reservations r ON r.id = pl.reservation_id
              WHERE pl.status = 'won'
                AND (pl.updated_at AT TIME ZONE 'Asia/Kolkata')::DATE
                    BETWEEN p_from AND p_to
           ), 0)
         )
    INTO v_money;

  RETURN jsonb_build_object(
    'by_source',         v_by_source,
    'funnel',            v_funnel,
    'bookings_ahead_4w', v_weeks,
    'lost_reasons',      v_lost,
    'money',             v_money
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_party_pipeline_report(DATE,DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_party_pipeline_report(DATE,DATE) TO authenticated;

COMMIT;
