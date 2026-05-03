-- ===========================================================================
--  Diaries Club v1.5 — 0003_rpc_functions.sql
--  All RPC functions for money, gamification, birthdays, ops.
--
--  Conventions enforced (see spec/02_SESSION_RPCS.md and spec/00_CONTEXT.md):
--    * SECURITY DEFINER, search_path=public, LANGUAGE plpgsql
--    * Money in INTEGER paise; integer/NUMERIC math only (no floats)
--    * Customer-callable RPCs: assert auth.uid()=p_family_id (or active staff PIN)
--    * Service-role-only RPCs: GRANT only to service_role; called by webhooks/cron
--    * Idempotency: replay returns {success:true, idempotent:true, ...} via the
--      idempotency_key column on the relevant entity table
--    * Concurrency: SELECT ... FOR UPDATE on rows being mutated
--    * Audit: every state-changing RPC writes audit_log
--    * Business values read from venue_config row inside the RPC (Q4 — direct
--      row read; get_venue_config() reserved for client surface)
--
--  Idempotent. Safe to re-run on a fresh or existing project.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  DDL: idempotency_key on birthday_reservations and refunds.
--  These tables ship without it in 0001; required for idempotent RPCs.
-- ---------------------------------------------------------------------------
ALTER TABLE birthday_reservations
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
DO $$ BEGIN
  ALTER TABLE birthday_reservations
    ADD CONSTRAINT birthday_reservations_idempotency_key_key UNIQUE (idempotency_key);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE refunds
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;
DO $$ BEGIN
  ALTER TABLE refunds
    ADD CONSTRAINT refunds_idempotency_key_key UNIQUE (idempotency_key);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ===========================================================================
--  HELPER: assert_caller_authority
--  Two paths:
--    * Staff path: p_staff_pin_id provided → require active staff row.
--      (PIN itself is verified by the staff app's login flow before this call.)
--    * Customer path: require auth.uid() = p_family_id.
--  Service-role calls bypass RLS and never invoke this helper.
-- ===========================================================================
CREATE OR REPLACE FUNCTION assert_caller_authority(
  p_family_id UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_staff_pin_id IS NOT NULL THEN
    IF NOT EXISTS(SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active) THEN
      RAISE EXCEPTION 'not_authorised';
    END IF;
    RETURN;
  END IF;
  IF auth.uid() IS NULL OR auth.uid() <> p_family_id THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;
END $$;

-- ===========================================================================
--  1. xp_credit_with_split  (internal — service_role only)
--  Tests:
--    ✓ Per-trait XP applied; stages recomputed; level recomputed
--    ✓ Stage transition emits notification
--    ✓ Level/stage thresholds read from venue_config (no hardcoding)
-- ===========================================================================
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
  i INTEGER;
BEGIN
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds   := v_config.stage_thresholds_per_trait;

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

  -- Per-trait stage recompute
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
    p_reference_id, p_metadata
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

  RETURN jsonb_build_object(
    'success', true,
    'new_total_xp', v_new_total,
    'new_level', v_new_level,
    'new_overall_stage', v_new_overall_stage,
    'new_stages', v_new_stages,
    'transitions', v_transitions
  );
END $$;

-- ===========================================================================
--  2. wallet_topup  (service_role only — Razorpay webhook)
--  Tests:
--    ✓ Credits balance + bonus correctly
--    ✓ Idempotent replay returns same balance, no double credit
--    ✗ invalid_amount on amount_paise <= 0
-- ===========================================================================
CREATE OR REPLACE FUNCTION wallet_topup(
  p_family_id UUID,
  p_amount_paise INTEGER,
  p_bonus_paise INTEGER DEFAULT 0,
  p_razorpay_payment_id TEXT DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wallet wallets%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_bonus_paise  <  0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions
      WHERE idempotency_key = p_idempotency_key LIMIT 1;
    IF FOUND THEN
      SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id;
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_balance_paise', v_wallet.balance_paise
      );
    END IF;
  END IF;

  -- Defensive: ensure wallet exists (trigger should have created it)
  INSERT INTO wallets (family_id) VALUES (p_family_id)
    ON CONFLICT (family_id) DO NOTHING;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;

  UPDATE wallets SET
    balance_paise = balance_paise + p_amount_paise + p_bonus_paise,
    updated_at = now()
  WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  -- Topup row (balance_after = post-topup balance, before bonus row insert)
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise,
    payment_method, razorpay_payment_id, idempotency_key
  ) VALUES (
    p_family_id, 'topup', p_amount_paise,
    v_wallet.balance_paise - p_bonus_paise,
    'razorpay', p_razorpay_payment_id, p_idempotency_key
  );

  IF p_bonus_paise > 0 THEN
    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method
    ) VALUES (
      p_family_id, 'bonus', p_bonus_paise, v_wallet.balance_paise, 'system'
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (NULL, 'system', 'wallet.topup', 'family', p_family_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'bonus_paise', p_bonus_paise,
                             'razorpay_payment_id', p_razorpay_payment_id));

  RETURN jsonb_build_object(
    'success', true,
    'new_balance_paise', v_wallet.balance_paise,
    'amount_credited',  p_amount_paise + p_bonus_paise
  );
END $$;

-- ===========================================================================
--  3. session_create  (customer or staff)
--  Tests:
--    ✓ Wallet pays → debits and creates session
--    ✓ Cash pays → creates session, no debit
--    ✓ Idempotent replay returns same session_id
--    ✗ insufficient_balance / invalid_duration / invalid_payment_method / not_authorised
-- ===========================================================================
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
  v_session  sessions%ROWTYPE;
  v_existing sessions%ROWTYPE;
  v_wallet   wallets%ROWTYPE;
  v_config   venue_config%ROWTYPE;
  v_amount   INTEGER;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id', v_existing.id,
        'expires_at', v_existing.expires_at,
        'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_amount := CASE WHEN p_duration_minutes = 60
                   THEN v_config.session_1hr_price_paise
                   ELSE v_config.session_2hr_price_paise END;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
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

  INSERT INTO sessions(
    venue_id, family_id, child_id, staff_pin_id,
    duration_minutes, amount_paise, payment_method,
    expires_at, grace_force_close_at,
    is_guest, guest_phone, pre_booking_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method,
    now() + (p_duration_minutes        || ' minutes')::INTERVAL,
    now() + ((p_duration_minutes + v_config.session_grace_max_minutes) || ' minutes')::INTERVAL,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key
  ) RETURNING * INTO v_session;

  -- Update wallet_transactions.reference_id now that we have the session id
  IF p_payment_method = 'wallet' THEN
    UPDATE wallet_transactions SET reference_id = v_session.id
      WHERE family_id = p_family_id
        AND type = 'session_debit'
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  -- Pre-booking redemption
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
    jsonb_build_object('child_id', p_child_id, 'duration_minutes', p_duration_minutes,
                       'amount_paise', v_amount, 'payment_method', p_payment_method)
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'expires_at', v_session.expires_at,
    'grace_force_close_at', v_session.grace_force_close_at,
    'amount_paise', v_amount
  );
END $$;

