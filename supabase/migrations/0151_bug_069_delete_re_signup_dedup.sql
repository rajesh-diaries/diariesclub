-- 0151 — BUG-069: Delete-account + re-signup
--
-- Symptom 1: deleting an account then re-signing up with the same phone
-- silently left families.deleted_at + is_anonymised set on the same row.
-- Sessions, push, wallet credits all then operated on a "deleted" row,
-- producing weird half-deleted behaviour (push skipped with reason
-- 'family_inactive' was the trigger that surfaced this — see lib/BUGS.md).
--
-- Symptom 2: once the re-signup flow is fixed, the existing first-time
-- coupon check (WELCOME100, max_per_family=1) was keyed on family_id
-- only. With the same family_id reused across delete + re-signup the
-- redemption history was correctly preserved... EXCEPT that
-- family_anonymise deletes coupon_redemptions + referral_conversions
-- rows during anonymisation. After deletion, there's no historical
-- record on the family_id, so re-signup → claim WELCOME100 again → loop.
-- Same vector for referrals (claim ₹100 referee + ₹100 referrer, delete,
-- repeat). One SMS (₹0.20) per cycle.
--
-- Fix
-- ---
-- (a) family_anonymise: STOP deleting coupon_redemptions and
--     referral_conversions. These rows contain no PII (just family_id +
--     coupon_id / referrer_family_id + amounts) and are needed for
--     post-deletion dedup. Auth users + families.id are 1:1 (re-signup
--     reuses the same UUID via find_auth_user_for_otp), so existing
--     family_id-keyed checks continue to work without any change.
--
-- (b) session_create: refuse if families.deleted_at IS NOT NULL.
--     Defense in depth — the trigger bug today was a session running on
--     a tombstoned family because session_create didn't check.
--
-- (c) qr_scan_validate: same guard on families.deleted_at.
--
-- App-store compliance: PII (name, phone, children with names/birthdays,
-- wallet history, fcm token, etc.) is still scrubbed by family_anonymise.
-- Only audit-grade metadata rows (coupon_redemptions / referral_conversions)
-- are preserved, which contain no PII and are needed for fraud prevention
-- — fully acceptable under Apple's "delete account" guideline.
--
-- The auth-otp Edge Function still needs a separate patch to revive the
-- tombstoned families row when the same phone re-signs up (clear
-- deleted_at + is_anonymised, restore phone). That ships as an Edge
-- Function deploy, not a migration.

-- ===========================================================================
-- (a) family_anonymise — preserve dedup history
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.family_anonymise(p_family_id uuid, p_confirmation_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_family  families%ROWTYPE;
  v_forfeit INTEGER := 0;
BEGIN
  IF p_confirmation_token <> 'DELETE' THEN RAISE EXCEPTION 'invalid_confirmation'; END IF;

  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_family FROM families WHERE id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  SELECT COALESCE(balance_paise, 0) INTO v_forfeit
    FROM wallets WHERE family_id = p_family_id;

  DELETE FROM hero_card_collection
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM stage_perk_grants
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM gift_redemptions
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM hero_quest_progress
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM hero_within_unlocks
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM parent_logged_moments
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM streak_records
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM xp_events
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM workshop_registrations
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM birthday_journey_state
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM child_birthday_wishes_sent
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);
  DELETE FROM hero_recaps
   WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);

  DELETE FROM session_extensions
   WHERE session_id IN (SELECT id FROM sessions WHERE family_id = p_family_id);
  -- BUG-069: coupon_redemptions kept (was: DELETE FROM coupon_redemptions WHERE family_id = p_family_id)
  DELETE FROM session_pre_bookings WHERE family_id = p_family_id;
  DELETE FROM sessions WHERE family_id = p_family_id;

  DELETE FROM order_items
   WHERE order_id IN (SELECT id FROM orders WHERE family_id = p_family_id);
  DELETE FROM fit_meal_orders WHERE family_id = p_family_id;
  DELETE FROM orders WHERE family_id = p_family_id;

  DELETE FROM wallet_transactions WHERE family_id = p_family_id;
  DELETE FROM refunds WHERE family_id = p_family_id;
  UPDATE wallets SET balance_paise = 0, coins_balance = 0,
                     coins_lifetime = 0, held_paise = 0, updated_at = now()
   WHERE family_id = p_family_id;

  DELETE FROM birthday_reservations WHERE family_id = p_family_id;
  DELETE FROM saved_birthday_packages WHERE family_id = p_family_id;

  DELETE FROM visit_milestones WHERE family_id = p_family_id;
  DELETE FROM brand_badges WHERE family_id = p_family_id;
  DELETE FROM fit_subscription_waitlist WHERE family_id = p_family_id;
  UPDATE reactivation_contacts SET redeemed_family_id = NULL
   WHERE redeemed_family_id = p_family_id;

  -- BUG-069: referral_conversions kept (was: DELETE FROM referral_conversions ...).
  -- The referrer side of the row may still point to a live family — we keep
  -- the row so that referrer can't be re-credited if the deleted family
  -- re-signs up and tries to redeem the same referrer's code again.

  DELETE FROM children WHERE family_id = p_family_id;
  DELETE FROM family_devices WHERE family_id = p_family_id;
  DELETE FROM notifications WHERE family_id = p_family_id;

  -- referral_code is NOT NULL on families. It's an opaque token (not PII)
  -- so we keep the existing value rather than try to null it. Same with
  -- referrer_family_id — already nulled at the referral_conversions delete.
  UPDATE families SET
    is_anonymised     = true,
    deleted_at        = now(),
    name              = 'Deleted User',
    phone             = '+910000' || substr(p_family_id::TEXT, 1, 10),
    fcm_token         = NULL,
    fcm_platform      = NULL,
    app_version       = NULL,
    marketing_consent = false,
    has_children      = false,
    is_cafe_only      = false,
    notification_preferences = '{}'::jsonb,
    last_active_at    = now()
  WHERE id = p_family_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    p_family_id, 'customer', 'family.anonymise', 'family', p_family_id,
    jsonb_build_object(
      'deleted_at', now(),
      'wallet_forfeited_paise', v_forfeit,
      'note', 'bug_069_v7_preserve_redemption_history'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'anonymised_at', now(),
    'wallet_forfeited_paise', v_forfeit
  );
