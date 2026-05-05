-- ===========================================================================
--  Migration 0023 — Fix-batch RPCs
--
--  Five RPCs grouped here because they share schema dependencies from
--  0020/0021/0022 and several call sites need them at once:
--
--    1. family_set_birthday_interest  — FEATURE-002
--    2. birthday_reservation_cancel   — BUG-013
--    3. session_create (v2)           — BUG-004 (replaces 0003 version)
--    4. session_cancel_pending        — BUG-004
--    5. qr_scan_validate (v2)         — BUG-004 (replaces 0015 version)
--
--  All SECURITY DEFINER, idempotent where applicable, audit-logged.
--  Concurrency model for BUG-004: both qr_scan_validate and
--  session_cancel_pending acquire FOR UPDATE on the session row and
--  re-check status='pending' inside the lock — whichever wins, the
--  other sees status != 'pending' and returns a benign already_done.
--
--  Reversibility:
--    -- Restore previous signatures from 0003 and 0015. session_create body
--    -- in 0003:287; qr_scan_validate body in 0015:568. Drop the new RPCs:
--    DROP FUNCTION IF EXISTS family_set_birthday_interest(UUID, TEXT);
--    DROP FUNCTION IF EXISTS birthday_reservation_cancel(UUID);
--    DROP FUNCTION IF EXISTS session_cancel_pending(UUID);
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. family_set_birthday_interest
--
-- Customer toggles per-child interest state from the birthday discovery
-- page. Idempotent: setting the same state twice is a no-op (returns the
-- current row). Always audit-logs the change for refund disputes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION family_set_birthday_interest(
  p_child_id       UUID,
  p_interest_state TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child   children%ROWTYPE;
  v_family  families%ROWTYPE;
  v_old     TEXT;
BEGIN
  IF p_interest_state NOT IN ('interested','not_this_year') THEN
    RAISE EXCEPTION 'invalid_interest_state';
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND OR v_child.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'child_not_found';
  END IF;

  PERFORM assert_caller_authority(v_child.family_id, NULL);

  v_old := v_child.birthday_interest_state;

  IF v_old = p_interest_state THEN
    -- Idempotent no-op; still return the current row so the client gets
    -- a consistent response shape.
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'child_id', v_child.id,
      'birthday_interest_state', v_child.birthday_interest_state
    );
  END IF;

  UPDATE children
     SET birthday_interest_state      = p_interest_state,
         birthday_interest_updated_at = now()
   WHERE id = p_child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    v_child.family_id, 'customer',
    'birthday.interest_state.update', 'child', p_child_id,
    jsonb_build_object('old', v_old, 'new', p_interest_state)
  );

  RETURN jsonb_build_object(
    'success', true,
    'child_id', v_child.id,
    'birthday_interest_state', p_interest_state
  );
END $$;

REVOKE EXECUTE ON FUNCTION family_set_birthday_interest(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION family_set_birthday_interest(UUID, TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. birthday_reservation_cancel
--
-- Customer self-cancels a pre-payment reservation from the status screen
-- (BUG-013). Allowed states: 'interested', 'admin_contacted'. Anything
-- past 'confirmed' goes through admin refund flow — this RPC refuses.
-- Idempotent: cancelling an already-cancelled-by-customer row is a no-op.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION birthday_reservation_cancel(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations
   WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;

  PERFORM assert_caller_authority(v_res.family_id, NULL);

  IF v_res.status = 'cancelled_by_customer' THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'reservation_id', v_res.id, 'status', v_res.status
    );
  END IF;

  IF v_res.status NOT IN ('interested','admin_contacted') THEN
    RAISE EXCEPTION 'cannot_cancel_post_confirmation';
  END IF;

  UPDATE birthday_reservations
     SET status           = 'cancelled_by_customer',
         cancelled_at     = now(),
         cancelled_reason = 'customer_initiated'
   WHERE id = p_reservation_id;

  -- Pause the journey state so D-N reminders stop firing.
  UPDATE birthday_journey_state
     SET arc_type = 'paused', updated_at = now()
   WHERE child_id = v_res.child_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_res.family_id, 'customer',
    'birthday.reserve.cancel_by_customer', 'birthday_reservation',
    v_res.id, v_res.venue_id,
    jsonb_build_object('previous_status', v_res.status)
  );

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id,
    'status', 'cancelled_by_customer'
  );