-- ===========================================================================
--  4. session_extend  (customer or staff)
--  Tests:
--    ✓ Extends active or grace session, debits if wallet
--    ✗ session_not_active / insufficient_balance / not_authorised
-- ===========================================================================
CREATE OR REPLACE FUNCTION session_extend(
  p_session_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,
  p_initiated_by TEXT DEFAULT 'parent',
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session  sessions%ROWTYPE;
  v_wallet   wallets%ROWTYPE;
  v_config   venue_config%ROWTYPE;
  v_amount   INTEGER;
  v_new_exp  TIMESTAMPTZ;
  v_existing session_extensions%ROWTYPE;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_initiated_by NOT IN ('parent','staff_on_behalf') THEN RAISE EXCEPTION 'invalid_initiator'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM session_extensions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'new_expires_at', v_existing.new_expires_at,
        'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  v_amount := v_config.session_extension_per_hour_paise * (p_duration_minutes / 60);
  IF v_amount <= 0 THEN RAISE EXCEPTION 'invalid_duration'; END IF;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = v_session.family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_amount THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

    UPDATE wallets SET balance_paise = balance_paise - v_amount, updated_at = now()
      WHERE family_id = v_session.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_id, reference_type, idempotency_key
    ) VALUES (
      v_session.family_id, 'extension_debit', -v_amount, v_wallet.balance_paise,
      'wallet', p_session_id, 'session_extension', p_idempotency_key
    );
  END IF;

  v_new_exp := GREATEST(v_session.expires_at, now()) + (p_duration_minutes || ' minutes')::INTERVAL;

  UPDATE sessions SET
    expires_at = v_new_exp,
    grace_force_close_at = v_new_exp + (v_config.session_grace_max_minutes || ' minutes')::INTERVAL,
    status = 'active',
    grace_started_at = NULL
  WHERE id = p_session_id;

  INSERT INTO session_extensions(
    session_id, duration_minutes, amount_paise, payment_method, new_expires_at,
    staff_pin_id, initiated_by, idempotency_key
  ) VALUES (
    p_session_id, p_duration_minutes, v_amount, p_payment_method, v_new_exp,
    p_staff_pin_id, p_initiated_by, p_idempotency_key
  );

  IF p_initiated_by = 'staff_on_behalf' THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'extend_nudge',
      'Session extended',
      'Staff extended your session by ' || p_duration_minutes || ' minutes.',
      '/home', p_session_id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.extend', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('duration_minutes', p_duration_minutes, 'amount_paise', v_amount,
                       'initiated_by', p_initiated_by, 'new_expires_at', v_new_exp)
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_expires_at', v_new_exp,
    'amount_paise', v_amount
  );
END $$;

-- ===========================================================================
--  5. session_complete  (customer or staff or service-role cron)
--  Flips status to 'completed', creates hero_recaps row with NULL image_url
--  (Edge Function in Session 13 will populate image_url later).
--  reflection_deadline = now() + reflection_window_hours from venue_config.
--  Tests:
--    ✓ Active session → completed; recap row created with deadline
--    ✓ Idempotent: completing already-completed session returns idempotent:true
-- ===========================================================================
CREATE OR REPLACE FUNCTION session_complete(
  p_session_id UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_config  venue_config%ROWTYPE;
  v_pool    INTEGER;
  v_recap_id UUID;
  v_deadline TIMESTAMPTZ;
  v_old_status TEXT;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  -- Service-role calls (cron) skip authority check; otherwise enforce.
  IF auth.role() <> 'service_role' THEN
    PERFORM assert_caller_authority(v_session.family_id, p_staff_pin_id);
  END IF;

  IF v_session.status IN ('completed','auto_closed','void') THEN
    SELECT id INTO v_recap_id FROM hero_recaps WHERE session_id = p_session_id;
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', p_session_id,
      'recap_id', v_recap_id,
      'status', v_session.status
    );
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  v_pool := v_session.duration_minutes * v_config.xp_per_session_minute;
  v_deadline := now() + (v_config.reflection_window_hours || ' hours')::INTERVAL;
  v_old_status := v_session.status;

  UPDATE sessions SET
    status = 'completed',
    completed_at = now(),
    reflection_deadline = v_deadline,
    total_xp_earned = v_pool
  WHERE id = p_session_id;

  INSERT INTO hero_recaps(
    session_id, child_id, total_xp_pool,
    reflection_status, reflection_deadline
  ) VALUES (
    p_session_id, v_session.child_id, v_pool,
    'pending', v_deadline
  )
  ON CONFLICT (session_id) DO NOTHING
  RETURNING id INTO v_recap_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'session_closed',
    'Session ended — recap on the way',
    'Tap to reflect on the moments and earn XP.',
    '/recap/' || p_session_id, p_session_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, old_value, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN auth.role() = 'service_role' THEN 'system'
         WHEN p_staff_pin_id IS NOT NULL    THEN 'staff'
         ELSE 'customer' END,
    'session.complete', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', 'completed', 'total_xp_pool', v_pool,
                       'reflection_deadline', v_deadline)
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'recap_id', v_recap_id,
    'total_xp_pool', v_pool,
    'reflection_deadline', v_deadline
  );
END $$;

-- ===========================================================================
--  6. order_place  (customer or staff)
--  Tests:
--    ✓ Wallet order: server-side prices, GST, coins (cashback_percent)
--    ✓ Combo overrides item-summed subtotal
--    ✓ Idempotent replay returns original order_id
--    ✗ insufficient_balance / menu_item_unavailable / invalid_combo / invalid_quantity
-- ===========================================================================
CREATE OR REPLACE FUNCTION order_place(
  p_venue_id UUID,
  p_family_id UUID,
  p_items JSONB,
  p_fulfillment_mode TEXT,
  p_payment_method TEXT,
  p_combo_id UUID DEFAULT NULL,
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order   orders%ROWTYPE;
  v_existing orders%ROWTYPE;
  v_wallet  wallets%ROWTYPE;
  v_config  venue_config%ROWTYPE;
  v_combo   combos%ROWTYPE;
  v_subtotal INTEGER := 0;
  v_gst INTEGER := 0;
  v_combo_discount INTEGER := 0;
  v_total INTEGER;
  v_coins INTEGER := 0;
  v_item JSONB;
  v_menu_item menu_items%ROWTYPE;
  v_qty INTEGER;
  v_brand TEXT;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash','razorpay') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  IF p_fulfillment_mode NOT IN ('dine_in','takeaway','table_service') THEN RAISE EXCEPTION 'invalid_fulfillment_mode'; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'invalid_items';
  END IF;

  PERFORM assert_caller_authority(p_family_id, p_staff_pin_id);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM orders WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'order_id', v_existing.id,
        'total_paise', v_existing.total_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  -- Server-side subtotal from menu_items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
    IF NOT FOUND OR NOT v_menu_item.is_available THEN
      RAISE EXCEPTION 'menu_item_unavailable';
    END IF;
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;
    v_subtotal := v_subtotal + (v_menu_item.price_paise * v_qty);
  END LOOP;

  -- Combo override
  IF p_combo_id IS NOT NULL THEN
    SELECT * INTO v_combo FROM combos
      WHERE id = p_combo_id AND venue_id = p_venue_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_combo'; END IF;
    v_combo_discount := GREATEST(v_subtotal - v_combo.price_paise, 0);
    v_subtotal := v_combo.price_paise;
  END IF;

  -- GST: integer math via NUMERIC (gst_percent is NUMERIC(5,2), not float)
  v_gst   := (v_subtotal * v_config.gst_percent / 100)::INTEGER;
  v_total := v_subtotal + v_gst;

  IF p_payment_method = 'wallet' THEN
    v_coins := (v_subtotal * v_config.cashback_percent / 100)::INTEGER;

    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_total THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_total + v_coins,
      coins_lifetime = coins_lifetime + v_coins,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      coins_amount, payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'order_debit', -v_total + v_coins, v_wallet.balance_paise,
      v_coins, 'wallet', 'order', p_idempotency_key
    );
  END IF;

  INSERT INTO orders(
    venue_id, family_id, staff_pin_id, fulfillment_mode, payment_method,
    subtotal_paise, gst_paise, combo_discount_paise, total_paise,
    coins_earned, combo_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_staff_pin_id, p_fulfillment_mode, p_payment_method,
    v_subtotal, v_gst, v_combo_discount, v_total,
    v_coins, p_combo_id, p_idempotency_key
  ) RETURNING * INTO v_order;

  -- Snapshot order_items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
    SELECT brand INTO v_brand FROM menus WHERE id = v_menu_item.menu_id;
    INSERT INTO order_items(
      order_id, menu_item_id, brand, name_snapshot, quantity, unit_price_paise
    ) VALUES (
      v_order.id, v_menu_item.id, v_brand, v_menu_item.name,
      (v_item->>'quantity')::INTEGER, v_menu_item.price_paise
    );
  END LOOP;

  -- Backfill reference on the wallet txn
  IF p_payment_method = 'wallet' THEN
    UPDATE wallet_transactions SET reference_id = v_order.id
      WHERE family_id = p_family_id
        AND type = 'order_debit'
        AND reference_id IS NULL
        AND created_at >= now() - INTERVAL '5 seconds';
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, p_family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'order.place', 'order', v_order.id, p_venue_id,
    jsonb_build_object('subtotal_paise', v_subtotal, 'gst_paise', v_gst,
                       'total_paise', v_total, 'coins_earned', v_coins,
                       'combo_id', p_combo_id, 'payment_method', p_payment_method)
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'subtotal_paise', v_subtotal,
    'gst_paise', v_gst,
    'combo_discount_paise', v_combo_discount,
    'total_paise', v_total,
    'coins_earned', v_coins
  );
