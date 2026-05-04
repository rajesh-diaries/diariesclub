-- ===========================================================================
--  Migration 0015 — Staff app, tablet auth, walk-in cash POS (Session 10)
--
--  Locked decisions for v1:
--    * Staff app shares the customer Flutter codebase via flavor (no separate
--      project root). The DB-side surface here is independent of that choice.
--    * Tablet identity = one Supabase auth user per physical device,
--      registered in tablet_devices. Staff identity = per-action 4-digit PIN
--      bcrypt-checked via verify_staff_pin.
--    * Roles: cashier / kitchen_staff / manager / super_admin. CLEAN
--      cutover from old enum (staff/venue_manager/hq_admin) — verified
--      `SELECT COUNT(*) FROM staff = 0` at write time.
--    * First admin bootstrapped here (rajesh @ planovativediaries@gmail.com,
--      role super_admin, PIN 0000, force_pin_change=true). The Flutter app
--      enforces PIN rotation on first login (TODO marker in dart code).
--    * Walk-in cash POS is staff-only. Walk-in customers don't get an app
--      account; one synthetic "walk-in family" is seeded per venue (Kondapur
--      only at v1) and all walk-in sessions/orders point at it.
--    * GST policy:
--        - App + walk-in PLAY: 18% inclusive (existing compute_pricing).
--        - Walk-in FOOD: 5% exclusive (new compute_pricing_exclusive).
--    * Payment method enum extended on sessions/orders to allow
--      'cash_walkin' as a 4th value (alongside wallet/cash/razorpay).
--    * QR scan validation done via qr_scan_validate RPC (decodes the
--      base64-JSON payload session_qr_screen emits today). Session 13 will
--      replace the payload format with a signed JWT; the validation RPC
--      stays in place and switches to verifying the signature.
--    * One-time-use scan: sessions.staff_scanned_at column (added here).
--      Second scan of the same QR raises 'qr_already_scanned'.
--    * Refund cap for staff: ₹500 (50000 paise). refund_issue_by_staff
--      wrapper enforces it; existing customer-side refund_issue is
--      untouched.
--
--  Changes summary:
--    1) Pre-flight assertion: staff is empty (clean cutover).
--    2) staff: add email (UNIQUE), force_pin_change; replace role CHECK.
--    3) tablet_devices: NEW table.
--    4) families: add is_walk_in.
--    5) Walk-in family seed for Kondapur (auth.users + families).
--    6) sessions.payment_method + orders.payment_method: allow 'cash_walkin'.
--    7) sessions.staff_scanned_at NEW column (idempotent scan enforcement).
--    8) venue_config.walkin_food_gst_percent NEW column (default 5).
--    9) compute_pricing_exclusive helper.
--   10) verify_staff_pin RPC.
--   11) staff_lookup_family RPC.
--   12) session_force_close RPC.
--   13) shift_close RPC.
--   14) qr_scan_validate RPC.
--   15) refund_issue_by_staff wrapper (enforces ₹500 cap).
--   16) walkin_checkout RPC.
--   17) Realtime publication adds: orders, order_items, staff,
--       tablet_devices, shift_logs.
--   18) Bootstrap row in staff (super_admin, PIN 0000, force_pin_change).
--
-- ---------------------------------------------------------------------------
--  BOOTSTRAP CEREMONY — manual steps after this migration runs:
--
--    1. Create the Kondapur tablet auth user via Supabase Studio:
--         Auth → Users → Add user → Create new user
--         Email:     tablet-kondapur-001@diariesclub.local
--         Password:  <generate strong 24-char random; save in 1Password>
--         Auto-confirm: YES (email already trusted)
--       Copy the resulting user's UUID.
--
--    2. Register that auth user as the Kondapur tablet:
--         INSERT INTO tablet_devices (venue_id, device_label, auth_user_id)
--         VALUES (
--           '00000000-0000-0000-0000-000000000001',
--           'Kondapur Front Desk',
--           '<paste-uuid-from-step-1>'
--         );
--
--    3. Open the Diaries Staff app on the tablet emulator/device:
--         - Sign in with: tablet-kondapur-001@diariesclub.local + the password
--           from step 1. Tablet identity persists from here.
--         - Tap any PIN-gated action. PIN sheet opens.
--         - Enter 0000. App detects force_pin_change=true on the staff row
--           and pushes the PIN-change screen. Pick a real 4-digit PIN.
--           From this point the founder's super_admin PIN is set.
--
--    4. From admin web (Session 11 — out of scope here), add additional
--       staff rows. Each gets their own random PIN + force_pin_change=true.
--
--  TODO(pre-launch): the Flutter staff app must enforce force_pin_change
--  before allowing any non-PIN-change action. Search dart code for
--  `TODO(pre-launch)` markers.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. Pre-flight: staff must be empty for clean role-enum cutover
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_staff_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_staff_count FROM staff;
  IF v_staff_count > 0 THEN
    RAISE EXCEPTION
      'staff table not empty (% rows) — role enum cutover requires manual reconciliation. Aborting.',
      v_staff_count;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