END $function$;

-- ===========================================================================
-- (b) session_create — refuse on deleted family
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.session_create(p_venue_id uuid, p_family_id uuid, p_child_id uuid, p_duration_minutes integer, p_payment_method text, p_staff_pin_id uuid DEFAULT NULL::uuid, p_is_guest boolean DEFAULT false, p_guest_phone text DEFAULT NULL::text, p_pre_booking_id uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text, p_coupon_code text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_session     sessions%ROWTYPE;
  v_existing    sessions%ROWTYPE;
  v_wallet      wallets%ROWTYPE;
  v_config      venue_config%ROWTYPE;
  v_amount      INTEGER;
  v_base_amount INTEGER;
  v_pending_scan BOOLEAN;
  v_status      TEXT;
  v_started_at  TIMESTAMPTZ;
  v_expires_at  TIMESTAMPTZ;
  v_grace_at    TIMESTAMPTZ;
  v_coupon      coupons%ROWTYPE;
  v_normalized_code TEXT;
  v_coupon_discount INTEGER := 0;
  v_family_uses INTEGER;
  v_redemption_id UUID;
  v_family_deleted BOOLEAN;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  -- BUG-069: refuse to start a session for a deleted/anonymised family.
  -- (auth-otp normally revives tombstones on re-signup; this is defense
  -- in depth in case any code path bypasses that revival.)
  SELECT (deleted_at IS NOT NULL) INTO v_family_deleted
    FROM families WHERE id = p_family_id;
  IF v_family_deleted IS TRUE THEN RAISE EXCEPTION 'family_deleted'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id', v_existing.id, 'status', v_existing.status,
        'expires_at', v_existing.expires_at, 'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

  v_base_amount := CASE WHEN p_duration_minutes = 60
                        THEN v_config.session_1hr_price_paise
                        ELSE v_config.session_2hr_price_paise END;

  -- Coupon validation (unchanged logic)
  IF p_coupon_code IS NOT NULL AND length(trim(p_coupon_code)) > 0 THEN
    v_normalized_code := upper(trim(p_coupon_code));
    SELECT * INTO v_coupon FROM coupons WHERE upper(code) = v_normalized_code FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'coupon_invalid_code'; END IF;
    IF NOT v_coupon.is_active THEN RAISE EXCEPTION 'coupon_inactive'; END IF;
    IF v_coupon.valid_from > now() THEN RAISE EXCEPTION 'coupon_not_yet_active'; END IF;
    IF v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < now() THEN
      RAISE EXCEPTION 'coupon_expired';
    END IF;
    IF v_coupon.max_uses IS NOT NULL AND v_coupon.uses_count >= v_coupon.max_uses THEN
      RAISE EXCEPTION 'coupon_exhausted';
    END IF;
    IF v_base_amount < v_coupon.min_order_paise THEN
      RAISE EXCEPTION 'coupon_min_order_not_met';
    END IF;
    SELECT COUNT(*) INTO v_family_uses FROM coupon_redemptions
      WHERE coupon_id = v_coupon.id AND family_id = p_family_id;
    IF v_family_uses >= v_coupon.max_per_family THEN
      RAISE EXCEPTION 'coupon_already_used_by_family';
    END IF;

    IF v_coupon.type = 'percent_off' THEN
      v_coupon_discount := (v_base_amount * v_coupon.value) / 100;
      IF v_coupon.max_discount_paise IS NOT NULL AND v_coupon_discount > v_coupon.max_discount_paise THEN
        v_coupon_discount := v_coupon.max_discount_paise;
      END IF;
    ELSIF v_coupon.type = 'flat_off' THEN
      v_coupon_discount := LEAST(v_coupon.value, v_base_amount);
    ELSIF v_coupon.type = 'free_session' THEN
      v_coupon_discount := v_base_amount;
    END IF;
  END IF;

  v_amount := v_base_amount - v_coupon_discount;
  v_pending_scan := (p_staff_pin_id IS NULL);

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
    IF (v_wallet.balance_paise - v_wallet.held_paise) < v_amount THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_amount,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'session_debit', -v_amount, v_wallet.balance_paise,
      'wallet', 'session', p_idempotency_key
    );
  END IF;

  IF v_pending_scan THEN
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

  IF p_payment_method = 'wallet' THEN
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

  IF v_coupon_discount > 0 THEN
    UPDATE coupons SET uses_count = uses_count + 1, updated_at = now()
      WHERE id = v_coupon.id;
    INSERT INTO coupon_redemptions(coupon_id, family_id, session_id, discount_paise)
      VALUES (v_coupon.id, p_family_id, v_session.id, v_coupon_discount)
      RETURNING id INTO v_redemption_id;
    UPDATE sessions SET coupon_redemption_id = v_redemption_id
      WHERE id = v_session.id;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.create', 'session', v_session.id, p_venue_id,
    jsonb_build_object(
      'child_id', p_child_id, 'duration_minutes', p_duration_minutes,
      'base_amount_paise', v_base_amount,
      'coupon_discount_paise', v_coupon_discount,
      'amount_paise', v_amount,
      'coupon_code', CASE WHEN v_coupon_discount > 0 THEN v_coupon.code ELSE NULL END,
      'payment_method', p_payment_method,
      'status', v_status, 'debit_at_create', true, 'pending_scan', v_pending_scan
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'session_id', v_session.id, 'status', v_status,
    'expires_at', v_session.expires_at, 'grace_force_close_at', v_session.grace_force_close_at,
    'amount_paise', v_amount, 'base_amount_paise', v_base_amount,
    'coupon_discount_paise', v_coupon_discount, 'coupon_redemption_id', v_redemption_id
  );