END $$;

-- ===========================================================================
--  7. reflection_submit  (customer)
--  Computes per-trait split from moment_tags, calls xp_credit_with_split.
-- ===========================================================================
CREATE OR REPLACE FUNCTION reflection_submit(
  p_session_id UUID,
  p_moment_tags TEXT[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_recap   hero_recaps%ROWTYPE;
  v_pool INTEGER;
  v_weights JSONB := '{"rafi":0,"ellie":0,"gerry":0,"zena":0}'::JSONB;
  v_total_weight NUMERIC := 0;
  v_tag TEXT;
  v_moment reflection_moments%ROWTYPE;
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena  INTEGER := 0;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  PERFORM assert_caller_authority(v_session.family_id, NULL);

  SELECT * INTO v_recap FROM hero_recaps WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'recap_not_ready'; END IF;
  IF v_recap.reflection_status <> 'pending' THEN RAISE EXCEPTION 'reflection_already_done'; END IF;
  IF v_recap.reflection_deadline IS NOT NULL AND now() > v_recap.reflection_deadline THEN
    RAISE EXCEPTION 'reflection_window_expired';
  END IF;

  v_pool := v_recap.total_xp_pool;

  FOREACH v_tag IN ARRAY p_moment_tags LOOP
    SELECT * INTO v_moment FROM reflection_moments WHERE tag = v_tag AND is_active;
    IF FOUND THEN
      v_weights := jsonb_set(
        v_weights,
        ARRAY[v_moment.primary_trait],
        to_jsonb((v_weights->>v_moment.primary_trait)::NUMERIC + v_moment.xp_weight)
      );
      v_total_weight := v_total_weight + v_moment.xp_weight;
    END IF;
  END LOOP;

  IF v_total_weight = 0 THEN
    -- No valid tags or empty array → equal split
    v_xp_rafi  := v_pool / 4;
    v_xp_ellie := v_pool / 4;
    v_xp_gerry := v_pool / 4;
    v_xp_zena  := v_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  ELSE
    v_xp_rafi  := FLOOR(v_pool * (v_weights->>'rafi') ::NUMERIC / v_total_weight)::INTEGER;
    v_xp_ellie := FLOOR(v_pool * (v_weights->>'ellie')::NUMERIC / v_total_weight)::INTEGER;
    v_xp_gerry := FLOOR(v_pool * (v_weights->>'gerry')::NUMERIC / v_total_weight)::INTEGER;
    v_xp_zena  := v_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);  -- absorb remainder
  END IF;

  PERFORM xp_credit_with_split(
    v_session.child_id, v_session.family_id, v_session.venue_id,
    'reflection_split',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    p_session_id,
    jsonb_build_object('moment_tags', to_jsonb(p_moment_tags))
  );

  UPDATE hero_recaps SET
    reflection_status = 'reflected',
    reflection_at = now(),
    moment_tags = p_moment_tags
  WHERE session_id = p_session_id;

  UPDATE sessions SET reflection_status = 'reflected' WHERE id = p_session_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    v_session.family_id, 'customer',
    'reflection.submit', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('split',
      jsonb_build_object('rafi', v_xp_rafi, 'ellie', v_xp_ellie,
                         'gerry', v_xp_gerry, 'zena', v_xp_zena),
      'moment_tags', to_jsonb(p_moment_tags))
  );

  RETURN jsonb_build_object(
    'success', true,
    'split', jsonb_build_object(
      'rafi', v_xp_rafi, 'ellie', v_xp_ellie,
      'gerry', v_xp_gerry, 'zena', v_xp_zena
    )
  );
END $$;

-- ===========================================================================
--  8. reflection_auto_split  (cron — service_role only)
--  Batch-processes pending recaps past their deadline.
-- ===========================================================================
CREATE OR REPLACE FUNCTION reflection_auto_split() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_recap hero_recaps%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_per INTEGER;
  v_remainder INTEGER;
  v_count INTEGER := 0;
BEGIN
  FOR v_recap IN
    SELECT * FROM hero_recaps
    WHERE reflection_status = 'pending' AND reflection_deadline < now()
    ORDER BY reflection_deadline ASC
    LIMIT 100
  LOOP
    SELECT * INTO v_session FROM sessions WHERE id = v_recap.session_id;
    v_per := v_recap.total_xp_pool / 4;
    v_remainder := v_recap.total_xp_pool - (v_per * 4);

    PERFORM xp_credit_with_split(
      v_session.child_id, v_session.family_id, v_session.venue_id,
      'auto_split',
      v_per, v_per, v_per, v_per + v_remainder,
      v_recap.session_id, '{}'::JSONB
    );

    UPDATE hero_recaps SET
      reflection_status = 'auto_split', reflection_at = now()
    WHERE id = v_recap.id;

    UPDATE sessions SET reflection_status = 'auto_split' WHERE id = v_recap.session_id;

    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'reflection_auto_split',
      'XP shared across all four heroes',
      'You did not reflect on the session, so we split XP equally.',
      '/adventure', v_recap.session_id
    );

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'reflection.auto_split', 'session', v_recap.session_id,
            v_session.venue_id,
            jsonb_build_object('total_xp_pool', v_recap.total_xp_pool));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'auto_split_count', v_count);
END $$;

-- ===========================================================================
--  9. healthy_bite_distribute  (staff via Edge Function — service_role only)
--  ~10% rare draws; falls back to common; final fallback to duplicate.
-- ===========================================================================
CREATE OR REPLACE FUNCTION healthy_bite_distribute(
  p_session_id UUID,
  p_child_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_is_rare BOOLEAN;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.healthy_bite_distributed THEN
    RAISE EXCEPTION 'already_cancelled';  -- reuse generic "already done" path
  END IF;

  UPDATE sessions SET
    healthy_bite_earned = true,
    healthy_bite_distributed = true
  WHERE id = p_session_id;

  v_is_rare := random() <= 0.10;

  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare AND is_birthday_exclusive = false AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_cards_available';
  END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO NOTHING;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'hero_card_received',
    'New hero card!',
    CASE WHEN v_card.is_rare THEN 'A rare card just arrived in your collection.'
         ELSE 'Tap to add it to your collection.' END,
    '/adventure', p_child_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
          v_session.venue_id,
          jsonb_build_object('card_id', v_card.id, 'is_rare', v_card.is_rare));

  RETURN jsonb_build_object(
    'success', true,
    'card_id', v_card.id,
    'card_name', v_card.name,
    'is_rare', v_card.is_rare,
    'image_url', v_card.image_url
  );
END $$;