--  2. staff: add email + force_pin_change; replace role CHECK
-- ---------------------------------------------------------------------------
ALTER TABLE staff
  ADD COLUMN IF NOT EXISTS email            TEXT,
  ADD COLUMN IF NOT EXISTS force_pin_change BOOLEAN NOT NULL DEFAULT false;

-- Email is the human staff member's identity (used in audit trails and the
-- admin web). Unique only when set — a partial unique index keeps NULLs free.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_staff_email_lower
  ON staff (lower(email)) WHERE email IS NOT NULL;

ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE staff ALTER COLUMN role DROP DEFAULT;

ALTER TABLE staff
  ADD CONSTRAINT staff_role_check
  CHECK (role IN ('cashier','kitchen_staff','manager','super_admin'));

ALTER TABLE staff ALTER COLUMN role SET DEFAULT 'cashier';

COMMENT ON COLUMN staff.email IS
  'Staff member identity for audit attribution. Optional but recommended.';
COMMENT ON COLUMN staff.force_pin_change IS
  'When true the Flutter staff app must require a PIN change before any other action.';

-- ---------------------------------------------------------------------------
--  3. tablet_devices: registers a physical tablet to a venue
--
--  Each tablet is one Supabase auth user (email/password). All staff
--  actions originate from a tablet auth.uid(); resolving venue_id at
--  RPC time goes through this table.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tablet_devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id      UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  device_label  TEXT NOT NULL,
  auth_user_id  UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  last_used_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tablet_devices_venue_active
  ON tablet_devices(venue_id) WHERE is_active = true;

ALTER TABLE tablet_devices ENABLE ROW LEVEL SECURITY;
-- No grants for direct access — all reads/writes go through RPCs.

-- ---------------------------------------------------------------------------
--  4. families.is_walk_in: synthetic walk-in identities
-- ---------------------------------------------------------------------------
ALTER TABLE families
  ADD COLUMN IF NOT EXISTS is_walk_in BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_families_walkin
  ON families(is_walk_in) WHERE is_walk_in = true;

-- ---------------------------------------------------------------------------
--  5. Walk-in family seed for Kondapur
--
--  families.id has an FK to auth.users so we have to materialise an auth
--  user. Synthetic system user, email never receives mail, password is a
--  random unguessable string (ON CONFLICT skips re-runs).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_walkin_user_id UUID := '00000000-1000-0000-0000-000000000001';
  v_kondapur_id    UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  )
  VALUES (
    v_walkin_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'walkin-kondapur-001@diariesclub.local',
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    '{"provider":"system","providers":["system"]}'::jsonb,
    '{"is_walk_in": true, "venue": "kondapur"}'::jsonb,
    now(), now()
  )
  ON CONFLICT (id) DO NOTHING;

  -- Phone is a placeholder satisfying the validate_phone_e164 trigger
  -- (+91 followed by [6-9]\d{9}). The walk-in family is also flagged
  -- is_anonymised=true so customer-facing logic that hides anonymised
  -- rows naturally hides this synthetic identity too.
  INSERT INTO families (id, phone, name, is_walk_in, is_anonymised)
  VALUES (
    v_walkin_user_id,
    '+916000000000',
    'Walk-in (Kondapur)',
    true,
    true
  )
  ON CONFLICT (id) DO NOTHING;
END $$;

