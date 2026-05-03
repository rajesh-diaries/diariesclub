# Session 2 — RPC Functions

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisite:** Session 1 (database schema) must be complete.

---

## Session Header

```
I am building Diaries Club. The Supabase schema from Session 1 is already live.
This session: implement every Postgres RPC function.

Estimated time: 3–4 hours
What to build: All RPC functions listed below — each as a CREATE OR REPLACE FUNCTION,
  in a single migration file `supabase/migrations/0002_rpc_functions.sql`.

What NOT to build: Edge Functions (next session block), Flutter code.

Critical rules — apply to EVERY RPC:
  1. SECURITY DEFINER, LANGUAGE plpgsql.
  2. Accept p_idempotency_key TEXT (nullable). On replay, return success without
     re-executing.
  3. All money operations are atomic — succeed completely or fail completely.
  4. Never trust client-supplied prices. For order_place, look up menu_items.price_paise.
  5. RAISE EXCEPTION 'error_code' for failures. Standard codes are listed at the end.
  6. Always write an audit_log row for state-changing operations.
  7. Return JSONB.
  8. Use SELECT ... FOR UPDATE on rows that need locking against concurrent writes.

Output expected:
  - Single SQL file with all RPCs.
  - File is idempotent (CREATE OR REPLACE FUNCTION).
  - GRANT EXECUTE TO authenticated, service_role at the bottom.

Acceptance:
  - Each RPC has a positive test (happy path) and a negative test (error path)
    documented as comments at the top.
  - Idempotency replay returns the original result, never executes twice.
```

---

## 1. `wallet_topup` — Razorpay webhook success

```sql
-- Tests:
--   ✓ Credits balance + bonus correctly
--   ✓ Replay with same idempotency_key returns same result, no double credit
--   ✓ Auto-creates wallet if missing (defensive)
--   ✗ Raises if amount_paise <= 0
CREATE OR REPLACE FUNCTION wallet_topup(
  p_family_id UUID,
  p_amount_paise INTEGER,
  p_bonus_paise INTEGER DEFAULT 0,
  p_razorpay_payment_id TEXT DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_wallet wallets%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
BEGIN
  IF p_amount_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  -- Idempotency
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

  -- Lock + credit
  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;

  UPDATE wallets SET
    balance_paise = balance_paise + p_amount_paise + p_bonus_paise,
    updated_at = now()
  WHERE family_id = p_family_id
  RETURNING * INTO v_wallet;

  -- Topup ledger row
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise,
    payment_method, razorpay_payment_id, idempotency_key
  ) VALUES (
    p_family_id, 'topup', p_amount_paise,
    v_wallet.balance_paise - p_bonus_paise,    -- balance after the topup, before bonus row
    'razorpay', p_razorpay_payment_id, p_idempotency_key
  );

  -- Bonus row (if any)
  IF p_bonus_paise > 0 THEN
    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise, payment_method
    ) VALUES (
      p_family_id, 'bonus', p_bonus_paise, v_wallet.balance_paise, 'system'
    );
  END IF;

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (NULL, 'system', 'wallet.topup', 'family', p_family_id,
          jsonb_build_object('amount', p_amount_paise, 'bonus', p_bonus_paise));

  RETURN jsonb_build_object(
    'success', true,
    'new_balance_paise', v_wallet.balance_paise,
    'amount_credited', p_amount_paise + p_bonus_paise
  );
END $$;
```

---

## 2. `session_create` — Play session + wallet debit