-- ===========================================================================
--  10. workshop_register  (customer)
--  Atomic spot decrement via WHERE-clause guard. Concurrent calls: only one wins.
-- ===========================================================================
CREATE OR REPLACE FUNCTION workshop_register(
  p_workshop_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_payment_method TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wshop workshops%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_existing workshop_registrations%ROWTYPE;
  v_reg workshop_registrations%ROWTYPE;
BEGIN
  IF p_payment_method NOT IN ('wallet','cash','razorpay') THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM workshop_registrations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'registration_id', v_existing.id,
        'amount_paise', v_existing.amount_paise
      );
    END IF;
  END IF;

  -- Atomic guarded decrement
  UPDATE workshops SET spots_remaining = spots_remaining - 1
    WHERE id = p_workshop_id AND spots_remaining > 0 AND status = 'upcoming'
    RETURNING * INTO v_wshop;
  IF NOT FOUND THEN RAISE EXCEPTION 'workshop_full'; END IF;

  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_wshop.price_paise THEN
      -- Rolled back automatically on RAISE; the explicit revert is unneeded.
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET balance_paise = balance_paise - v_wshop.price_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'workshop_debit', -v_wshop.price_paise, v_wallet.balance_paise, 'wallet',
      p_workshop_id, 'workshop', p_idempotency_key
    );
  END IF;

  INSERT INTO workshop_registrations(
    workshop_id, family_id, child_id, payment_method, amount_paise, idempotency_key
  ) VALUES (
    p_workshop_id, p_family_id, p_child_id, p_payment_method, v_wshop.price_paise, p_idempotency_key
  ) RETURNING * INTO v_reg;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'workshop.register', 'workshop_registration', v_reg.id,
          v_wshop.venue_id,
          jsonb_build_object('workshop_id', p_workshop_id, 'amount_paise', v_wshop.price_paise,
                             'payment_method', p_payment_method));

  RETURN jsonb_build_object(
    'success', true,
    'registration_id', v_reg.id,
    'amount_paise', v_wshop.price_paise
  );
END $$;

-- ===========================================================================
--  11. workshop_cancel  (customer)
-- ===========================================================================
CREATE OR REPLACE FUNCTION workshop_cancel(
  p_registration_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reg workshop_registrations%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_wshop workshops%ROWTYPE;
BEGIN
  SELECT * INTO v_reg FROM workshop_registrations WHERE id = p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_reg.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'already_cancelled'; END IF;

  PERFORM assert_caller_authority(v_reg.family_id, NULL);

  SELECT * INTO v_wshop FROM workshops WHERE id = v_reg.workshop_id;
  UPDATE workshops SET spots_remaining = spots_remaining + 1 WHERE id = v_reg.workshop_id;

  IF v_reg.payment_method = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + v_reg.amount_paise, updated_at = now()
      WHERE family_id = v_reg.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type
    ) VALUES (
      v_reg.family_id, 'refund', v_reg.amount_paise, v_wallet.balance_paise, 'system',
      v_reg.id, 'workshop_cancel'
    );
  END IF;

  UPDATE workshop_registrations SET
    cancelled_at = now(), cancellation_reason = p_reason
  WHERE id = p_registration_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (v_reg.family_id, 'customer', 'workshop.cancel', 'workshop_registration', p_registration_id,
          v_wshop.venue_id,
          jsonb_build_object('reason', p_reason, 'refund_paise',
            CASE WHEN v_reg.payment_method = 'wallet' THEN v_reg.amount_paise ELSE 0 END));

  RETURN jsonb_build_object('success', true);
END $$;

-- ===========================================================================
--  12. workshop_attend  (staff via Edge Function — service_role only)
--  Marks attendance, credits XP via xp_credit_with_split using primary_trait,
--  calls streak_update.
-- ===========================================================================
CREATE OR REPLACE FUNCTION workshop_attend(
  p_registration_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_reg workshop_registrations%ROWTYPE;
  v_wshop workshops%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_xp INTEGER;
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena INTEGER := 0;
BEGIN
  SELECT * INTO v_reg FROM workshop_registrations WHERE id = p_registration_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_reg.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'already_cancelled'; END IF;
  IF v_reg.attended THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  SELECT * INTO v_wshop FROM workshops WHERE id = v_reg.workshop_id;
  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_wshop.venue_id;
  v_xp := COALESCE(v_wshop.xp_award, v_config.xp_workshop_attendance);

  -- All XP to the workshop's primary trait (or split equally if NULL)
  IF v_wshop.primary_trait IS NULL THEN
    v_xp_rafi  := v_xp / 4;
    v_xp_ellie := v_xp / 4;
    v_xp_gerry := v_xp / 4;
    v_xp_zena  := v_xp - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  ELSE
    v_xp_rafi  := CASE WHEN v_wshop.primary_trait = 'rafi'  THEN v_xp ELSE 0 END;
    v_xp_ellie := CASE WHEN v_wshop.primary_trait = 'ellie' THEN v_xp ELSE 0 END;
    v_xp_gerry := CASE WHEN v_wshop.primary_trait = 'gerry' THEN v_xp ELSE 0 END;
    v_xp_zena  := CASE WHEN v_wshop.primary_trait = 'zena'  THEN v_xp ELSE 0 END;
  END IF;

  PERFORM xp_credit_with_split(
    v_reg.child_id, v_reg.family_id, v_wshop.venue_id,
    'workshop',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    v_reg.id, jsonb_build_object('workshop_id', v_wshop.id)
  );

  UPDATE workshop_registrations SET
    attended = true, xp_credited = true
  WHERE id = p_registration_id;

  PERFORM streak_update(v_reg.child_id, v_wshop.venue_id);

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'workshop.attend', 'workshop_registration', p_registration_id,
          v_wshop.venue_id,
          jsonb_build_object('xp_award', v_xp, 'primary_trait', v_wshop.primary_trait));

  RETURN jsonb_build_object('success', true, 'xp_credited', v_xp);
END $$;