-- ---------------------------------------------------------------------------
--  6. payment_method enum: allow 'cash_walkin' on sessions + orders
-- ---------------------------------------------------------------------------
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_payment_method_check;
ALTER TABLE sessions ADD CONSTRAINT sessions_payment_method_check
  CHECK (payment_method IN ('wallet','cash','razorpay','cash_walkin'));

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;
ALTER TABLE orders ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method IN ('wallet','cash','razorpay','cash_walkin'));

-- ---------------------------------------------------------------------------
--  7. sessions.staff_scanned_at: idempotent QR scan marker
-- ---------------------------------------------------------------------------
ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS staff_scanned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS staff_scanned_by UUID REFERENCES staff(id);

COMMENT ON COLUMN sessions.staff_scanned_at IS
  'Timestamp the staff app validated the QR. NULL until first scan; second scan via qr_scan_validate raises qr_already_scanned.';

-- ---------------------------------------------------------------------------
--  8. venue_config.walkin_food_gst_percent
-- ---------------------------------------------------------------------------
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS walkin_food_gst_percent NUMERIC(5,2) NOT NULL DEFAULT 5.00;

COMMENT ON COLUMN venue_config.walkin_food_gst_percent IS
  'GST applied to walk-in FOOD transactions (5% exclusive). App + walk-in PLAY use the regular gst_percent (18% inclusive).';

-- ---------------------------------------------------------------------------
--  9. compute_pricing_exclusive helper
--
--  Mirror of compute_pricing but for tax-exclusive flows: caller passes
--  the pre-tax subtotal, we add GST on top. CEIL on GST so any rounding
--  drift becomes extra collected tax (accountant-conservative, matches
--  the rounding direction in compute_pricing).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_pricing_exclusive(
  p_subtotal_paise INTEGER,
  p_gst_percent    NUMERIC
) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_gst INTEGER;
BEGIN
  IF p_subtotal_paise IS NULL OR p_subtotal_paise < 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_gst_percent IS NULL OR p_gst_percent < 0 THEN
    RAISE EXCEPTION 'invalid_gst_percent';
  END IF;

  v_gst := CEIL(p_subtotal_paise::NUMERIC * p_gst_percent / 100)::INTEGER;
  RETURN jsonb_build_object(
    'subtotal_paise', p_subtotal_paise,
    'gst_paise',      v_gst,
    'total_paise',    p_subtotal_paise + v_gst
  );
END $$;