```sql
-- Tests:
--   ✓ Wallet payment debits, creates session, returns session_id and expires_at
--   ✓ Cash payment creates session without debiting
--   ✓ Idempotent replay returns same session_id
--   ✗ Raises 'insufficient_balance' if wallet too low
--   ✗ Raises if duration not in (60, 120)
CREATE OR REPLACE FUNCTION session_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,           -- 'wallet' | 'cash'
  p_staff_pin_id UUID DEFAULT NULL,
  p_is_guest BOOLEAN DEFAULT false,
  p_guest_phone TEXT DEFAULT NULL,
  p_pre_booking_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_amount INTEGER;
  v_existing sessions%ROWTYPE;
BEGIN
  IF p_duration_minutes NOT IN (60, 120) THEN
    RAISE EXCEPTION 'invalid_duration';
  END IF;
  IF p_payment_method NOT IN ('wallet','cash') THEN
    RAISE EXCEPTION 'invalid_payment_method';
  END IF;

  -- Idempotency: stored on sessions row
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM sessions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'idempotent', true,
        'session_id', v_existing.id,
        'expires_at', v_existing.expires_at
      );
    END IF;
  END IF;

  -- Server-side price lookup
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_amount := CASE WHEN p_duration_minutes = 60
                   THEN v_config.price_1hr_paise
                   ELSE v_config.price_2hr_paise END;

  -- Debit (if wallet)
  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_amount THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_amount,
      updated_at = now()
    WHERE family_id = p_family_id
    RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_type, idempotency_key
    ) VALUES (
      p_family_id, 'session_debit', -v_amount, v_wallet.balance_paise,
      'wallet', 'session', p_idempotency_key
    );
  END IF;

  -- Create session
  INSERT INTO sessions(
    venue_id, family_id, child_id, staff_pin_id,
    duration_minutes, amount_paise, payment_method,
    expires_at, grace_force_close_at,
    is_guest, guest_phone, pre_booking_id, idempotency_key,
    reflection_deadline
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_staff_pin_id,
    p_duration_minutes, v_amount, p_payment_method,
    now() + (p_duration_minutes || ' minutes')::INTERVAL,
    now() + ((p_duration_minutes + v_config.grace_max_minutes) || ' minutes')::INTERVAL,
    p_is_guest, p_guest_phone, p_pre_booking_id, p_idempotency_key,
    -- reflection_deadline is set on completion; default null until then
    NULL
  ) RETURNING * INTO v_session;

  -- If this came from a pre-booking, mark redeemed
  IF p_pre_booking_id IS NOT NULL THEN
    UPDATE session_pre_bookings SET
      status = 'redeemed', redeemed_session_id = v_session.id
    WHERE id = p_pre_booking_id AND status = 'reserved';
  END IF;

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, CASE WHEN p_staff_pin_id IS NULL THEN 'customer' ELSE 'staff' END,
          'session.create', 'session', v_session.id, p_venue_id,
          jsonb_build_object('child_id', p_child_id, 'duration', p_duration_minutes,
                             'amount', v_amount, 'payment_method', p_payment_method));

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session.id,
    'expires_at', v_session.expires_at,
    'grace_force_close_at', v_session.grace_force_close_at,
    'amount_paise', v_amount
  );
END $$;
```

---

## 3. `session_extend` — wallet debit + extend `expires_at`

```sql
-- Tests:
--   ✓ Extends active session, debits wallet
--   ✓ Extends grace session (parent rushed back to extend)
--   ✗ 'session_not_active' on completed/void session
--   ✗ 'insufficient_balance'
CREATE OR REPLACE FUNCTION session_extend(
  p_session_id UUID,
  p_duration_minutes INTEGER,
  p_payment_method TEXT,
  p_initiated_by TEXT DEFAULT 'parent', -- 'parent' or 'staff_on_behalf'
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_amount INTEGER;
  v_new_expires TIMESTAMPTZ;
  v_existing session_extensions%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM session_extensions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true,
                                'new_expires_at', v_existing.new_expires_at);
    END IF;
  END IF;

  -- Lock the session row to prevent concurrent extends
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.status NOT IN ('active','grace') THEN
    RAISE EXCEPTION 'session_not_active';
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_session.venue_id;
  v_amount := v_config.price_extension_paise * (p_duration_minutes / 60);

  -- Debit
  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = v_session.family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_amount THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

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

  -- Compute new expiry: extend from whichever is later (now() vs current expires_at)
  v_new_expires := GREATEST(v_session.expires_at, now()) + (p_duration_minutes || ' minutes')::INTERVAL;

  UPDATE sessions SET
    expires_at = v_new_expires,
    grace_force_close_at = v_new_expires + (v_config.grace_max_minutes || ' minutes')::INTERVAL,
    status = 'active',
    grace_started_at = NULL
  WHERE id = p_session_id;

  INSERT INTO session_extensions(
    session_id, duration_minutes, amount_paise, payment_method, new_expires_at,
    staff_pin_id, initiated_by, idempotency_key
  ) VALUES (
    p_session_id, p_duration_minutes, v_amount, p_payment_method, v_new_expires,
    p_staff_pin_id, p_initiated_by, p_idempotency_key
  );

  -- If staff acted on behalf, push a confirmation notification to the parent
  IF p_initiated_by = 'staff_on_behalf' THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_session.family_id, 'extend_nudge',
      'Session extended',
      'Staff has extended the session for ' || p_duration_minutes || ' more minutes.',
      '/home', p_session_id
    );
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (
    COALESCE(p_staff_pin_id, v_session.family_id),
    CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
    'session.extend', 'session', p_session_id, v_session.venue_id,
    jsonb_build_object('duration', p_duration_minutes, 'amount', v_amount,
                       'initiated_by', p_initiated_by)
  );

  RETURN jsonb_build_object(
    'success', true,
    'new_expires_at', v_new_expires,
    'amount_paise', v_amount
  );
END $$;
```

