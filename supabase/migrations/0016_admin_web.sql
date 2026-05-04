-- ===========================================================================
--  Migration 0016 — Admin Web (Session 11)
--
--  Locked decisions for v1:
--    * admin_users is a SEPARATE table from staff. The founder happens to
--      hold both rows (staff for tablet PIN, admin_users for web access),
--      but identity surfaces stay decoupled — future admins (regional ops,
--      customer success) may never use a tablet.
--    * is_admin() helper resolves auth.uid() against admin_users.
--      All admin-only RPCs check it as the FIRST statement.
--    * 2FA deferred to v1.1.
--    * Read-only impersonation deferred to Session 13 (needs Edge Function
--      to mint a service-role-signed JWT).
--    * Existing refund_approve and manual_wallet_adjust are retrofitted
--      with is_admin() checks via CREATE OR REPLACE; their signatures
--      and behaviour stay the same. Then GRANT EXECUTE to authenticated
--      so the admin web tablet auth user can invoke them.
--    * churn_threshold_days lives on venue_config so it's tunable later
--      without code change. Default 60.
--
--  Changes summary:
--    1) admin_users table + RLS (super_admin can manage admins).
--    2) is_admin() / is_super_admin() helpers.
--    3) venue_config.churn_threshold_days (default 60).
--    4) refund_approve + manual_wallet_adjust retrofitted with is_admin()
--       check and re-granted to authenticated.
--    5) New admin_* RPCs:
--         admin_create_user, admin_update_role, admin_deactivate_user
--         admin_create_staff, admin_reset_staff_pin, admin_deactivate_staff
--         admin_set_venue_config
--         admin_birthday_reservation_contact / _confirm / _complete
--         admin_family_search
--    6) Realtime publication adds: admin_users.
--    7) Bootstrap admin_users INSERT commented out at bottom — run after
--       creating the auth.users row in Supabase Studio.
--
-- ---------------------------------------------------------------------------
--  BOOTSTRAP CEREMONY — manual steps after this migration runs:
--
--    1. Create the founder admin auth user via Supabase Studio:
--         Auth → Users → Add user → Create new user
--         Email:           planovativediaries@gmail.com
--         Password:        <generate strong 24-char random; 1Password>
--         Auto-confirm:    YES (founder mailbox; no verification mail)
--       Copy the resulting auth user UUID.
--
--    2. Run this INSERT (replace the placeholder UUID):
--         INSERT INTO admin_users (auth_user_id, name, email, role)
--         VALUES (
--           '<paste-uuid-from-step-1>',
--           'Rajesh',
--           'planovativediaries@gmail.com',
--           'super_admin'
--         );
--
--    3. Sign in to admin web (Chrome) with the same email/password.
--       The admin app verifies the admin_users row exists + is_active before
--       letting you past /admin/login.
--
--    4. Future admins are added from /admin/users in the admin web. Don't
--       hand-roll INSERTs after this point — admin_create_user enforces the
--       audit trail and role checks.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  1. admin_users table
--
--  auth_user_id is unique — each Supabase auth identity maps to exactly
--  one admin_users row (deactivated rows still exist for audit purposes).
--  email is duplicated from auth.users.email for query convenience and to
--  survive auth user soft-deletes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  email           TEXT NOT NULL UNIQUE,
  role            TEXT NOT NULL DEFAULT 'admin'
                  CHECK (role IN ('admin', 'super_admin')),
  is_active       BOOLEAN NOT NULL DEFAULT true,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deactivated_at  TIMESTAMPTZ,
  deactivated_by  UUID REFERENCES admin_users(id),
  audit_metadata  JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_admin_users_active
  ON admin_users(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_admin_users_email_lower
  ON admin_users (lower(email));

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- RLS: any active admin can SELECT (so the admin web can list admins);
-- only super_admin can INSERT/UPDATE/DELETE (enforced via is_super_admin()
-- check in the admin_create_user / admin_update_role / admin_deactivate_user
-- RPCs — RLS just gates the read path).
CREATE POLICY admin_users_select ON admin_users
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users a
       WHERE a.auth_user_id = auth.uid() AND a.is_active = true
    )
  );

-- No INSERT/UPDATE/DELETE policies — those go through SECURITY DEFINER RPCs.

COMMENT ON TABLE admin_users IS
  'Web admin identities. Separate from staff (which is tablet-PIN scoped). '
  'Founder may hold both rows; that is expected.';