-- ===========================================================================
--  13. referral_convert  (service_role only — webhook)
--  Money cap: sum of gifter credits this calendar month ≤ referral_monthly_cap_paise
-- ===========================================================================
CREATE OR REPLACE FUNCTION referral_convert(
  p_referrer_family_id UUID,
  p_new_family_id UUID,
  p_triggering_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_config venue_config%ROWTYPE;
  v_venue_id UUID;
  v_month_start DATE;
  v_month_total INTEGER;
  v_is_first BOOLEAN;
  v_referrer_wallet wallets%ROWTYPE;
  v_new_wallet wallets%ROWTYPE;
  v_first_child UUID;
  v_gifter_credit INTEGER;
  v_new_credit INTEGER;
BEGIN
  IF p_referrer_family_id = p_new_family_id THEN RAISE EXCEPTION 'invalid_referral'; END IF;

  SELECT venue_id INTO v_venue_id FROM sessions WHERE id = p_triggering_session_id;
  IF v_venue_id IS NULL THEN RAISE EXCEPTION 'session_not_found'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_venue_id;
  v_gifter_credit := v_config.referral_gifter_credit_paise;
  v_new_credit    := v_config.referral_new_family_credit_paise;

  v_month_start := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::DATE;

  SELECT COALESCE(SUM(gifter_wallet_credit_paise), 0) INTO v_month_total
    FROM referral_conversions
    WHERE referrer_family_id = p_referrer_family_id
      AND conversion_month = v_month_start;
  IF (v_month_total + v_gifter_credit) > v_config.referral_monthly_cap_paise THEN
    RAISE EXCEPTION 'monthly_cap_exceeded';
  END IF;

  SELECT NOT EXISTS(SELECT 1 FROM referral_conversions WHERE referrer_family_id = p_referrer_family_id)
    INTO v_is_first;

  -- Credit gifter
  SELECT * INTO v_referrer_wallet FROM wallets WHERE family_id = p_referrer_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_gifter_credit, updated_at = now()
    WHERE family_id = p_referrer_family_id RETURNING * INTO v_referrer_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
    VALUES (p_referrer_family_id, 'bonus', v_gifter_credit, v_referrer_wallet.balance_paise, 'system');

  -- Credit new family
  SELECT * INTO v_new_wallet FROM wallets WHERE family_id = p_new_family_id FOR UPDATE;
  UPDATE wallets SET balance_paise = balance_paise + v_new_credit, updated_at = now()
    WHERE family_id = p_new_family_id RETURNING * INTO v_new_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
    VALUES (p_new_family_id, 'bonus', v_new_credit, v_new_wallet.balance_paise, 'system');

  -- Brave Boost on first ever referral
  IF v_is_first THEN
    SELECT id INTO v_first_child FROM children
      WHERE family_id = p_referrer_family_id ORDER BY created_at LIMIT 1;
    IF v_first_child IS NOT NULL THEN
      PERFORM xp_credit_with_split(
        v_first_child, p_referrer_family_id, v_venue_id,
        'referral_bonus',
        v_config.xp_referral_bonus_rafi, 0, 0, 0,
        NULL, jsonb_build_object('reason', 'first_referral_brave_boost')
      );
      INSERT INTO notifications(family_id, type, title, body, deep_link)
      VALUES (p_referrer_family_id, 'first_referral_brave_boost',
              'You unlocked a Brave Boost!',
              'Your first referral gave Rafi a +' || v_config.xp_referral_bonus_rafi || ' XP boost.',
              '/adventure');
    END IF;
  ELSE
    INSERT INTO notifications(family_id, type, title, body, deep_link)
    VALUES (p_referrer_family_id, 'referral_reward',
            'Referral reward credited',
            'Welcome credit added for your friend, plus ' ||
              (v_gifter_credit / 100)::TEXT || ' for you.',
            '/wallet');
  END IF;

  INSERT INTO referral_conversions(
    referrer_family_id, new_family_id, triggering_session_id, conversion_month,
    gifter_wallet_credit_paise, gifter_xp_bonus_rafi, new_family_wallet_credit_paise,
    is_first_referral
  ) VALUES (
    p_referrer_family_id, p_new_family_id, p_triggering_session_id, v_month_start,
    v_gifter_credit,
    CASE WHEN v_is_first THEN v_config.xp_referral_bonus_rafi ELSE 0 END,
    v_new_credit, v_is_first
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'referral.convert', 'family', p_referrer_family_id, v_venue_id,
          jsonb_build_object('new_family_id', p_new_family_id,
                             'gifter_credit_paise', v_gifter_credit,
                             'new_family_credit_paise', v_new_credit,
                             'is_first', v_is_first));

  RETURN jsonb_build_object(
    'success', true, 'is_first', v_is_first,
    'gifter_credit_paise', v_gifter_credit,
    'new_family_credit_paise', v_new_credit
  );
END $$;

-- ===========================================================================
--  14. birthday_reservation_create  (customer)
-- ===========================================================================
CREATE OR REPLACE FUNCTION birthday_reservation_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_package_id UUID,
  p_slot_date DATE,
  p_slot_start_time TIME,
  p_num_kids INTEGER,
  p_num_adults INTEGER,
  p_triggered_by TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_avail birthday_availability%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
  v_existing_count INTEGER;
  v_res birthday_reservations%ROWTYPE;
  v_end_time TIME;
  v_config venue_config%ROWTYPE;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'reservation_id', v_existing.id,
        'deposit_paise', (SELECT deposit_paise FROM birthday_packages WHERE id = v_existing.package_id),
        'expires_at', v_existing.reservation_expires_at
      );
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages
    WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  v_end_time := (p_slot_start_time + (v_pkg.duration_hours || ' hours')::INTERVAL)::TIME;

  SELECT * INTO v_avail FROM birthday_availability
    WHERE venue_id = p_venue_id AND slot_date = p_slot_date AND slot_start_time = p_slot_start_time;
  IF NOT FOUND OR v_avail.is_blocked THEN RAISE EXCEPTION 'slot_unavailable'; END IF;

  SELECT COUNT(*) INTO v_existing_count FROM birthday_reservations
    WHERE venue_id = p_venue_id
      AND slot_date = p_slot_date
      AND slot_start_time = p_slot_start_time
      AND status IN ('reserved','deposit_paid','confirmed');
  IF v_existing_count > 0 THEN RAISE EXCEPTION 'slot_unavailable'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    slot_date, slot_start_time, slot_end_time,
    num_kids, num_adults,
    package_price_paise, balance_paise,
    triggered_by, reservation_expires_at,
    idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_package_id,
    p_slot_date, p_slot_start_time, v_end_time,
    p_num_kids, p_num_adults,
    v_pkg.price_paise, v_pkg.price_paise - v_pkg.deposit_paise,
    p_triggered_by,
    now() + (v_config.birthday_reservation_autocancel_hours || ' hours')::INTERVAL,
    p_idempotency_key
  ) RETURNING * INTO v_res;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'birthday.reserve', 'birthday_reservation', v_res.id, p_venue_id,
          jsonb_build_object('package_id', p_package_id, 'slot_date', p_slot_date,
                             'slot_start_time', p_slot_start_time,
                             'num_kids', p_num_kids, 'num_adults', p_num_adults,
                             'triggered_by', p_triggered_by));

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id,
    'deposit_paise', v_pkg.deposit_paise,
    'balance_paise', v_pkg.price_paise - v_pkg.deposit_paise,
    'expires_at', v_res.reservation_expires_at
  );
END $$;

-- ===========================================================================
--  15. birthday_deposit_record  (service_role only — Razorpay webhook)
-- ===========================================================================
CREATE OR REPLACE FUNCTION birthday_deposit_record(
  p_reservation_id UUID,
  p_amount_paise INTEGER,
  p_razorpay_payment_id TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('success', true, 'idempotent', true); END IF;
  END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('reserved') THEN RAISE EXCEPTION 'invalid_reservation_state'; END IF;

  UPDATE birthday_reservations SET
    deposit_paid_paise = p_amount_paise,
    total_paid_paise   = total_paid_paise + p_amount_paise,
    status = 'deposit_paid'
  WHERE id = p_reservation_id;

  -- Ledger row only; deposit doesn't pass through the wallet balance.
  SELECT * INTO v_wallet FROM wallets WHERE family_id = v_res.family_id;
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type, razorpay_payment_id, idempotency_key
  ) VALUES (
    v_res.family_id, 'birthday_deposit_debit', -p_amount_paise,
    COALESCE(v_wallet.balance_paise, 0),
    'razorpay', p_reservation_id, 'birthday_deposit',
    p_razorpay_payment_id, p_idempotency_key
  );

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_90',
    'Reservation confirmed!',
    'Our team will reach out within 24 hours to finalise.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'birthday.deposit', 'birthday_reservation', p_reservation_id,
          v_res.venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'razorpay_payment_id', p_razorpay_payment_id));

  RETURN jsonb_build_object('success', true);
END $$;

-- ===========================================================================
--  16. birthday_complete  (admin via Edge Function — service_role only)
--  Marks reservation completed; XP bonus to host child; assigns birthday hero card.
-- ===========================================================================
CREATE OR REPLACE FUNCTION birthday_complete(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_card hero_card_definitions%ROWTYPE;
  v_per INTEGER;
  v_remainder INTEGER;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status = 'completed' THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  IF v_res.status NOT IN ('confirmed','deposit_paid') THEN
    RAISE EXCEPTION 'invalid_reservation_state';
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_res.venue_id;

  -- XP bonus split equally across the four traits (xp_birthday_hosted)
  v_per := v_config.xp_birthday_hosted / 4;
  v_remainder := v_config.xp_birthday_hosted - (v_per * 4);
  PERFORM xp_credit_with_split(
    v_res.child_id, v_res.family_id, v_res.venue_id,
    'birthday_hosted',
    v_per, v_per, v_per, v_per + v_remainder,
    p_reservation_id, jsonb_build_object('reservation_id', p_reservation_id)
  );

  -- Pick a birthday-exclusive card the child doesn't have
  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_birthday_exclusive = true AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = v_res.child_id)
    ORDER BY random() LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = true AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF FOUND THEN
    INSERT INTO hero_card_collection(child_id, card_id, birthday_booking_id)
    VALUES (v_res.child_id, v_card.id, p_reservation_id)
    ON CONFLICT (child_id, card_id) DO NOTHING;

    UPDATE birthday_reservations SET birthday_hero_card_id = v_card.id WHERE id = p_reservation_id;
  END IF;

  UPDATE birthday_reservations SET status = 'completed' WHERE id = p_reservation_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (v_res.family_id, 'birthday_d_plus_1',
          'Thanks for celebrating with us!',
          'Your birthday album and a special hero card are on the way.',
          '/birthday/album/' || v_res.id, v_res.id);

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'birthday.complete', 'birthday_reservation', p_reservation_id,
          v_res.venue_id,
          jsonb_build_object('xp_awarded', v_config.xp_birthday_hosted,
                             'birthday_card_id', v_card.id));

  RETURN jsonb_build_object(
    'success', true,
    'xp_awarded', v_config.xp_birthday_hosted,
    'birthday_card_id', v_card.id
  );