---

## 4. `order_place` — server-validated prices, GST, combos, coins

```sql
-- Tests:
--   ✓ Wallet order: debits, computes GST server-side, awards coins (7%)
--   ✓ Cash order: no wallet impact, no coins
--   ✓ Combo order: applies combo price, ignores item-level prices
--   ✓ Idempotent replay returns original order_id
--   ✗ 'insufficient_balance', 'menu_item_unavailable', 'invalid_combo'
CREATE OR REPLACE FUNCTION order_place(
  p_venue_id UUID,
  p_family_id UUID,
  p_items JSONB,                     -- [{"menu_item_id": uuid, "quantity": int}]
  p_combo_id UUID DEFAULT NULL,
  p_fulfillment_mode TEXT,
  p_payment_method TEXT,
  p_staff_pin_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_existing orders%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_combo combos%ROWTYPE;
  v_subtotal INTEGER := 0;
  v_gst INTEGER := 0;
  v_combo_discount INTEGER := 0;
  v_total INTEGER;
  v_coins INTEGER := 0;
  v_item JSONB;
  v_menu_item menu_items%ROWTYPE;
  v_qty INTEGER;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM orders WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true,
                                'order_id', v_existing.id,
                                'total_paise', v_existing.total_paise);
    END IF;
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;

  -- Compute subtotal SERVER-SIDE from menu_items lookup
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
    IF NOT FOUND OR NOT v_menu_item.is_available THEN
      RAISE EXCEPTION 'menu_item_unavailable';
    END IF;
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;
    v_subtotal := v_subtotal + (v_menu_item.price_paise * v_qty);
  END LOOP;

  -- If a combo is applied, override pricing
  IF p_combo_id IS NOT NULL THEN
    SELECT * INTO v_combo FROM combos WHERE id = p_combo_id AND venue_id = p_venue_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'invalid_combo'; END IF;
    v_combo_discount := GREATEST(v_subtotal - v_combo.price_paise, 0);
    v_subtotal := v_combo.price_paise;
  END IF;

  -- GST 5% on the (possibly combo-replaced) subtotal
  v_gst := (v_subtotal * 0.05)::INTEGER;
  v_total := v_subtotal + v_gst;

  -- Coins (7% of pre-GST subtotal, wallet only)
  IF p_payment_method = 'wallet' THEN
    v_coins := FLOOR(v_subtotal * v_config.cashback_percent / 100);
  END IF;

  -- Debit
  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_total THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;

    UPDATE wallets SET
      balance_paise = balance_paise - v_total + v_coins,
      coins_lifetime = coins_lifetime + v_coins,
      updated_at = now()
    WHERE family_id = p_family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      coins_amount, payment_method, idempotency_key
    ) VALUES (
      p_family_id, 'order_debit', -v_total + v_coins, v_wallet.balance_paise,
      v_coins, 'wallet', p_idempotency_key
    );
  END IF;

  -- Create order
  INSERT INTO orders(
    venue_id, family_id, staff_pin_id, fulfillment_mode, payment_method,
    subtotal_paise, gst_paise, combo_discount_paise, total_paise,
    coins_earned, combo_id, idempotency_key
  ) VALUES (
    p_venue_id, p_family_id, p_staff_pin_id, p_fulfillment_mode, p_payment_method,
    v_subtotal, v_gst, v_combo_discount, v_total,
    v_coins, p_combo_id, p_idempotency_key
  ) RETURNING * INTO v_order;

  -- Order items (snapshot prices)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_menu_item FROM menu_items WHERE id = (v_item->>'menu_item_id')::UUID;
    INSERT INTO order_items(
      order_id, menu_item_id, brand, name_snapshot, quantity, unit_price_paise
    ) VALUES (
      v_order.id, v_menu_item.id,
      (SELECT brand FROM menus WHERE id = v_menu_item.menu_id),
      v_menu_item.name,
      (v_item->>'quantity')::INTEGER,
      v_menu_item.price_paise
    );
  END LOOP;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (COALESCE(p_staff_pin_id, p_family_id),
          CASE WHEN p_staff_pin_id IS NOT NULL THEN 'staff' ELSE 'customer' END,
          'order.place', 'order', v_order.id, p_venue_id,
          jsonb_build_object('total', v_total, 'subtotal', v_subtotal, 'coins', v_coins));

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order.id,
    'subtotal_paise', v_subtotal,
    'gst_paise', v_gst,
    'total_paise', v_total,
    'coins_earned', v_coins
  );
END $$;
```

---

## 5. `xp_credit_with_split` — per-trait XP allocation (NEW for v1.5)