-- ---------------------------------------------------------------------------
--  2. is_admin() / is_super_admin() helpers
--
--  STABLE so they're safely cacheable per-statement. SECURITY DEFINER so
--  callers don't need direct read access to admin_users (RLS would block
--  the admin checking themselves before they're "admin enough" to see
--  the table — circular).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(
    SELECT 1 FROM admin_users
     WHERE auth_user_id = auth.uid() AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION is_super_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(
    SELECT 1 FROM admin_users
     WHERE auth_user_id = auth.uid()
       AND is_active = true
       AND role = 'super_admin'
  );
$$;

REVOKE EXECUTE ON FUNCTION is_admin()       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION is_super_admin() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION is_admin()       TO authenticated;
GRANT  EXECUTE ON FUNCTION is_super_admin() TO authenticated;

-- ---------------------------------------------------------------------------
--  3. venue_config.churn_threshold_days
-- ---------------------------------------------------------------------------
ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS churn_threshold_days INTEGER NOT NULL DEFAULT 60;
COMMENT ON COLUMN venue_config.churn_threshold_days IS
  'Days of inactivity after which a family is considered churned (used by '
  'admin reactivation reports). Default 60.';

-- ---------------------------------------------------------------------------
--  4. Retrofit refund_approve with is_admin() check + re-grant
--
--  Existing signature: (UUID, UUID, UUID) — preserved. Behaviour unchanged
--  except: the FIRST line is now `IF NOT is_admin() THEN RAISE EXCEPTION
--  'not_authorised'; END IF;`. Re-granted to authenticated so admin web
--  can call directly (was service_role only).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION refund_approve(
  p_refund_id UUID,
  p_approver_id UUID,
  p_venue_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_refund refunds%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_refund FROM refunds WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_refund.status <> 'pending' THEN RAISE EXCEPTION 'invalid_state'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF v_config.require_two_person_for_debit AND p_approver_id = v_refund.staff_pin_id THEN
    RAISE EXCEPTION 'two_person_required';
  END IF;

  UPDATE refunds SET status = 'approved', approved_by = p_approver_id, approved_at = now()
    WHERE id = p_refund_id;

  IF v_refund.destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + v_refund.amount_paise, updated_at = now()
      WHERE family_id = v_refund.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type
    ) VALUES (
      v_refund.family_id, 'refund', v_refund.amount_paise, v_wallet.balance_paise, 'system',
      v_refund.id, 'refund'
    );

    UPDATE refunds SET status = 'completed' WHERE id = p_refund_id;

    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (v_refund.family_id, 'refund_processed',
            'Refund credited to wallet',
            'Your refund of ' || (v_refund.amount_paise / 100)::TEXT || ' has been added.',
            '/wallet', v_refund.id);
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_approver_id, 'admin', 'refund.approve', 'refund', p_refund_id, p_venue_id,
          jsonb_build_object('amount_paise', v_refund.amount_paise,
                             'destination', v_refund.destination));

  RETURN jsonb_build_object('success', true, 'refund_id', v_refund.id);
END $$;

GRANT EXECUTE ON FUNCTION refund_approve(UUID, UUID, UUID) TO authenticated;

-- ---------------------------------------------------------------------------
--  5. Retrofit manual_wallet_adjust with is_admin() check + re-grant
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION manual_wallet_adjust(
  p_family_id UUID,
  p_amount_paise INTEGER,
  p_reason TEXT,
  p_admin_id UUID,
  p_venue_id UUID,
  p_second_approver_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing wallet_transactions%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_type TEXT;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_amount_paise = 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions
      WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  IF p_amount_paise < 0 AND v_config.require_two_person_for_debit THEN
    IF p_second_approver_id IS NULL OR p_second_approver_id = p_admin_id THEN
      RAISE EXCEPTION 'two_person_required';
    END IF;
  END IF;

  v_type := CASE WHEN p_amount_paise > 0 THEN 'manual_credit' ELSE 'manual_debit' END;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
  IF p_amount_paise < 0 AND v_wallet.balance_paise + p_amount_paise < 0 THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets SET balance_paise = balance_paise + p_amount_paise, updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    metadata, idempotency_key
  ) VALUES (
    p_family_id, v_type, p_amount_paise, v_wallet.balance_paise, 'system',
    jsonb_build_object('reason', p_reason, 'admin_id', p_admin_id,
                       'second_approver_id', p_second_approver_id),
    p_idempotency_key
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_admin_id, 'admin', 'wallet.manual_adjust', 'family', p_family_id, p_venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'reason', p_reason,
                             'second_approver_id', p_second_approver_id));

  RETURN jsonb_build_object(
    'success', true,
    'new_balance_paise', v_wallet.balance_paise,
    'type', v_type
  );