END $function$;

-- ===========================================================================
-- (c) qr_scan_validate — refuse on deleted family
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.qr_scan_validate(p_qr_payload text, p_staff_pin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tablet     tablet_devices%ROWTYPE;
  v_decoded    JSONB;
  v_session_id UUID;
  v_session    sessions%ROWTYPE;
  v_config     venue_config%ROWTYPE;
  v_child_name TEXT;
  v_was_pending BOOLEAN;
  v_family_deleted BOOLEAN;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM staff
     WHERE id = p_staff_pin_id AND venue_id = v_tablet.venue_id AND is_active = true
  ) THEN RAISE EXCEPTION 'staff_not_authorised'; END IF;

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

  SELECT * INTO v_session FROM sessions WHERE id = v_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.venue_id != v_tablet.venue_id THEN RAISE EXCEPTION 'session_wrong_venue'; END IF;
  IF v_session.status NOT IN ('pending','active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;
  IF v_session.staff_scanned_at IS NOT NULL THEN RAISE EXCEPTION 'qr_already_scanned'; END IF;

  -- BUG-069: refuse if the underlying family has been deleted/anonymised.
  SELECT (deleted_at IS NOT NULL) INTO v_family_deleted
    FROM families WHERE id = v_session.family_id;
  IF v_family_deleted IS TRUE THEN RAISE EXCEPTION 'family_deleted'; END IF;

  v_was_pending := (v_session.status = 'pending');

  IF v_was_pending THEN
    SELECT * INTO v_config FROM venue_config WHERE venue_id = v_tablet.venue_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;

    UPDATE sessions SET
      status               = 'active',
      started_at           = now(),
      expires_at           = now() + (v_session.duration_minutes || ' minutes')::INTERVAL,
      grace_force_close_at = now() + ((v_session.duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,
      staff_scanned_at     = now(),
      staff_pin_id         = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  ELSE
    UPDATE sessions SET
      staff_scanned_at = now(),
      staff_pin_id     = p_staff_pin_id
    WHERE id = v_session.id RETURNING * INTO v_session;
  END IF;

  SELECT name INTO v_child_name FROM children WHERE id = v_session.child_id;

  IF v_was_pending THEN
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => v_session.family_id,
        p_type         => 'session_started',
        p_args         => jsonb_build_object(
          'child_name', COALESCE(v_child_name, 'your kid'),
          'session_id', v_session.id::text
        ),
        p_reference_id => v_session.id
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
      VALUES (NULL, 'system', 'session.start_push_failed', 'session', v_session.id, v_session.venue_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    p_staff_pin_id, 'staff',
    CASE WHEN v_was_pending THEN 'session.qr_scan_activate' ELSE 'session.qr_scan_revisit' END,
    'session', v_session.id, v_tablet.venue_id,
    jsonb_build_object('was_pending', v_was_pending, 'amount_paise', v_session.amount_paise)
  );

  RETURN jsonb_build_object(
    'success', true, 'session_id', v_session.id,
    'child_id', v_session.child_id, 'child_name', v_child_name,
    'status', v_session.status, 'expires_at', v_session.expires_at,
    'was_pending', v_was_pending
  );
END $function$;