The big change from v1.4. Reflection produces an explicit per-trait split; auto-split divides equally.

```sql
-- Tests:
--   ✓ Reflected split: applies xp_rafi/ellie/gerry/zena, recomputes stages, recomputes overall level
--   ✓ Auto-split: equal quarters, marks reflection_status = 'auto_split'
--   ✓ Stage transition triggers notification (stage_transition_revealed)
--   ✓ Overall level cap at 20 reachable (was off-by-one in v1.4)
CREATE OR REPLACE FUNCTION xp_credit_with_split(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_event_type TEXT,                         -- 'reflection_split' | 'auto_split' | 'workshop' | etc.
  p_xp_rafi  INTEGER DEFAULT 0,
  p_xp_ellie INTEGER DEFAULT 0,
  p_xp_gerry INTEGER DEFAULT 0,
  p_xp_zena  INTEGER DEFAULT 0,
  p_reference_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_overall_thresholds JSONB;
  v_trait_thresholds JSONB;
  v_new_total INTEGER;
  v_new_level INTEGER := 1;
  v_new_overall_stage TEXT;
  v_old_stages JSONB;
  v_new_stages JSONB := '{}'::JSONB;
  v_transitions JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_trait_xp INTEGER;
  i INTEGER;
BEGIN
  SELECT * INTO v_child FROM children WHERE id = p_child_id FOR UPDATE;
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds := v_config.trait_stage_thresholds;

  v_old_stages := jsonb_build_object(
    'rafi', v_child.stage_rafi, 'ellie', v_child.stage_ellie,
    'gerry', v_child.stage_gerry, 'zena', v_child.stage_zena
  );

  -- Apply per-trait XP
  UPDATE children SET
    xp_rafi  = xp_rafi  + p_xp_rafi,
    xp_ellie = xp_ellie + p_xp_ellie,
    xp_gerry = xp_gerry + p_xp_gerry,
    xp_zena  = xp_zena  + p_xp_zena
  WHERE id = p_child_id RETURNING * INTO v_child;

  -- Recompute per-trait stages
  -- trait_stage_thresholds is e.g. [0, 50, 150, 350, 700]
  -- Stage = first index where xp >= threshold (Seedling=0, Explorer=1, Adventurer=2, Champion=3, Legend=4)
  FOR v_trait IN SELECT unnest(ARRAY['rafi','ellie','gerry','zena']) LOOP
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
          WHEN 0 THEN 'seedling' WHEN 1 THEN 'explorer'
          WHEN 2 THEN 'adventurer' WHEN 3 THEN 'champion'
          WHEN 4 THEN 'legend' ELSE 'legend'
        END;
      END IF;
    END LOOP;

    v_new_stages := v_new_stages || jsonb_build_object(v_trait, v_new_stage);
    v_old_stage := v_old_stages->>v_trait;

    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage);
    END IF;
  END LOOP;

  -- Persist new per-trait stages
  UPDATE children SET
    stage_rafi  = v_new_stages->>'rafi',
    stage_ellie = v_new_stages->>'ellie',
    stage_gerry = v_new_stages->>'gerry',
    stage_zena  = v_new_stages->>'zena'
  WHERE id = p_child_id;

  -- Overall level: sum of all trait XP, mapped to level_thresholds
  v_new_total := v_child.xp_rafi + v_child.xp_ellie + v_child.xp_gerry + v_child.xp_zena;
  v_new_level := 1;
  -- FIX: loop now reaches the final threshold (off-by-one fix from v1.4)
  FOR i IN 0..(jsonb_array_length(v_overall_thresholds) - 1) LOOP
    IF v_new_total >= (v_overall_thresholds->>i)::INTEGER THEN
      v_new_level := i + 1;  -- levels are 1-based
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
    total_xp = v_new_total,
    current_level = v_new_level,
    current_overall_stage = v_new_overall_stage
  WHERE id = p_child_id;

  -- Log XP event
  INSERT INTO xp_events(
    child_id, family_id, venue_id, event_type,
    xp_rafi, xp_ellie, xp_gerry, xp_zena,
    reference_id, metadata
  ) VALUES (
    p_child_id, p_family_id, p_venue_id, p_event_type,
    p_xp_rafi, p_xp_ellie, p_xp_gerry, p_xp_zena,
    p_reference_id, p_metadata
  );

  -- Notification on each stage transition (revealed at venue if event came from a session)
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
```

### `reflection_submit` — parent's tap-the-moments output