END $$;

GRANT EXECUTE ON FUNCTION manual_wallet_adjust(UUID, INTEGER, TEXT, UUID, UUID, UUID, TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
--  6. admin_create_user (super_admin only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_create_user(
  p_auth_user_id UUID,
  p_name TEXT,
  p_email TEXT,
  p_role TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_role NOT IN ('admin','super_admin') THEN RAISE EXCEPTION 'invalid_role'; END IF;
  IF p_email IS NULL OR length(trim(p_email)) = 0 THEN RAISE EXCEPTION 'email_required'; END IF;

  INSERT INTO admin_users (auth_user_id, name, email, role)
  VALUES (p_auth_user_id, p_name, lower(trim(p_email)), p_role)
  RETURNING id INTO v_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (auth.uid(), 'admin', 'admin.create_user', 'admin_users', v_id,
          jsonb_build_object('email', lower(trim(p_email)), 'role', p_role));

  RETURN jsonb_build_object('success', true, 'admin_id', v_id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_create_user(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_create_user(UUID, TEXT, TEXT, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  7. admin_update_role (super_admin only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_update_role(
  p_admin_id UUID,
  p_new_role TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_old_role TEXT;
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_new_role NOT IN ('admin','super_admin') THEN RAISE EXCEPTION 'invalid_role'; END IF;

  SELECT role INTO v_old_role FROM admin_users WHERE id = p_admin_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE admin_users SET role = p_new_role WHERE id = p_admin_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, old_value, new_value)
  VALUES (auth.uid(), 'admin', 'admin.update_role', 'admin_users', p_admin_id,
          jsonb_build_object('role', v_old_role),
          jsonb_build_object('role', p_new_role));

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION admin_update_role(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_update_role(UUID, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
--  8. admin_deactivate_user (super_admin only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_deactivate_user(
  p_admin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_self_id UUID;
BEGIN
  IF NOT is_super_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT id INTO v_self_id FROM admin_users WHERE auth_user_id = auth.uid();
  IF v_self_id = p_admin_id THEN RAISE EXCEPTION 'cannot_deactivate_self'; END IF;

  UPDATE admin_users SET
    is_active = false,
    deactivated_at = now(),
    deactivated_by = v_self_id
  WHERE id = p_admin_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (auth.uid(), 'admin', 'admin.deactivate_user', 'admin_users', p_admin_id);

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION admin_deactivate_user(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_deactivate_user(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
--  9. admin_create_staff
--
--  Creates a staff row with bcrypt-hashed PIN + force_pin_change=true.
--  Returns the generated PIN ONCE (caller must show it to the admin
--  immediately and not persist).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_create_staff(
  p_venue_id UUID,
  p_name TEXT,
  p_phone TEXT,
  p_email TEXT,
  p_role TEXT,
  p_pin TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_role NOT IN ('cashier','kitchen_staff','manager','super_admin') THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'invalid_pin';
  END IF;

  INSERT INTO staff (
    venue_id, name, phone, email, role, pin_hash, force_pin_change, is_active
  ) VALUES (
    p_venue_id, p_name, p_phone, lower(trim(p_email)), p_role,
    crypt(p_pin, gen_salt('bf')),
    true, true
  ) RETURNING id INTO v_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (auth.uid(), 'admin', 'staff.create', 'staff', v_id, p_venue_id,
          jsonb_build_object('name', p_name, 'role', p_role));

  RETURN jsonb_build_object('success', true, 'staff_id', v_id);
END $$;

REVOKE EXECUTE ON FUNCTION admin_create_staff(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_create_staff(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. admin_reset_staff_pin
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_reset_staff_pin(
  p_staff_id UUID,
  p_new_pin TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_venue_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_new_pin IS NULL OR p_new_pin !~ '^[0-9]{4}$' THEN
    RAISE EXCEPTION 'invalid_pin';
  END IF;

  SELECT venue_id INTO v_venue_id FROM staff WHERE id = p_staff_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE staff SET
    pin_hash = crypt(p_new_pin, gen_salt('bf')),
    force_pin_change = true,
    last_pin_used_at = NULL
  WHERE id = p_staff_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (auth.uid(), 'admin', 'staff.reset_pin', 'staff', p_staff_id, v_venue_id);

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION admin_reset_staff_pin(UUID, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_reset_staff_pin(UUID, TEXT) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. admin_deactivate_staff
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_deactivate_staff(
  p_staff_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_venue_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT venue_id INTO v_venue_id FROM staff WHERE id = p_staff_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  UPDATE staff SET is_active = false WHERE id = p_staff_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (auth.uid(), 'admin', 'staff.deactivate', 'staff', p_staff_id, v_venue_id);

  RETURN jsonb_build_object('success', true);
END $$;

REVOKE EXECUTE ON FUNCTION admin_deactivate_staff(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_deactivate_staff(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. admin_set_venue_config
--
--  Generic key-value setter. Accepts a JSONB patch and merges it into
--  venue_config. Whitelist of allowed keys at the top — adding a new
--  key requires a migration so the editor doesn't accidentally clobber
--  fields with rejection-worthy semantics (e.g. JSON schema for
--  topup_offers).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_set_venue_config(
  p_venue_id UUID,
  p_patch JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_old JSONB;
  v_key TEXT;
  v_allowed TEXT[] := ARRAY[
    'session_1hr_price_paise',
    'session_2hr_price_paise',
    'session_extension_per_hour_paise',
    'overtime_per_min_paise',
    'gst_percent',
    'walkin_food_gst_percent',
    'cashback_percent',
    'topup_offers',
    'low_balance_threshold_paise',
    'reactivation_credit_paise',
    'reactivation_expiry_days',
    'churn_threshold_days',
    'ios_min_supported_version',
    'ios_latest_version',
    'android_min_supported_version',
    'android_latest_version',
    'require_two_person_for_debit',
    'wall_of_legends_enabled',
    'wall_of_legends_anonymise'
  ];
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  -- Reject any patch keys not in the whitelist.
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    IF NOT (v_key = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'config_key_not_allowed: %', v_key;
    END IF;
  END LOOP;

  -- Capture old values (for the keys being changed) for audit.
  SELECT jsonb_object_agg(key, value)
    INTO v_old
    FROM (
      SELECT k AS key, to_jsonb(venue_config) -> k AS value
        FROM venue_config, jsonb_object_keys(p_patch) k
       WHERE venue_id = p_venue_id
    ) t;

  -- Apply the patch one key at a time. Dynamic SQL because we don't have
  -- a single jsonb-merge column; this also enforces that each value is
  -- castable to the column type before commit.
  FOR v_key IN SELECT jsonb_object_keys(p_patch) LOOP
    EXECUTE format(
      'UPDATE venue_config SET %I = ($1->>%L)::%s WHERE venue_id = $2',
      v_key, v_key,
      (SELECT data_type FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'venue_config'
          AND column_name = v_key)
    ) USING p_patch, p_venue_id;
  END LOOP;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id,
    old_value, new_value
  ) VALUES (
    auth.uid(), 'admin', 'config.update', 'venue_config', p_venue_id,
    p_venue_id, v_old, p_patch
  );

  RETURN jsonb_build_object('success', true, 'updated_keys', p_patch);
END $$;

REVOKE EXECUTE ON FUNCTION admin_set_venue_config(UUID, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_set_venue_config(UUID, JSONB) TO authenticated;

-- ---------------------------------------------------------------------------
-- 13. Birthday CRM RPCs
--
--  Thin wrappers over status transitions. The RPCs are admin-only;
--  customers can't push their own reservation forward via these.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_birthday_reservation_contact(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status <> 'interested' THEN RAISE EXCEPTION 'invalid_state'; END IF;

  UPDATE birthday_reservations SET status = 'admin_contacted'
   WHERE id = p_reservation_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_60',
    'Our team has been in touch',
    'Check WhatsApp for details on your birthday booking.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id)
  VALUES (auth.uid(), 'admin', 'birthday.contact', 'birthday_reservation',
          p_reservation_id, v_res.venue_id);

  RETURN jsonb_build_object('success', true);
END $$;

CREATE OR REPLACE FUNCTION admin_birthday_reservation_confirm(
  p_reservation_id UUID,
  p_slot_date DATE,
  p_slot_start_time TIME,
  p_slot_end_time TIME,
  p_deposit_paid_paise INTEGER DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_res FROM birthday_reservations
    WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('interested','admin_contacted') THEN
    RAISE EXCEPTION 'invalid_state';
  END IF;

  UPDATE birthday_reservations SET
    status = 'confirmed',
    slot_date = p_slot_date,
    slot_start_time = p_slot_start_time,
    slot_end_time = p_slot_end_time,
    deposit_paid_paise = p_deposit_paid_paise,
    balance_paise = package_price_paise - p_deposit_paid_paise
  WHERE id = p_reservation_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_30',
    'You are confirmed!',
    'Your birthday booking is locked. We will see you on '
      || to_char(p_slot_date, 'Dy, Mon DD') || '.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (auth.uid(), 'admin', 'birthday.confirm', 'birthday_reservation',
          p_reservation_id, v_res.venue_id,
          jsonb_build_object(
            'slot_date', p_slot_date,
            'slot_start_time', p_slot_start_time,
            'deposit_paid_paise', p_deposit_paid_paise
          ));

  RETURN jsonb_build_object('success', true);
END $$;

CREATE OR REPLACE FUNCTION admin_birthday_reservation_complete(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID;
  v_result JSONB;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  v_admin_id := auth.uid();

  -- Delegate to the existing complete RPC (Session 9) which awards the
  -- birthday-exclusive cards + 1000 XP split + flips status to completed.
  v_result := birthday_reservation_complete(p_reservation_id, v_admin_id);
  RETURN v_result;
END $$;

REVOKE EXECUTE ON FUNCTION admin_birthday_reservation_contact(UUID)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_birthday_reservation_confirm(UUID, DATE, TIME, TIME, INTEGER)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION admin_birthday_reservation_complete(UUID)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION admin_birthday_reservation_contact(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_birthday_reservation_confirm(UUID, DATE, TIME, TIME, INTEGER)
  TO authenticated;
GRANT EXECUTE ON FUNCTION admin_birthday_reservation_complete(UUID) TO authenticated;

-- birthday_reservation_complete is called via SECURITY DEFINER from the
-- wrapper above; admin web doesn't need direct access.

-- ---------------------------------------------------------------------------
-- 14. admin_family_search
--
--  Used by the customer search UI. Phone exact match wins; otherwise
--  partial name match. Returns a small projection (id, name, phone,
--  child names) with a hard cap so the list stays sane.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_family_search(
  p_query TEXT,
  p_limit INTEGER DEFAULT 50
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_q TEXT;
  v_results JSONB;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  v_q := lower(trim(coalesce(p_query, '')));
  IF length(v_q) < 2 THEN
    RETURN jsonb_build_object('results', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(t ORDER BY t->>'last_visit' DESC NULLS LAST), '[]'::jsonb)
    INTO v_results
    FROM (
      SELECT jsonb_build_object(
        'id', f.id,
        'name', f.name,
        'phone', f.phone,
        'is_walk_in', f.is_walk_in,
        'is_anonymised', f.is_anonymised,
        'children', COALESCE((
          SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name))
            FROM children c
           WHERE c.family_id = f.id AND c.deleted_at IS NULL
        ), '[]'::jsonb),
        'wallet_balance_paise', COALESCE(
          (SELECT balance_paise FROM wallets w WHERE w.family_id = f.id), 0
        ),
        'last_visit', (
          SELECT MAX(s.created_at)::TEXT FROM sessions s WHERE s.family_id = f.id
        )
      ) AS t
        FROM families f
       WHERE f.deleted_at IS NULL
         AND f.is_walk_in = false
         AND (
              f.phone LIKE '%' || v_q || '%'
           OR lower(f.name) LIKE '%' || v_q || '%'
           OR EXISTS (
                SELECT 1 FROM children c
                 WHERE c.family_id = f.id
                   AND c.deleted_at IS NULL
                   AND lower(c.name) LIKE '%' || v_q || '%'
              )
         )
       LIMIT p_limit
    ) sub;

  RETURN jsonb_build_object('results', v_results);
END $$;

REVOKE EXECUTE ON FUNCTION admin_family_search(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_family_search(TEXT, INTEGER) TO authenticated;

-- ---------------------------------------------------------------------------
-- 15. Realtime publication
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'admin_users'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_users';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 16. Bootstrap admin_users row — RUN MANUALLY after creating auth user
--
-- INSERT INTO admin_users (auth_user_id, name, email, role)
-- VALUES (
--   '<paste-uuid-from-supabase-studio>',
--   'Rajesh',
--   'planovativediaries@gmail.com',
--   'super_admin'
-- );
-- ---------------------------------------------------------------------------