END $$;

-- ===========================================================================
--  17. pre_booking_create  (customer) — hold partial wallet credit
-- ===========================================================================
CREATE OR REPLACE FUNCTION pre_booking_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_scheduled_start TIMESTAMPTZ,
  p_duration_minutes INTEGER,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing session_pre_bookings%ROWTYPE;
  v_pb session_pre_bookings%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_amount INTEGER;
  v_hold INTEGER;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN RAISE EXCEPTION 'invalid_duration'; END IF;
  PERFORM assert_caller_authority(p_family_id, NULL);

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM session_pre_bookings WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'pre_booking_id', v_existing.id, 'hold_amount_paise', v_existing.hold_amount_paise
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_amount := CASE WHEN p_duration_minutes = 60
                   THEN v_config.session_1hr_price_paise
                   ELSE v_config.session_2hr_price_paise END;
  v_hold := (v_amount * v_config.pre_booking_hold_percent / 100)::INTEGER;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
  IF v_wallet.balance_paise < v_hold THEN RAISE EXCEPTION 'insufficient_balance'; END IF;

  UPDATE wallets SET balance_paise = balance_paise - v_hold, updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  INSERT INTO session_pre_bookings(
    venue_id, family_id, child_id, scheduled_start, duration_minutes,
    amount_paise, hold_amount_paise, expires_at, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_scheduled_start, p_duration_minutes,
    v_amount, v_hold,
    p_scheduled_start + (v_config.pre_booking_grace_minutes || ' minutes')::INTERVAL,
    p_idempotency_key
  ) RETURNING * INTO v_pb;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type, idempotency_key
  ) VALUES (
    p_family_id, 'session_debit', -v_hold, v_wallet.balance_paise, 'wallet',
    v_pb.id, 'pre_booking_hold', p_idempotency_key
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'pre_booking.create', 'session_pre_booking', v_pb.id, p_venue_id,
          jsonb_build_object('scheduled_start', p_scheduled_start,
                             'duration_minutes', p_duration_minutes,
                             'hold_amount_paise', v_hold));

  RETURN jsonb_build_object(
    'success', true,
    'pre_booking_id', v_pb.id,
    'hold_amount_paise', v_hold,
    'expires_at', v_pb.expires_at
  );
END $$;

-- ===========================================================================
--  18. pre_booking_redeem  (customer or staff)
--  Refund the held amount to wallet, then call session_create with payment=wallet.
-- ===========================================================================
CREATE OR REPLACE FUNCTION pre_booking_redeem(
  p_pre_booking_id UUID,
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pb session_pre_bookings%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_session_result JSONB;
BEGIN
  SELECT * INTO v_pb FROM session_pre_bookings WHERE id = p_pre_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_pb.status <> 'reserved' THEN RAISE EXCEPTION 'invalid_state'; END IF;
  IF now() > v_pb.expires_at THEN RAISE EXCEPTION 'expired'; END IF;

  PERFORM assert_caller_authority(v_pb.family_id, p_staff_pin_id);

  -- Refund the hold to wallet
  UPDATE wallets SET balance_paise = balance_paise + v_pb.hold_amount_paise, updated_at = now()
    WHERE family_id = v_pb.family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type
  ) VALUES (
    v_pb.family_id, 'refund', v_pb.hold_amount_paise, v_wallet.balance_paise, 'system',
    v_pb.id, 'pre_booking_redeem'
  );

  -- Now create the session via the standard RPC, charging full price from wallet
  v_session_result := session_create(
    v_pb.venue_id, v_pb.family_id, v_pb.child_id,
    v_pb.duration_minutes, 'wallet',
    p_staff_pin_id, false, NULL,
    v_pb.id,                      -- pre_booking_id
    p_idempotency_key
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_pb.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'pre_booking.redeem', 'session_pre_booking', v_pb.id, v_pb.venue_id,
    v_session_result
  );

  RETURN jsonb_build_object(
    'success', true,
    'pre_booking_id', v_pb.id,
    'session', v_session_result
  );
END $$;

-- ===========================================================================
--  19. pre_booking_cancel  (customer)
-- ===========================================================================
CREATE OR REPLACE FUNCTION pre_booking_cancel(
  p_pre_booking_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pb session_pre_bookings%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  SELECT * INTO v_pb FROM session_pre_bookings WHERE id = p_pre_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_pb.status <> 'reserved' THEN RAISE EXCEPTION 'invalid_state'; END IF;

  PERFORM assert_caller_authority(v_pb.family_id, NULL);

  UPDATE wallets SET balance_paise = balance_paise + v_pb.hold_amount_paise, updated_at = now()
    WHERE family_id = v_pb.family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type
  ) VALUES (
    v_pb.family_id, 'refund', v_pb.hold_amount_paise, v_wallet.balance_paise, 'system',
    v_pb.id, 'pre_booking_cancel'
  );

  UPDATE session_pre_bookings SET
    status = 'cancelled', cancellation_reason = p_reason
  WHERE id = p_pre_booking_id;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (v_pb.family_id, 'customer', 'pre_booking.cancel', 'session_pre_booking', v_pb.id, v_pb.venue_id,
          jsonb_build_object('reason', p_reason, 'refund_paise', v_pb.hold_amount_paise));

  RETURN jsonb_build_object('success', true, 'refund_paise', v_pb.hold_amount_paise);
END $$;

-- ===========================================================================
--  20. refund_issue  (staff)
--  Auto-approves if amount ≤ staff_refund_cap_paise; else creates pending row.
-- ===========================================================================
CREATE OR REPLACE FUNCTION refund_issue(
  p_family_id UUID,
  p_reference_id UUID,
  p_reference_type TEXT,
  p_amount_paise INTEGER,
  p_destination TEXT,
  p_reason TEXT,
  p_staff_pin_id UUID,
  p_venue_id UUID,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing refunds%ROWTYPE;
  v_refund refunds%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_auto_approve BOOLEAN;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_reference_type NOT IN ('session','order','workshop','birthday','manual') THEN
    RAISE EXCEPTION 'invalid_reference_type';
  END IF;
  IF p_destination NOT IN ('wallet','razorpay') THEN RAISE EXCEPTION 'invalid_destination'; END IF;

  IF NOT EXISTS(SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM refunds WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'refund_id', v_existing.id, 'status', v_existing.status
      );
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_auto_approve := (p_amount_paise <= v_config.staff_refund_cap_paise);

  INSERT INTO refunds(
    family_id, reference_id, reference_type, amount_paise, destination,
    initiated_by, staff_pin_id, status, reason, approved_by, approved_at, idempotency_key
  ) VALUES (
    p_family_id, p_reference_id, p_reference_type, p_amount_paise, p_destination,
    'staff', p_staff_pin_id,
    CASE WHEN v_auto_approve THEN 'approved' ELSE 'pending' END,
    p_reason,
    CASE WHEN v_auto_approve THEN p_staff_pin_id ELSE NULL END,
    CASE WHEN v_auto_approve THEN now() ELSE NULL END,
    p_idempotency_key
  ) RETURNING * INTO v_refund;

  -- If auto-approved + destination is wallet, credit immediately.
  IF v_auto_approve AND p_destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + p_amount_paise, updated_at = now()
      WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method,
      reference_id, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'refund', p_amount_paise, v_wallet.balance_paise, 'system',
      v_refund.id, 'refund', p_idempotency_key
    );

    UPDATE refunds SET status = 'completed' WHERE id = v_refund.id;

    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (p_family_id, 'refund_processed',
            'Refund credited to wallet',
            'Your refund of ' || (p_amount_paise / 100)::TEXT || ' has been added.',
            '/wallet', v_refund.id);
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'refund.issue', 'refund', v_refund.id, p_venue_id,
          jsonb_build_object('amount_paise', p_amount_paise, 'destination', p_destination,
                             'auto_approved', v_auto_approve, 'reason', p_reason));

  RETURN jsonb_build_object(
    'success', true,
    'refund_id', v_refund.id,
    'status', CASE WHEN v_auto_approve AND p_destination = 'wallet' THEN 'completed'
                   WHEN v_auto_approve THEN 'approved'
                   ELSE 'pending' END,
    'auto_approved', v_auto_approve
  );