```sql
-- Tests:
--   ✓ Computes per-trait split from moment_tags, calls xp_credit_with_split
--   ✓ Marks recap reflection_status = 'reflected'
--   ✗ 'reflection_window_expired' if past deadline
CREATE OR REPLACE FUNCTION reflection_submit(
  p_session_id UUID,
  p_moment_tags TEXT[]
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_recap hero_recaps%ROWTYPE;
  v_total_pool INTEGER;
  v_weights JSONB := '{"rafi":0,"ellie":0,"gerry":0,"zena":0}'::JSONB;
  v_total_weight DECIMAL := 0;
  v_tag TEXT;
  v_moment reflection_moments%ROWTYPE;
  v_xp_rafi INTEGER := 0;
  v_xp_ellie INTEGER := 0;
  v_xp_gerry INTEGER := 0;
  v_xp_zena INTEGER := 0;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
  SELECT * INTO v_recap FROM hero_recaps WHERE session_id = p_session_id FOR UPDATE;

  IF v_recap.reflection_status <> 'pending' THEN
    RAISE EXCEPTION 'reflection_already_done';
  END IF;
  IF now() > v_recap.reflection_deadline THEN
    RAISE EXCEPTION 'reflection_window_expired';
  END IF;

  v_total_pool := v_recap.total_xp_pool;

  -- Sum trait weights from tapped moments
  FOREACH v_tag IN ARRAY p_moment_tags LOOP
    SELECT * INTO v_moment FROM reflection_moments WHERE tag = v_tag AND is_active;
    IF FOUND THEN
      v_weights := jsonb_set(
        v_weights,
        ARRAY[v_moment.primary_trait],
        to_jsonb((v_weights->>v_moment.primary_trait)::DECIMAL + v_moment.xp_weight)
      );
      v_total_weight := v_total_weight + v_moment.xp_weight;
    END IF;
  END LOOP;

  -- If parent tapped nothing, treat as auto-split
  IF v_total_weight = 0 THEN
    v_xp_rafi  := v_total_pool / 4;
    v_xp_ellie := v_total_pool / 4;
    v_xp_gerry := v_total_pool / 4;
    v_xp_zena  := v_total_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry); -- remainder
  ELSE
    v_xp_rafi  := FLOOR(v_total_pool * (v_weights->>'rafi')::DECIMAL  / v_total_weight);
    v_xp_ellie := FLOOR(v_total_pool * (v_weights->>'ellie')::DECIMAL / v_total_weight);
    v_xp_gerry := FLOOR(v_total_pool * (v_weights->>'gerry')::DECIMAL / v_total_weight);
    v_xp_zena  := v_total_pool - (v_xp_rafi + v_xp_ellie + v_xp_gerry);
  END IF;

  -- Apply via xp_credit_with_split
  PERFORM xp_credit_with_split(
    v_session.child_id, v_session.family_id, v_session.venue_id,
    'reflection_split',
    v_xp_rafi, v_xp_ellie, v_xp_gerry, v_xp_zena,
    p_session_id,
    jsonb_build_object('moment_tags', p_moment_tags)
  );

  UPDATE hero_recaps SET
    reflection_status = 'reflected',
    reflection_at = now(),
    moment_tags = p_moment_tags
  WHERE session_id = p_session_id;

  UPDATE sessions SET reflection_status = 'reflected' WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'split', jsonb_build_object('rafi', v_xp_rafi, 'ellie', v_xp_ellie, 'gerry', v_xp_gerry, 'zena', v_xp_zena)
  );
END $$;
```

### `reflection_auto_split` — called by cron 24h after session close

```sql
CREATE OR REPLACE FUNCTION reflection_auto_split() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
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
    LIMIT 100  -- batch
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
      'You didn''t reflect on the session, so we split XP equally.',
      '/adventure', v_recap.session_id
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'auto_split_count', v_count);
END $$;
```

---

## 6. `healthy_bite_distribute` — random card draw (no provably-fair claim)

```sql
-- Tests:
--   ✓ ~10% rare draws over 1000 simulated calls
--   ✓ Falls back gracefully if all rare cards collected
CREATE OR REPLACE FUNCTION healthy_bite_distribute(
  p_session_id UUID,
  p_child_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_is_rare BOOLEAN;
BEGIN
  UPDATE sessions SET healthy_bite_distributed = true WHERE id = p_session_id;

  v_is_rare := random() <= 0.10;  -- honest 10%

  -- Try a card of the chosen rarity that the child doesn't have
  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare AND is_birthday_exclusive = false AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  -- Fallback: any non-collected
  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  -- All collected? Give a "duplicate" — track separately if needed
  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'card_id', v_card.id,
    'card_name', v_card.name,
    'is_rare', v_card.is_rare,
    'image_url', v_card.image_url
  );
END $$;
```

---

## 7. `workshop_register` — atomic spot decrement (race fix)