END $$;

REVOKE EXECUTE ON FUNCTION birthday_reservation_cancel(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION birthday_reservation_cancel(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. session_create (v2) — hold-then-charge for customer wallet flow
--
-- Behavioral change vs. 0003 version:
--   - When payment_method='wallet' AND p_staff_pin_id IS NULL (customer
--     started this from the app), the function:
--       * Verifies (balance_paise - held_paise) >= amount
--       * Increments held_paise by amount (balance untouched)
--       * Inserts session with status='pending'
--       * No wallet_transactions row yet — no debit has happened
--   - When payment_method='wallet' AND p_staff_pin_id IS NOT NULL (staff
--     created at counter on customer's behalf), or payment_method='cash':
--       * Existing immediate-active behavior preserved exactly.
--
-- Signature unchanged from 0003 — clients don't need to update.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION session_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,
  p_staff_pin_id UUID DEFAULT NULL,
  p_is_guest BOOLEAN DEFAULT false,
  p_guest_phone TEXT DEFAULT NULL,
  p_pre_booking_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session    sessions%ROWTYPE;
  v_existing   sessions%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_amount     INTEGER;
  v_use_hold   BOOLEAN;
  v_status     TEXT;
  v_started_at TIMESTAMPTZ;
  v_expires_at TIMESTAMPTZ;
  v_grace_at   TIMESTAMPTZ;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id',     v_existing.id,
        'status',         v_existing.status,
        'expires_at',     v_existing.expires_at,
        'amount_paise',   v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  v_amount := CASE WHEN p_duration_minutes = 60
                   THEN v_config.session_1hr_price_paise
                   ELSE v_config.session_2hr_price_paise END;

  -- The hold path applies only to customer-initiated wallet sessions.
  v_use_hold := (p_payment_method = 'wallet' AND p_staff_pin_id IS NULL);

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;

    IF v_use_hold THEN
      -- Spendable = balance - held. Reject if not enough room.
      IF (v_wallet.balance_paise - v_wallet.held_paise) < v_amount THEN
        RAISE EXCEPTION 'insufficient_balance';
      END IF;
      UPDATE wallets SET
        held_paise = held_paise + v_amount,
        updated_at = now()
      WHERE family_id = p_family_id;
    ELSE
      -- Staff-counter wallet flow: keep existing immediate-debit behavior.
      IF v_wallet.balance_paise < v_amount THEN RAISE EXCEPTION 'insufficient_balance'; END IF;
      UPDATE wallets SET
        balance_paise = balance_paise - v_amount, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;
      INSERT INTO wallet_transactions(
        family_id, type, amount_paise, balance_after_paise,
        payment_method, reference_type, idempotency_key
      ) VALUES (
        p_family_id, 'session_debit', -v_amount, v_wallet.balance_paise,
        'wallet', 'session', p_idempotency_key
      );
    END IF;
  END IF;

  IF v_use_hold THEN
    -- Pending session: clock starts on QR scan, not creation. expires_at
    -- and grace_force_close_at are placeholders set far in the future
    -- and overwritten by qr_scan_validate when status flips to active.
    -- We set them to (now + timeout + buffer) so they always satisfy the
    -- NOT NULL constraint without leaking through the autocancel window.
    v_status     := 'pending';
    v_started_at := now();
    v_expires_at := now() + (v_config.session_pre_scan_timeout_minutes || ' minutes')::INTERVAL
                          + (p_duration_minutes || ' minutes')::INTERVAL;
    v_grace_at   := v_expires_at + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL;
  ELSE
    v_status     := 'active';
    v_started_at := now();
    v_expires_at := now() + (p_duration_minutes || ' minutes')::INTERVAL;
    v_grace_at   := now() + ((p_duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL;
  END IF;

  INSERT INTO sessions(
    venue_id, family_id, child_id, staff_pin_id,
    duration_minutes, amount_paise, payment_method, status,
    started_at, expires_at, grace_force_close_at,
    is_guest, guest_phone, pre_booking_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method, v_status,
    v_started_at, v_expires_at, v_grace_at,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key
  ) RETURNING * INTO v_session;

  -- Backfill the reference_id on the immediate-debit transaction (only
  -- written in the non-hold branch above).
  IF p_payment_method = 'wallet' AND NOT v_use_hold THEN
    UPDATE wallet_transactions SET reference_id = v_session.id
      WHERE family_id = p_family_id
        AND type = 'session_debit'
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  IF p_pre_booking_id IS NOT NULL THEN
    UPDATE session_pre_bookings SET
      status = 'redeemed', redeemed_session_id = v_session.id
    WHERE id = p_pre_booking_id AND status = 'reserved';
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.create', 'session', v_session.id, p_venue_id,
    jsonb_build_object(
      'child_id', p_child_id,
      'duration_minutes', p_duration_minutes,
      'amount_paise', v_amount,
      'payment_method', p_payment_method,
      'status', v_status,
      'used_hold', v_use_hold
    )
  );

  RETURN jsonb_build_object(
    'success',              true,
    'session_id',           v_session.id,
    'status',               v_status,
    'expires_at',           v_session.expires_at,
    'grace_force_close_at', v_session.grace_force_close_at,
    'amount_paise',         v_amount
  );
END $$;

-- Permission grant unchanged from 0003.
GRANT EXECUTE ON FUNCTION session_create(UUID,UUID,UUID,INTEGER,TEXT,UUID,BOOLEAN,TEXT,UUID,TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. session_cancel_pending
--
-- Releases a wallet hold on a pending session and flips status to
-- 'cancelled_pre_scan'. Two callers:
--   * Customer manually taps "Cancel" on the QR screen.
--   * autocancel cron sweeps sessions older than venue_config
--     .session_pre_scan_timeout_minutes.
-- Concurrency: SELECT FOR UPDATE on the session row, re-check
-- status='pending' inside the lock. If qr_scan_validate already won,
-- we see status != 'pending' and return idempotent no-op.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION session_cancel_pending(
  p_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_actor   TEXT;
  v_actor_id UUID;
BEGIN
  SELECT * INTO v_session FROM sessions
   WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.status != 'pending' THEN
    -- Already moved on (scan won, or already cancelled). Idempotent.
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', v_session.id, 'status', v_session.status
    );
  END IF;

  -- Caller authority: customer family OR service_role (cron). Staff
  -- role can also cancel via tablet — assert_caller_authority allows
  -- both customer-self and service-role (NULL family check on service
  -- role pathway).
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, NULL);
    v_actor    := 'customer';
    v_actor_id := v_session.family_id;
  ELSE
    v_actor    := 'system';
    v_actor_id := NULL;
  END IF;

  -- Release the hold (only meaningful for wallet-paid pending sessions).
  IF v_session.payment_method = 'wallet' THEN
    UPDATE wallets
       SET held_paise = GREATEST(held_paise - v_session.amount_paise, 0),
           updated_at = now()
     WHERE family_id = v_session.family_id;
  END IF;

  UPDATE sessions
     SET status = 'cancelled_pre_scan',
         completed_at = now()
   WHERE id = p_session_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_actor_id, v_actor,
    'session.cancel_pending', 'session', v_session.id, v_session.venue_id,
    jsonb_build_object(
      'amount_released_paise', v_session.amount_paise,
      'payment_method', v_session.payment_method
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'status', 'cancelled_pre_scan',
    'amount_released_paise', v_session.amount_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION session_cancel_pending(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION session_cancel_pending(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. qr_scan_validate (v2) — pending → active + hold → debit
--
-- Behavioral change vs. 0015 version:
--   - Now accepts session.status='pending' (in addition to 'active','grace').
--   - When status was 'pending':
--       * Decrement wallet.held_paise by amount, decrement balance_paise
--         by amount, insert wallet_transactions session_debit row.
--       * Update session: status='active', started_at=now(), recompute
--         expires_at and grace_force_close_at from the actual scan time.
--   - When status was already 'active'/'grace' (legacy / staff-counter
--     flow): existing behavior unchanged — just records staff_scanned_at.
--
-- Signature unchanged from 0015.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION qr_scan_validate(
  p_qr_payload   TEXT,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet     tablet_devices%ROWTYPE;
  v_decoded    JSONB;
  v_session_id UUID;
  v_session    sessions%ROWTYPE;
  v_wallet     wallets%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_child_name TEXT;
  v_was_pending BOOLEAN;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = v_tablet.venue_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  -- Decode base64url(JSON{...}) — same as 0015.
  BEGIN
    v_decoded := convert_from(
      decode(
        translate(p_qr_payload, '-_', '+/') ||
          repeat('=', (4 - length(p_qr_payload) % 4) % 4),
        'base64'
      ), 'UTF8'
    )::JSONB;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'qr_payload_invalid';
  END;

  v_session_id := (v_decoded->>'session_id')::UUID;
  IF v_session_id IS NULL THEN RAISE EXCEPTION 'qr_payload_invalid'; END IF;

  SELECT * INTO v_session FROM sessions
    WHERE id = v_session_id AND venue_id = v_tablet.venue_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.status NOT IN ('pending','active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;
  IF v_session.staff_scanned_at IS NOT NULL THEN
    RAISE EXCEPTION 'qr_already_scanned';
  END IF;

  v_was_pending := (v_session.status = 'pending');

  IF v_was_pending THEN
    -- Convert hold to debit. Only wallet-paid pending sessions reach here
    -- (cash sessions never go pending), but guard anyway.
    SELECT * INTO v_config FROM venue_config WHERE venue_id = v_tablet.venue_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

    IF v_session.payment_method = 'wallet' THEN
      SELECT * INTO v_wallet FROM wallets
        WHERE family_id = v_session.family_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
      IF v_wallet.held_paise < v_session.amount_paise THEN
        RAISE EXCEPTION 'hold_lost';
      END IF;
      IF v_wallet.balance_paise < v_session.amount_paise THEN
        RAISE EXCEPTION 'insufficient_balance';
      END IF;

      UPDATE wallets SET
        held_paise    = held_paise    - v_session.amount_paise,
        balance_paise = balance_paise - v_session.amount_paise,
        updated_at    = now()
      WHERE family_id = v_session.family_id RETURNING * INTO v_wallet;

      INSERT INTO wallet_transactions(
        family_id, type, amount_paise, balance_after_paise,
        payment_method, reference_type, reference_id, idempotency_key
      ) VALUES (
        v_session.family_id, 'session_debit', -v_session.amount_paise, v_wallet.balance_paise,
        'wallet', 'session', v_session.id,
        COALESCE(v_session.idempotency_key, v_session.id::TEXT) || ':scan'
      );
    END IF;

    -- Now flip pending → active. Recompute expiry from actual scan time.
    UPDATE sessions SET
      status               = 'active',
      started_at           = now(),
      expires_at           = now() + (v_session.duration_minutes || ' minutes')::INTERVAL,
      grace_force_close_at = now() + ((v_session.duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,
      staff_scanned_at     = now(),
      staff_scanned_by     = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  ELSE
    -- Legacy path: session was already 'active' or 'grace' (staff-counter
    -- flow). Just stamp the scan and audit.
    UPDATE sessions SET
      staff_scanned_at = now(),
      staff_scanned_by = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  END IF;

  SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'session.qr_scan', 'session',
    v_session.id, v_tablet.venue_id,
    jsonb_build_object(
      'duration_minutes', v_session.duration_minutes,
      'was_pending', v_was_pending,
      'converted_hold_to_debit', v_was_pending AND v_session.payment_method = 'wallet'
    )
  );

  RETURN jsonb_build_object(
    'success',                     true,
    'session_id',                  v_session.id,
    'child_name',                  v_child_name,
    'duration_minutes',            v_session.duration_minutes,
    'started_at',                  v_session.started_at,
    'expires_at',                  v_session.expires_at,
    'healthy_bite_earned',         v_session.healthy_bite_earned,
    'healthy_bite_distributed',    v_session.healthy_bite_distributed,
    'status',                      v_session.status,
    'was_pending',                 v_was_pending
  );
END $$;

GRANT EXECUTE ON FUNCTION qr_scan_validate(TEXT, UUID) TO authenticated;

COMMIT;