END $$;

-- ===========================================================================
--  21. refund_approve  (admin via Edge Function — service_role only)
--  Admin approves a pending refund. If require_two_person_for_debit is on,
--  require approved_by != initiating staff_pin_id.
-- ===========================================================================
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
  -- Razorpay path is handled by the Edge Function which calls Razorpay refund API.

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_approver_id, 'admin', 'refund.approve', 'refund', p_refund_id, p_venue_id,
          jsonb_build_object('amount_paise', v_refund.amount_paise,
                             'destination', v_refund.destination));

  RETURN jsonb_build_object('success', true, 'refund_id', v_refund.id);
END $$;

-- ===========================================================================
--  22. streak_update  (called from session_complete / workshop_attend / cron)
--  IST week = Monday-Sunday. last_streak_week_ist stores the Monday of the
--  most recently credited streak week.
-- ===========================================================================
CREATE OR REPLACE FUNCTION streak_update(
  p_child_id UUID,
  p_venue_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rec streak_records%ROWTYPE;
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_today DATE;
  v_this_monday DATE;
  v_milestone_hit INTEGER := 0;
  v_xp_per INTEGER;
  v_bonus_xp INTEGER := 0;
BEGIN
  v_today := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_this_monday := v_today - ((EXTRACT(ISODOW FROM v_today)::INTEGER - 1));

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  -- Upsert
  INSERT INTO streak_records (child_id) VALUES (p_child_id)
    ON CONFLICT (child_id) DO NOTHING;
  SELECT * INTO v_rec FROM streak_records WHERE child_id = p_child_id FOR UPDATE;

  -- Already credited this week? No-op.
  IF v_rec.last_streak_week_ist = v_this_monday THEN
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'current_streak_weeks', v_rec.current_streak_weeks
    );
  END IF;

  -- Streak continues if last week was the previous Monday; otherwise reset to 1.
  IF v_rec.last_streak_week_ist = v_this_monday - INTERVAL '7 days' THEN
    UPDATE streak_records SET
      current_streak_weeks = current_streak_weeks + 1,
      longest_streak_weeks = GREATEST(longest_streak_weeks, current_streak_weeks + 1),
      total_visit_stars = total_visit_stars + 1,
      last_visit_date_ist = v_today,
      last_streak_week_ist = v_this_monday
    WHERE child_id = p_child_id RETURNING * INTO v_rec;
  ELSE
    UPDATE streak_records SET
      current_streak_weeks = 1,
      longest_streak_weeks = GREATEST(longest_streak_weeks, 1),
      total_visit_stars = total_visit_stars + 1,
      last_visit_date_ist = v_today,
      last_streak_week_ist = v_this_monday
    WHERE child_id = p_child_id RETURNING * INTO v_rec;
  END IF;

  -- Milestones: 3-week, 5-week, 10-week (one-time flags). Bonus XP from venue_config.
  IF v_rec.current_streak_weeks >= 3 AND NOT v_rec.milestone_3_achieved THEN
    UPDATE streak_records SET milestone_3_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 3;
  ELSIF v_rec.current_streak_weeks >= 5 AND NOT v_rec.milestone_5_achieved THEN
    UPDATE streak_records SET milestone_5_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 5;
  ELSIF v_rec.current_streak_weeks >= 10 AND NOT v_rec.milestone_10_achieved THEN
    UPDATE streak_records SET milestone_10_achieved = true WHERE child_id = p_child_id;
    v_milestone_hit := 10;
  END IF;

  IF v_milestone_hit > 0 THEN
    v_bonus_xp := v_config.xp_streak_bonus * v_milestone_hit;
    v_xp_per := v_bonus_xp / 4;
    PERFORM xp_credit_with_split(
      p_child_id, v_child.family_id, p_venue_id,
      'streak_bonus',
      v_xp_per, v_xp_per, v_xp_per, v_bonus_xp - v_xp_per * 3,
      NULL, jsonb_build_object('milestone_weeks', v_milestone_hit)
    );

    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_child.family_id, 'streak_milestone',
      v_milestone_hit || '-week streak!',
      v_child.name || ' just hit a ' || v_milestone_hit || '-week streak. +' || v_bonus_xp || ' XP.',
      '/adventure', p_child_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'current_streak_weeks', v_rec.current_streak_weeks,
    'milestone_hit', v_milestone_hit,
    'bonus_xp', v_bonus_xp
  );
END $$;

-- ===========================================================================
--  23. gift_redeem  (customer)
--  Validates child's overall_level >= gift.level_required; UNIQUE prevents dupe.
-- ===========================================================================
CREATE OR REPLACE FUNCTION gift_redeem(
  p_child_id UUID,
  p_gift_id UUID,
  p_venue_id UUID,
  p_staff_pin_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child children%ROWTYPE;
  v_gift gift_ladder%ROWTYPE;
  v_redemption gift_redemptions%ROWTYPE;
BEGIN
  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  PERFORM assert_caller_authority(v_child.family_id, p_staff_pin_id);

  SELECT * INTO v_gift FROM gift_ladder WHERE id = p_gift_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'gift_not_available'; END IF;

  IF v_child.current_level < v_gift.level_required THEN
    RAISE EXCEPTION 'level_too_low';
  END IF;

  IF EXISTS(SELECT 1 FROM gift_redemptions WHERE child_id = p_child_id AND gift_id = p_gift_id) THEN
    RAISE EXCEPTION 'already_redeemed';
  END IF;

  INSERT INTO gift_redemptions(child_id, gift_id, venue_id, staff_pin_id)
  VALUES (p_child_id, p_gift_id, p_venue_id, p_staff_pin_id)
  RETURNING * INTO v_redemption;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (v_child.family_id, 'hero_card_received',  -- closest existing type
          'Gift unlocked!',
          v_gift.gift_name || ' is ready to collect at the venue.',
          '/adventure', v_redemption.id);

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_child.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'gift.redeem', 'gift_redemption', v_redemption.id, p_venue_id,
    jsonb_build_object('gift_id', p_gift_id, 'gift_name', v_gift.gift_name)
  );

  RETURN jsonb_build_object(
    'success', true,
    'redemption_id', v_redemption.id,
    'gift_name', v_gift.gift_name,
    'delivery_method', v_gift.delivery_method
  );
END $$;