```sql
-- Tests:
--   ✓ Two concurrent registrations: one succeeds, one gets 'workshop_full'
--   ✓ Wallet payment debits, registration created
CREATE OR REPLACE FUNCTION workshop_register(
  p_workshop_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_payment_method TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_wshop workshops%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_existing workshop_registrations%ROWTYPE;
  v_reg workshop_registrations%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM workshop_registrations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'registration_id', v_existing.id);
    END IF;
  END IF;

  -- ATOMIC decrement using WHERE clause guard
  UPDATE workshops SET spots_remaining = spots_remaining - 1
    WHERE id = p_workshop_id AND spots_remaining > 0 AND status = 'upcoming'
    RETURNING * INTO v_wshop;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'workshop_full';
  END IF;

  -- Debit (wallet path)
  IF p_payment_method = 'wallet' THEN
    SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
    IF v_wallet.balance_paise < v_wshop.price_paise THEN
      -- Rollback the decrement
      UPDATE workshops SET spots_remaining = spots_remaining + 1 WHERE id = p_workshop_id;
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

  RETURN jsonb_build_object('success', true, 'registration_id', v_reg.id);
END $$;
```

### `workshop_cancel` — restore spot, refund wallet

```sql
CREATE OR REPLACE FUNCTION workshop_cancel(
  p_registration_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_reg workshop_registrations%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  SELECT * INTO v_reg FROM workshop_registrations WHERE id = p_registration_id FOR UPDATE;
  IF v_reg.cancelled_at IS NOT NULL THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

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

  RETURN jsonb_build_object('success', true);
END $$;
```

---

## 8. `referral_convert` — calendar-month cap, Brave Boost on first

```sql
-- Tests:
--   ✓ First referral grants Brave Boost (+200 XP to Rafi)
--   ✓ Subsequent referrals grant wallet credit + standard XP (no extra Brave Boost)
--   ✗ 'monthly_cap_exceeded' on the gifter's 6th conversion that month
CREATE OR REPLACE FUNCTION referral_convert(
  p_referrer_family_id UUID,
  p_new_family_id UUID,
  p_triggering_session_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_config venue_config%ROWTYPE;
  v_venue_id UUID;
  v_count INTEGER;
  v_month_start DATE;
  v_is_first BOOLEAN;
  v_referrer_wallet wallets%ROWTYPE;
  v_new_wallet wallets%ROWTYPE;
  v_first_child UUID;
BEGIN
  SELECT venue_id INTO v_venue_id FROM sessions WHERE id = p_triggering_session_id;
  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_venue_id;

  v_month_start := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::DATE;

  -- Count gifter's conversions this calendar month
  SELECT COUNT(*) INTO v_count FROM referral_conversions
    WHERE referrer_family_id = p_referrer_family_id
      AND conversion_month = v_month_start;
  IF v_count >= v_config.referral_monthly_cap THEN
    RAISE EXCEPTION 'monthly_cap_exceeded';
  END IF;

  -- Is this the gifter's very first ever conversion?
  SELECT NOT EXISTS(SELECT 1 FROM referral_conversions WHERE referrer_family_id = p_referrer_family_id)
    INTO v_is_first;

  -- Credit gifter wallet
  UPDATE wallets SET balance_paise = balance_paise + v_config.referral_gifter_credit_paise, updated_at = now()
    WHERE family_id = p_referrer_family_id RETURNING * INTO v_referrer_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
    VALUES (p_referrer_family_id, 'bonus', v_config.referral_gifter_credit_paise, v_referrer_wallet.balance_paise, 'system');

  -- Credit new family wallet
  UPDATE wallets SET balance_paise = balance_paise + v_config.referral_new_family_credit_paise, updated_at = now()
    WHERE family_id = p_new_family_id RETURNING * INTO v_new_wallet;
  INSERT INTO wallet_transactions(family_id, type, amount_paise, balance_after_paise, payment_method)
    VALUES (p_new_family_id, 'bonus', v_config.referral_new_family_credit_paise, v_new_wallet.balance_paise, 'system');

  -- Brave Boost on first referral — apply to gifter's first child
  IF v_is_first THEN
    SELECT id INTO v_first_child FROM children WHERE family_id = p_referrer_family_id ORDER BY created_at LIMIT 1;
    IF v_first_child IS NOT NULL THEN
      PERFORM xp_credit_with_split(
        v_first_child, p_referrer_family_id, v_venue_id,
        'referral_bonus',
        v_config.xp_referral_bonus_rafi, 0, 0, 0,
        NULL,
        jsonb_build_object('reason', 'first_referral_brave_boost')
      );

      INSERT INTO notifications(family_id, type, title, body, deep_link)
      VALUES (p_referrer_family_id, 'first_referral_brave_boost',
              'You unlocked a Brave Boost!',
              'Your first referral gave Rafi a +' || v_config.xp_referral_bonus_rafi || ' XP boost.',
              '/adventure');
    END IF;
  END IF;

  INSERT INTO referral_conversions(
    referrer_family_id, new_family_id, triggering_session_id, conversion_month,
    gifter_wallet_credit_paise, gifter_xp_bonus_rafi, new_family_wallet_credit_paise,
    is_first_referral
  ) VALUES (
    p_referrer_family_id, p_new_family_id, p_triggering_session_id, v_month_start,
    v_config.referral_gifter_credit_paise,
    CASE WHEN v_is_first THEN v_config.xp_referral_bonus_rafi ELSE 0 END,
    v_config.referral_new_family_credit_paise,
    v_is_first
  );

  RETURN jsonb_build_object(
    'success', true, 'is_first', v_is_first,
    'gifter_credit', v_config.referral_gifter_credit_paise,
    'new_family_credit', v_config.referral_new_family_credit_paise
  );
END $$;
```