REVOKE EXECUTE ON FUNCTION compute_pricing_exclusive(INTEGER, NUMERIC) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION compute_pricing_exclusive(INTEGER, NUMERIC)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10. verify_staff_pin RPC
--
--  Tablet calls this with a 4-digit PIN typed by the staff member. We
--  resolve the venue from tablet_devices (auth.uid()), then bcrypt-check
--  the PIN against active staff at that venue.
--
--  N is small (a venue's staff count) so the seq scan + crypt() per row
--  is fine. If a venue ever has 50+ active staff we'd revisit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION verify_staff_pin(p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_staff  staff%ROWTYPE;
BEGIN
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'invalid_pin_format';
  END IF;

  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'tablet_not_authorised';
  END IF;

  SELECT * INTO v_staff FROM staff
    WHERE venue_id = v_tablet.venue_id
      AND is_active = true
      AND pin_hash = crypt(p_pin, pin_hash)
    LIMIT 1;

  IF NOT FOUND THEN
    -- Soft "no match" — caller shows "invalid PIN" without distinguishing
    -- bad-tablet vs bad-pin.
    RETURN jsonb_build_object('staff_id', NULL);
  END IF;

  UPDATE staff SET last_pin_used_at = now() WHERE id = v_staff.id;
  UPDATE tablet_devices SET last_used_at = now() WHERE id = v_tablet.id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (v_staff.id, 'staff', 'pin.verified', 'staff', v_staff.id, v_tablet.venue_id);

  RETURN jsonb_build_object(
    'staff_id',         v_staff.id,
    'staff_name',       v_staff.name,
    'role',             v_staff.role,
    'force_pin_change', v_staff.force_pin_change,
    'venue_id',         v_tablet.venue_id
  );
END $$;

REVOKE EXECUTE ON FUNCTION verify_staff_pin(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION verify_staff_pin(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. staff_lookup_family RPC
--
--  Takes a phone (E.164), returns the family + children + wallet for use
--  in the manual-session flow. Tablet-gated.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_lookup_family(p_phone TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet   tablet_devices%ROWTYPE;
  v_family   families%ROWTYPE;
  v_wallet   wallets%ROWTYPE;
  v_children JSONB;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  SELECT * INTO v_family FROM families
    WHERE phone = p_phone
      AND deleted_at IS NULL
      AND is_walk_in = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'family_not_found'; END IF;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = v_family.id;

  SELECT COALESCE(jsonb_agg(c ORDER BY c->>'created_at' ASC), '[]'::jsonb)
    INTO v_children
    FROM (
      SELECT to_jsonb(ch) - 'fcm_token' AS c, ch.created_at
        FROM children ch
       WHERE ch.family_id = v_family.id
         AND ch.deleted_at IS NULL
    ) t;

  RETURN jsonb_build_object(
    'family',   to_jsonb(v_family) - 'fcm_token',
    'children', COALESCE(v_children, '[]'::jsonb),
    'wallet',   COALESCE(to_jsonb(v_wallet), '{}'::jsonb)
  );
END $$;

REVOKE EXECUTE ON FUNCTION staff_lookup_family(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION staff_lookup_family(TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. session_force_close RPC (per-session, staff-pin gated)
--
--  Distinct from force_close_grace_sessions() which is the cron-driven
--  batch sweeper. This one closes ONE session immediately when a staff
--  member intervenes (e.g., parent walked out without checking out).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION session_force_close(
  p_session_id   UUID,
  p_staff_pin_id UUID,
  p_reason       TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet  tablet_devices%ROWTYPE;
  v_session sessions%ROWTYPE;
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

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT * INTO v_session FROM sessions
    WHERE id = p_session_id AND venue_id = v_tablet.venue_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  UPDATE sessions SET
    status       = 'completed',
    completed_at = now(),
    notes        = COALESCE(notes || ' | ', '') ||
                   'force-closed by staff: ' || trim(p_reason)
  WHERE id = p_session_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'session.force_close', 'session',
    p_session_id, v_tablet.venue_id,
    jsonb_build_object('reason', trim(p_reason))
  );

  RETURN jsonb_build_object('success', true, 'session_id', p_session_id);
END $$;

REVOKE EXECUTE ON FUNCTION session_force_close(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION session_force_close(UUID, UUID, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 13. shift_close RPC
--
--  Computes expected cash from the day's cash-paid sessions/orders, takes
--  the staff's counted figure, writes shift_logs row. Discrepancy is a
--  GENERATED column on shift_logs so we don't compute it here.
--
--  Big-discrepancy threshold: ₹100 (10000 paise). Above that we drop an
--  audit_log row tagged shift.discrepancy_alert; admin web will surface
--  it in Session 11.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shift_close(
  p_counted_cash_paise INTEGER,
  p_notes              TEXT DEFAULT NULL,
  p_staff_pin_id       UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet   tablet_devices%ROWTYPE;
  v_shift    shift_logs%ROWTYPE;
  v_expected INTEGER;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF p_counted_cash_paise IS NULL OR p_counted_cash_paise < 0 THEN
    RAISE EXCEPTION 'invalid_counted_cash';
  END IF;
  IF p_staff_pin_id IS NULL THEN RAISE EXCEPTION 'staff_pin_required'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = v_tablet.venue_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  -- Find or open a shift for this venue.
  SELECT * INTO v_shift FROM shift_logs
    WHERE venue_id = v_tablet.venue_id AND status = 'open'
    FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO shift_logs(venue_id, shift_start, status)
    VALUES (
      v_tablet.venue_id,
      DATE_TRUNC('day', now() AT TIME ZONE 'Asia/Kolkata')
        AT TIME ZONE 'Asia/Kolkata',
      'open'
    )
    RETURNING * INTO v_shift;
  END IF;

  -- Expected cash = sum of cash + cash_walkin payments since shift_start.
  -- Sessions and orders both contribute (walkin can produce one of each).
  SELECT
    COALESCE((
      SELECT SUM(amount_paise) FROM sessions
       WHERE venue_id = v_tablet.venue_id
         AND payment_method IN ('cash','cash_walkin')
         AND created_at >= v_shift.shift_start
    ), 0)
  + COALESCE((
      SELECT SUM(total_paise) FROM orders
       WHERE venue_id = v_tablet.venue_id
         AND payment_method IN ('cash','cash_walkin')
         AND created_at >= v_shift.shift_start
    ), 0)
    INTO v_expected;

  UPDATE shift_logs SET
    shift_end           = now(),
    expected_cash_paise = v_expected,
    counted_cash_paise  = p_counted_cash_paise,
    notes               = p_notes,
    closed_by_pin       = p_staff_pin_id,
    status              = 'closed',
    summary             = jsonb_build_object(
      'expected_paise',    v_expected,
      'counted_paise',     p_counted_cash_paise,
      'discrepancy_paise', p_counted_cash_paise - v_expected
    )
  WHERE id = v_shift.id RETURNING * INTO v_shift;

  IF ABS(v_shift.discrepancy_paise) > 10000 THEN
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
    ) VALUES (
      p_staff_pin_id, 'staff', 'shift.discrepancy_alert', 'shift_log',
      v_shift.id, v_tablet.venue_id,
      jsonb_build_object('discrepancy_paise', v_shift.discrepancy_paise)
    );
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'shift.close', 'shift_log',
    v_shift.id, v_tablet.venue_id,
    jsonb_build_object(
      'expected_paise',    v_expected,
      'counted_paise',     p_counted_cash_paise,
      'discrepancy_paise', v_shift.discrepancy_paise
    )
  );

  RETURN jsonb_build_object(
    'success',             true,
    'shift_id',            v_shift.id,
    'expected_cash_paise', v_expected,
    'counted_cash_paise',  p_counted_cash_paise,
    'discrepancy_paise',   v_shift.discrepancy_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION shift_close(INTEGER, TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION shift_close(INTEGER, TEXT, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 14. qr_scan_validate RPC
--
--  Customer's session_qr_screen emits a base64url(JSON{v,session_id,
--  family_id,expires_at}) blob. v1 trust is the unguessable session_id +
--  one-time-use enforcement. Session 13 will replace the payload with a
--  signed JWT — this RPC stays, validation switches to JWT signature check.
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
  v_child_name TEXT;
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

  -- Decode base64url(JSON{...}). Guard against malformed payloads.
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
  IF v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;
  IF v_session.staff_scanned_at IS NOT NULL THEN
    RAISE EXCEPTION 'qr_already_scanned';
  END IF;

  UPDATE sessions SET
    staff_scanned_at = now(),
    staff_scanned_by = p_staff_pin_id
  WHERE id = v_session.id;

  SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'session.qr_scan', 'session',
    v_session.id, v_tablet.venue_id,
    jsonb_build_object('duration_minutes', v_session.duration_minutes)
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
    'status',                      v_session.status
  );
END $$;

REVOKE EXECUTE ON FUNCTION qr_scan_validate(TEXT, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION qr_scan_validate(TEXT, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 15. refund_issue_by_staff (staff-cap wrapper)
--
--  Enforces the ₹500 staff cap, then calls existing refund_issue. Existing
--  RPC signature: refund_issue(family, ref, ref_type, amount, destination,
--  reason, staff_pin_id, venue_id, idempotency_key). Above-cap refunds
--  raise refund_exceeds_staff_cap; the staff app routes those to a
--  pending-admin-approval flow (Session 11 will materialise that).
--
--  The wrapper expects the caller to know the order (or session) ID and
--  pulls family + venue from there to keep the staff-side parameters
--  minimal.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refund_issue_by_staff(
  p_reference_id    UUID,
  p_reference_type  TEXT,                 -- 'order' | 'session'
  p_amount_paise    INTEGER,
  p_destination     TEXT,                 -- 'wallet' | 'razorpay'
  p_reason          TEXT,
  p_staff_pin_id    UUID,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet    tablet_devices%ROWTYPE;
  v_family_id UUID;
  v_venue_id  UUID;
  v_result    JSONB;
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

  IF p_reference_type NOT IN ('order','session') THEN
    RAISE EXCEPTION 'invalid_reference_type';
  END IF;
  IF p_amount_paise IS NULL OR p_amount_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount_paise > 50000 THEN
    RAISE EXCEPTION 'refund_exceeds_staff_cap';
  END IF;
  IF p_destination NOT IN ('wallet','razorpay') THEN
    RAISE EXCEPTION 'invalid_destination';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  -- Resolve family + venue from the reference. Staff can only refund txns
  -- at their own venue.
  IF p_reference_type = 'order' THEN
    SELECT family_id, venue_id INTO v_family_id, v_venue_id
      FROM orders WHERE id = p_reference_id;
  ELSE
    SELECT family_id, venue_id INTO v_family_id, v_venue_id
      FROM sessions WHERE id = p_reference_id;
  END IF;

  IF v_family_id IS NULL THEN RAISE EXCEPTION 'reference_not_found'; END IF;
  IF v_venue_id <> v_tablet.venue_id THEN
    RAISE EXCEPTION 'reference_other_venue';
  END IF;

  v_result := refund_issue(
    p_family_id       := v_family_id,
    p_reference_id    := p_reference_id,
    p_reference_type  := p_reference_type,
    p_amount_paise    := p_amount_paise,
    p_destination     := p_destination,
    p_reason          := trim(p_reason),
    p_staff_pin_id    := p_staff_pin_id,
    p_venue_id        := v_venue_id,
    p_idempotency_key := p_idempotency_key
  );

  RETURN v_result;
END $$;

REVOKE EXECUTE ON FUNCTION refund_issue_by_staff(UUID, TEXT, INTEGER, TEXT, TEXT, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION refund_issue_by_staff(UUID, TEXT, INTEGER, TEXT, TEXT, UUID, TEXT)
  TO authenticated;

-- Re-grant healthy_bite_distribute to authenticated so the staff app can
-- call it directly. Was service_role only in 0003 because it was meant
-- to be invoked from the (then-future) staff app.
GRANT EXECUTE ON FUNCTION healthy_bite_distribute(UUID, UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 15b. staff_pin_change RPC
--
--  The staff app's PIN-change flow calls this with the verified-current
--  PIN + a new PIN. We re-verify the current PIN server-side (defence in
--  depth — the RPC trusts neither the client nor the route guard), then
--  bcrypt the new value and clear force_pin_change. Audit on success.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION staff_pin_change(
  p_staff_id    UUID,
  p_current_pin TEXT,
  p_new_pin     TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_staff  staff%ROWTYPE;
BEGIN
  IF p_new_pin IS NULL OR p_new_pin !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'invalid_new_pin';
  END IF;
  IF p_new_pin = '0000' THEN
    RAISE EXCEPTION 'pin_too_weak';
  END IF;

  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  SELECT * INTO v_staff FROM staff
    WHERE id = p_staff_id
      AND venue_id = v_tablet.venue_id
      AND is_active = true
      AND pin_hash = crypt(p_current_pin, pin_hash);
  IF NOT FOUND THEN RAISE EXCEPTION 'current_pin_incorrect'; END IF;

  UPDATE staff SET
    pin_hash         = crypt(p_new_pin, gen_salt('bf')),
    force_pin_change = false,
    last_pin_used_at = now()
  WHERE id = p_staff_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (p_staff_id, 'staff', 'pin.changed', 'staff', p_staff_id, v_tablet.venue_id);

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION staff_pin_change(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION staff_pin_change(UUID, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 16. walkin_checkout RPC
--
--  Modes:
--    'play'  → 1× session (1hr or 2hr), 18% inclusive GST.
--    'food'  → 1× order, 5% exclusive GST on subtotal.
--    'mixed' → 1× session + 1× order, billed independently per the rules
--              above (single staff action, two DB rows).
--
--  Inputs:
--    p_play_minutes    — required for play/mixed (must be 60 or 120).
--    p_food_items      — required for food/mixed; JSONB array of
--                        { menu_item_id: UUID, quantity: INTEGER }.
--    p_idempotency_key — optional but recommended; we store it on the
--                        first non-null row created.
--
--  Walk-in family is the seeded synthetic family for this venue. We look
--  it up by (venue_id, is_walk_in=true).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION walkin_checkout(
  p_venue_id        UUID,
  p_staff_pin_id    UUID,
  p_mode            TEXT,
  p_play_minutes    INTEGER,
  p_food_items      JSONB,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tablet       tablet_devices%ROWTYPE;
  v_config       venue_config%ROWTYPE;
  v_walkin_id    UUID;

  v_play_total   INTEGER := 0;
  v_play_split   JSONB;
  v_session_id   UUID;

  v_food_subtotal INTEGER := 0;
  v_food_split   JSONB;
  v_order_id     UUID;

  v_item         JSONB;
  v_menu_item    menu_items%ROWTYPE;
  v_brand        TEXT;
  v_menu_venue   UUID;
  v_qty          INTEGER;

  v_now          TIMESTAMPTZ := now();
  v_idem_session TEXT;
  v_idem_order   TEXT;
BEGIN
  -- Tablet + venue check
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;
  IF v_tablet.venue_id <> p_venue_id THEN
    RAISE EXCEPTION 'venue_mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id
       AND venue_id = p_venue_id
       AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  IF p_mode NOT IN ('play','food','mixed') THEN
    RAISE EXCEPTION 'invalid_mode';
  END IF;

  -- Idempotency: each leg uses a derived key so the two rows don't collide
  -- on sessions.idempotency_key vs orders.idempotency_key (independent
  -- UNIQUE indexes).
  IF p_idempotency_key IS NOT NULL THEN
    v_idem_session := p_idempotency_key || ':session';
    v_idem_order   := p_idempotency_key || ':order';

    IF EXISTS (SELECT 1 FROM sessions WHERE idempotency_key = v_idem_session)
       OR EXISTS (SELECT 1 FROM orders WHERE idempotency_key = v_idem_order)
    THEN
      SELECT id INTO v_session_id FROM sessions WHERE idempotency_key = v_idem_session;
      SELECT id INTO v_order_id   FROM orders   WHERE idempotency_key = v_idem_order;
      RETURN jsonb_build_object(
        'success',     true,
        'idempotent',  true,
        'session_id',  v_session_id,
        'order_id',    v_order_id
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  SELECT id INTO v_walkin_id FROM families
    WHERE is_walk_in = true LIMIT 1;
    -- Single seeded walk-in family at v1 (multi-venue: filter by venue when
    -- families gets a venue_id column).
  IF v_walkin_id IS NULL THEN RAISE EXCEPTION 'walkin_family_missing'; END IF;

  -- ── PLAY leg ────────────────────────────────────────────────────────
  IF p_mode IN ('play','mixed') THEN
    IF p_play_minutes IS NULL OR p_play_minutes NOT IN (60, 120) THEN
      RAISE EXCEPTION 'invalid_play_minutes';
    END IF;

    v_play_total := CASE p_play_minutes
      WHEN 60  THEN v_config.session_1hr_price_paise
      WHEN 120 THEN v_config.session_2hr_price_paise
    END;

    v_play_split := compute_pricing(v_play_total, v_config.gst_percent);

    INSERT INTO sessions(
      venue_id, family_id, child_id, staff_pin_id,
      duration_minutes, amount_paise, payment_method, status,
      started_at, expires_at,
      subtotal_paise, gst_paise,
      is_guest, idempotency_key, notes
    ) VALUES (
      p_venue_id, v_walkin_id, NULL, p_staff_pin_id,
      p_play_minutes, v_play_total, 'cash_walkin', 'active',
      v_now, v_now + (p_play_minutes || ' minutes')::INTERVAL,
      (v_play_split->>'subtotal_paise')::INTEGER,
      (v_play_split->>'gst_paise')::INTEGER,
      true,
      v_idem_session,
      'walk-in PLAY (cash)'
    ) RETURNING id INTO v_session_id;
  END IF;

  -- ── FOOD leg ────────────────────────────────────────────────────────
  IF p_mode IN ('food','mixed') THEN
    IF p_food_items IS NULL OR jsonb_array_length(p_food_items) = 0 THEN
      RAISE EXCEPTION 'invalid_food_items';
    END IF;

    -- First pass: validate all menu items exist + active + at this venue,
    -- and accumulate the pre-tax subtotal. Brand + venue live on menus,
    -- so we join to confirm the item belongs to this tablet's venue.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_food_items) LOOP
      v_qty := COALESCE((v_item->>'quantity')::INTEGER, 1);
      IF v_qty <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

      -- PL/pgSQL forbids record + scalar in the same INTO list, so we
      -- split the lookup: row first, then brand/venue from the parent menu.
      SELECT * INTO v_menu_item FROM menu_items
       WHERE id = (v_item->>'menu_item_id')::UUID
         AND is_available = true;
      IF NOT FOUND THEN RAISE EXCEPTION 'menu_item_unavailable'; END IF;

      SELECT brand, venue_id INTO v_brand, v_menu_venue
        FROM menus
       WHERE id = v_menu_item.menu_id AND is_active = true;
      IF NOT FOUND THEN RAISE EXCEPTION 'menu_item_unavailable'; END IF;
      IF v_menu_venue <> p_venue_id THEN
        RAISE EXCEPTION 'menu_item_other_venue';
      END IF;

      v_food_subtotal := v_food_subtotal + (v_menu_item.price_paise * v_qty);
    END LOOP;

    v_food_split := compute_pricing_exclusive(
      v_food_subtotal, v_config.walkin_food_gst_percent
    );

    INSERT INTO orders(
      venue_id, family_id, staff_pin_id,
      fulfillment_mode, payment_method,
      subtotal_paise, gst_paise, combo_discount_paise, total_paise,
      coins_earned, status,
      idempotency_key
    ) VALUES (
      p_venue_id, v_walkin_id, p_staff_pin_id,
      'dine_in', 'cash_walkin',
      v_food_subtotal,
      (v_food_split->>'gst_paise')::INTEGER,
      0,
      (v_food_split->>'total_paise')::INTEGER,
      0, 'pending',
      v_idem_order
    ) RETURNING id INTO v_order_id;

    -- Second pass: now that we have the order_id, write order_items.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_food_items) LOOP
      v_qty := COALESCE((v_item->>'quantity')::INTEGER, 1);

      SELECT * INTO v_menu_item FROM menu_items
       WHERE id = (v_item->>'menu_item_id')::UUID;
      SELECT brand INTO v_brand FROM menus WHERE id = v_menu_item.menu_id;

      INSERT INTO order_items(
        order_id, menu_item_id, brand, name_snapshot,
        quantity, unit_price_paise
      ) VALUES (
        v_order_id, v_menu_item.id, v_brand, v_menu_item.name,
        v_qty, v_menu_item.price_paise
      );
    END LOOP;
  END IF;

  -- Audit
  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'walkin.checkout',
    CASE p_mode WHEN 'food' THEN 'order' ELSE 'session' END,
    COALESCE(v_session_id, v_order_id),
    p_venue_id,
    jsonb_build_object(
      'mode',           p_mode,
      'play_minutes',   p_play_minutes,
      'play_total',     v_play_total,
      'food_subtotal',  v_food_subtotal,
      'food_total',     COALESCE((v_food_split->>'total_paise')::INTEGER, 0),
      'session_id',     v_session_id,
      'order_id',       v_order_id
    )
  );

  RETURN jsonb_build_object(
    'success',           true,
    'session_id',        v_session_id,
    'order_id',          v_order_id,
    'play_total_paise',  v_play_total,
    'food_total_paise',  COALESCE((v_food_split->>'total_paise')::INTEGER, 0),
    'food_gst_paise',    COALESCE((v_food_split->>'gst_paise')::INTEGER, 0),
    'grand_total_paise', v_play_total + COALESCE((v_food_split->>'total_paise')::INTEGER, 0)
  );
END $$;

REVOKE EXECUTE ON FUNCTION walkin_checkout(UUID, UUID, TEXT, INTEGER, JSONB, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION walkin_checkout(UUID, UUID, TEXT, INTEGER, JSONB, TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 17. Realtime publication adds
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table  TEXT;
  v_tables TEXT[] := ARRAY[
    'orders',
    'order_items',
    'staff',
    'tablet_devices',
    'shift_logs'
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

-- ---------------------------------------------------------------------------
-- 18. Bootstrap super_admin row
--
--  Founder identity. PIN 0000 is a placeholder; force_pin_change=true
--  means the staff app routes the first PIN entry to the rotation flow.
-- ---------------------------------------------------------------------------
INSERT INTO staff (
  venue_id, name, phone, email, pin_hash, role, force_pin_change, is_active
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Rajesh',
  '+919999999999',
  'planovativediaries@gmail.com',
  crypt('0000', gen_salt('bf')),
  'super_admin',
  true,
  true
);

COMMIT;