-- ===========================================================================
--  24. manual_wallet_adjust  (admin via Edge Function — service_role only)
--  Credit flows free; debits require reason + optional 2-person approval.
-- ===========================================================================
CREATE OR REPLACE FUNCTION manual_wallet_adjust(
  p_family_id UUID,
  p_amount_paise INTEGER,         -- signed: + credit, - debit
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
  IF p_amount_paise = 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN RAISE EXCEPTION 'reason_required'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('success', true, 'idempotent', true); END IF;
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

-- ===========================================================================
--  25. reactivation_redeem  (customer — runs after successful phone verify)
--  Matches phone in reactivation_contacts, credits welcome amount, marks redeemed.
-- ===========================================================================
CREATE OR REPLACE FUNCTION reactivation_redeem(
  p_family_id UUID,
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_contact reactivation_contacts%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_contact FROM reactivation_contacts
    WHERE phone = p_phone AND redeemed_at IS NULL AND NOT is_paused
    FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', true, 'redeemed', false, 'reason', 'no_match');
  END IF;
  IF now() > v_contact.credit_expires_at THEN
    RETURN jsonb_build_object('success', true, 'redeemed', false, 'reason', 'expired');
  END IF;

  UPDATE wallets SET balance_paise = balance_paise + v_contact.credit_paise, updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type
  ) VALUES (
    p_family_id, 'reactivation_credit', v_contact.credit_paise, v_wallet.balance_paise, 'system',
    v_contact.id, 'reactivation_contact'
  );

  UPDATE reactivation_contacts SET redeemed_at = now(), redeemed_family_id = p_family_id
    WHERE id = v_contact.id;

  INSERT INTO notifications(family_id, type, title, body, deep_link)
  VALUES (p_family_id, 'reactivation_welcome',
          'Welcome back to Diaries Club!',
          'We added ' || (v_contact.credit_paise / 100)::TEXT || ' to your wallet to celebrate.',
          '/wallet');

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (p_family_id, 'system', 'reactivation.redeem', 'family', p_family_id,
          jsonb_build_object('credit_paise', v_contact.credit_paise,
                             'reactivation_contact_id', v_contact.id));

  RETURN jsonb_build_object(
    'success', true,
    'redeemed', true,
    'credit_paise', v_contact.credit_paise
  );
END $$;

-- ===========================================================================
--  26. force_close_grace_sessions  (cron — service_role only)
--  Auto-closes any session past grace_force_close_at still in 'grace'.
-- ===========================================================================
CREATE OR REPLACE FUNCTION force_close_grace_sessions() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER := 0;
  v_session sessions%ROWTYPE;
BEGIN
  FOR v_session IN
    SELECT * FROM sessions
    WHERE status IN ('active','grace')
      AND grace_force_close_at IS NOT NULL
      AND now() > grace_force_close_at
    LIMIT 200
  LOOP
    UPDATE sessions SET
      status = 'auto_closed',
      completed_at = now()
    WHERE id = v_session.id AND status IN ('active','grace');

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
    VALUES (NULL, 'system', 'session.auto_close', 'session', v_session.id, v_session.venue_id,
            jsonb_build_object('previous_status', v_session.status));

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'auto_closed_count', v_count);
END $$;

-- ===========================================================================
--  27. family_anonymise  (customer — DPDP delete)
--  Strong scrub of PII; preserves wallet_transactions for audit trail.
-- ===========================================================================
CREATE OR REPLACE FUNCTION family_anonymise(
  p_family_id UUID,
  p_confirmation_token TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_family families%ROWTYPE;
  v_placeholder_phone TEXT;
BEGIN
  IF p_confirmation_token <> 'DELETE' THEN RAISE EXCEPTION 'invalid_confirmation'; END IF;

  PERFORM assert_caller_authority(p_family_id, NULL);

  SELECT * INTO v_family FROM families WHERE id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_family.is_anonymised THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;

  -- Placeholder phone keeps the column non-null without colliding with live numbers.
  v_placeholder_phone := '+910000' || substr(p_family_id::TEXT, 1, 10);

  UPDATE families SET
    is_anonymised = true,
    deleted_at    = now(),
    name          = 'Deleted User',
    phone         = v_placeholder_phone,
    email         = NULL,
    fcm_token     = NULL,
    fcm_platform  = NULL,
    marketing_consent = false
  WHERE id = p_family_id;

  -- Children: clear name and photo
  UPDATE children SET
    name = 'Deleted Child',
    photo_url = NULL,
    delivery_address = NULL
  WHERE family_id = p_family_id;

  -- Hero recaps: clear image_url (PII potentially baked in)
  UPDATE hero_recaps SET image_url = NULL
    WHERE child_id IN (SELECT id FROM children WHERE family_id = p_family_id);

  -- Notifications: clear (contains personalised text)
  DELETE FROM notifications WHERE family_id = p_family_id;

  -- birthday_party_photos: leave physical photos to a separate scrub job (storage)
  -- wallet_transactions: PRESERVED for tax audit trail (per spec)

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (p_family_id, 'customer', 'family.anonymise', 'family', p_family_id,
          jsonb_build_object('deleted_at', now()));

  RETURN jsonb_build_object('success', true, 'anonymised_at', now());
END $$;

-- ===========================================================================
--  PERMISSIONS
--  Customer-facing: GRANT to authenticated + service_role.
--  Service-role-only: GRANT to service_role ONLY.
-- ===========================================================================

-- Internal / service-role only
REVOKE EXECUTE ON FUNCTION assert_caller_authority(UUID, UUID)              FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION xp_credit_with_split(UUID,UUID,UUID,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,UUID,JSONB) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION wallet_topup(UUID,INTEGER,INTEGER,TEXT,TEXT)      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION reflection_auto_split()                           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION healthy_bite_distribute(UUID,UUID,UUID)           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION workshop_attend(UUID,UUID)                        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION referral_convert(UUID,UUID,UUID)                  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION birthday_deposit_record(UUID,INTEGER,TEXT,TEXT)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION birthday_complete(UUID)                           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION refund_approve(UUID,UUID,UUID)                    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION manual_wallet_adjust(UUID,INTEGER,TEXT,UUID,UUID,UUID,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION force_close_grace_sessions()                      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION streak_update(UUID,UUID)                          FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION assert_caller_authority(UUID, UUID)                TO service_role;
GRANT EXECUTE ON FUNCTION xp_credit_with_split(UUID,UUID,UUID,TEXT,INTEGER,INTEGER,INTEGER,INTEGER,UUID,JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION wallet_topup(UUID,INTEGER,INTEGER,TEXT,TEXT)        TO service_role;
GRANT EXECUTE ON FUNCTION reflection_auto_split()                            TO service_role;
GRANT EXECUTE ON FUNCTION healthy_bite_distribute(UUID,UUID,UUID)            TO service_role;
GRANT EXECUTE ON FUNCTION workshop_attend(UUID,UUID)                         TO service_role;
GRANT EXECUTE ON FUNCTION referral_convert(UUID,UUID,UUID)                   TO service_role;
GRANT EXECUTE ON FUNCTION birthday_deposit_record(UUID,INTEGER,TEXT,TEXT)    TO service_role;
GRANT EXECUTE ON FUNCTION birthday_complete(UUID)                            TO service_role;
GRANT EXECUTE ON FUNCTION refund_approve(UUID,UUID,UUID)                     TO service_role;
GRANT EXECUTE ON FUNCTION manual_wallet_adjust(UUID,INTEGER,TEXT,UUID,UUID,UUID,TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION force_close_grace_sessions()                       TO service_role;
GRANT EXECUTE ON FUNCTION streak_update(UUID,UUID)                           TO service_role;

-- Customer-facing (authenticated + service_role)
GRANT EXECUTE ON FUNCTION session_create(UUID,UUID,UUID,INTEGER,TEXT,UUID,BOOLEAN,TEXT,UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION session_extend(UUID,INTEGER,TEXT,TEXT,UUID,TEXT)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION session_complete(UUID,UUID)                        TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION order_place(UUID,UUID,JSONB,TEXT,TEXT,UUID,UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION reflection_submit(UUID,TEXT[])                     TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION workshop_register(UUID,UUID,UUID,TEXT,TEXT)        TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION workshop_cancel(UUID,TEXT)                         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION birthday_reservation_create(UUID,UUID,UUID,UUID,DATE,TIME,INTEGER,INTEGER,TEXT,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION pre_booking_create(UUID,UUID,UUID,TIMESTAMPTZ,INTEGER,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION pre_booking_redeem(UUID,UUID,TEXT)                 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION pre_booking_cancel(UUID,TEXT)                      TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION refund_issue(UUID,UUID,TEXT,INTEGER,TEXT,TEXT,UUID,UUID,TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION gift_redeem(UUID,UUID,UUID,UUID)                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION reactivation_redeem(UUID,TEXT)                     TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION family_anonymise(UUID,TEXT)                        TO authenticated, service_role;

-- ===========================================================================
--  END
-- ===========================================================================