---

## 9. `birthday_reservation_create` — hybrid in-app reserve

```sql
-- Tests:
--   ✓ Reserve a slot, status starts at 'reserved'
--   ✓ deposit_paid moves status to 'deposit_paid'
--   ✓ Slot conflict raises 'slot_unavailable'
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
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_avail birthday_availability%ROWTYPE;
  v_existing_count INTEGER;
  v_res birthday_reservations%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
  v_end_time TIME;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'reservation_id', v_existing.id);
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  v_end_time := (p_slot_start_time + (v_pkg.duration_hours || ' hours')::INTERVAL)::TIME;

  -- Slot must be in the availability table and not blocked
  SELECT * INTO v_avail FROM birthday_availability
    WHERE venue_id = p_venue_id AND slot_date = p_slot_date AND slot_start_time = p_slot_start_time;
  IF NOT FOUND OR v_avail.is_blocked THEN
    RAISE EXCEPTION 'slot_unavailable';
  END IF;

  -- No existing active reservation for this slot
  SELECT COUNT(*) INTO v_existing_count FROM birthday_reservations
    WHERE venue_id = p_venue_id
      AND slot_date = p_slot_date
      AND slot_start_time = p_slot_start_time
      AND status IN ('reserved','deposit_paid','confirmed');
  IF v_existing_count > 0 THEN
    RAISE EXCEPTION 'slot_unavailable';
  END IF;

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
    p_triggered_by, now() + INTERVAL '24 hours',
    p_idempotency_key
  ) RETURNING * INTO v_res;

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id,
    'deposit_paise', v_pkg.deposit_paise,
    'expires_at', v_res.reservation_expires_at
  );
END $$;
```

### `birthday_deposit_record` — called by Razorpay webhook

```sql
CREATE OR REPLACE FUNCTION birthday_deposit_record(
  p_reservation_id UUID,
  p_amount_paise INTEGER,
  p_razorpay_payment_id TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_existing wallet_transactions%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM wallet_transactions WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN jsonb_build_object('success', true, 'idempotent', true); END IF;
  END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF v_res.status NOT IN ('reserved') THEN
    RAISE EXCEPTION 'invalid_reservation_state';
  END IF;

  UPDATE birthday_reservations SET
    deposit_paid_paise = p_amount_paise,
    total_paid_paise = total_paid_paise + p_amount_paise,
    status = 'deposit_paid'
  WHERE id = p_reservation_id;

  -- Audit-log only; deposit doesn't go to family wallet
  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method,
    reference_id, reference_type, razorpay_payment_id, idempotency_key
  )
  SELECT v_res.family_id, 'birthday_deposit_debit', -p_amount_paise,
         (SELECT balance_paise FROM wallets WHERE family_id = v_res.family_id),
         'razorpay', p_reservation_id, 'birthday_deposit', p_razorpay_payment_id, p_idempotency_key;

  -- Notify admin (via in-app inbox + dashboard)
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_minus_90',
    'Reservation confirmed!',
    'Our team will reach out within 24 hours to finalise.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  RETURN jsonb_build_object('success', true);
END $$;
```

---

## 10. Other RPCs — patterns identical to above

These are summarised for brevity; Claude Code should implement each following the exact same patterns (idempotency check, lock, validate, mutate, audit, return JSONB):

| RPC | Operations |
|---|---|
| `pre_booking_create` | Hold partial wallet credit, insert pre_bookings row, expires_at = scheduled_start + 30min |
| `pre_booking_redeem` | Convert pre_booking → session_create, refund hold to wallet (reapplied as session_debit) |
| `pre_booking_cancel` | Refund held amount to wallet, mark cancelled |
| `refund_issue` | Validate amount ≤ ₹500 if staff-initiated; insert refund row; if approved, credit wallet |
| `refund_approve` | Admin approves pending refund; if 2-person enabled, requires second approver |
| `streak_update` | Compute IST week boundary; if last_streak_week_ist != current_monday → update streak counter, check milestones, optionally award bonus XP |
| `gift_redeem` | Validate child's overall_level >= gift.level_required; insert gift_redemption (UNIQUE prevents double); notify parent |
| `workshop_attend` | Mark attendance, call xp_credit_with_split with workshop's primary_trait, call streak_update |
| `birthday_complete` | Mark reservation completed; XP bonus to host child via xp_credit_with_split; assign birthday_hero_card; notify D+1 |
| `manual_wallet_adjust` | Admin debit/credit; debits require reason, optional 2-person approval per venue_config flag |
| `reactivation_redeem` | Match phone in reactivation_contacts → credit ₹200 → mark redeemed |
| `force_close_grace_sessions` | Cron-callable; finds sessions where now() > grace_force_close_at AND status='grace'; sets status='auto_closed', completed_at=now() |
| `family_anonymise` | Strong DPDP delete: scramble name/phone/email/photo/child names; mark deleted_at + is_anonymised; revoke all sessions; preserve wallet_transactions |

---

## 11. Standard Error Codes

These are raised across the RPCs. Flutter maps them to user messages in `lib/core/utils/errors.dart`.

| Code | Meaning | UX message |
|---|---|---|
| `insufficient_balance` | Wallet too low | "Top up your wallet to continue" |
| `invalid_amount` | ≤0 amount | "Invalid amount" |
| `invalid_duration` | Not 60/120 | (system) |
| `invalid_payment_method` | Unknown method | (system) |
| `invalid_quantity` | 0 or negative | (system) |
| `invalid_combo` | Combo not active or not in venue | "That offer isn't available" |
| `invalid_package` | Birthday package not active | (system) |
| `invalid_reservation_state` | State machine violation | (system) |
| `menu_item_unavailable` | Item not available | "That item just sold out" |
| `session_not_active` | Extend on completed session | "This session has ended" |
| `slot_unavailable` | Birthday slot taken | "That slot just got booked. Pick another?" |
| `workshop_full` | No spots left | "This workshop is now full" |
| `monthly_cap_exceeded` | Referral cap hit | "You've hit your monthly referral cap. Resets on the 1st." |
| `reflection_already_done` | Replay protection | (system) |
| `reflection_window_expired` | Past 24h | (system) |
| `already_cancelled` | Replay protection | (system) |
| `not_authorised` | Caller doesn't own resource | "You can't access that" |

---

## 12. Permissions

```sql
-- All RPCs callable by authenticated users via PostgREST
GRANT EXECUTE ON FUNCTION wallet_topup            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION session_create          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION session_extend          TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION order_place             TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION xp_credit_with_split    TO service_role;          -- internal
GRANT EXECUTE ON FUNCTION reflection_submit       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION reflection_auto_split   TO service_role;          -- cron only
GRANT EXECUTE ON FUNCTION healthy_bite_distribute TO service_role;          -- staff via Edge Function
GRANT EXECUTE ON FUNCTION workshop_register       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION workshop_cancel         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION referral_convert        TO service_role;          -- triggered by webhook
GRANT EXECUTE ON FUNCTION birthday_reservation_create TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION birthday_deposit_record TO service_role;          -- webhook only
-- ...etc for all others
```

---

## Acceptance Tests (manual, run after migration)

```sql
-- 1. Idempotency
SELECT wallet_topup('<family_uuid>', 50000, 0, 'pay_test_1', 'idem_test_1');
-- balance += 500, returns success
SELECT wallet_topup('<family_uuid>', 50000, 0, 'pay_test_1', 'idem_test_1');
-- balance UNCHANGED, returns idempotent: true

-- 2. Insufficient balance
SELECT session_create('<venue>', '<family>', '<child>', 60, 'wallet');
-- raises insufficient_balance if < ₹800

-- 3. Server-side price safety
-- Invoke order_place with hand-crafted items and notice the server ignores any client price hints

-- 4. Concurrent workshop fills
-- In two psql sessions: simultaneously call workshop_register on a 1-spot workshop
-- One succeeds, the other raises 'workshop_full'

-- 5. Reflection split + auto-split
-- Submit reflection_submit with moment_tags = ['took_a_leap','helped_a_friend']
-- Inspect children.xp_rafi vs xp_ellie; weights should sum to total_xp_pool
```
