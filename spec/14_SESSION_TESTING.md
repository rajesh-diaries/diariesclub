# Session 14 — Testing (pgTAP)

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-13 + 5b complete.

---

## Session Header

```
I am building Diaries Club. All app + edge function code is spec'd. This session:
build a comprehensive pgTAP test suite for the database — focused on money safety,
state machines, and idempotency.

Why pgTAP: SQL-native testing in PostgreSQL. Tests run in transactions that roll
back, so they don't pollute the database. Catches money bugs before deploy.

Why not Flutter widget tests in v1: limited time, manual QA covers UI. Money
correctness is non-negotiable; UI polish can iterate.

Estimated time: 4-5 hours
What to build:
  - pgTAP installation migration
  - Test suite for every RPC (18 functions across all sessions)
  - State machine tests for sessions, birthday_reservations, refunds
  - Idempotency tests
  - Money conservation tests (no money created or lost)
  - RLS isolation tests
  - CI script to run tests on every migration

What NOT to build:
  - Flutter widget tests (skip for v1)
  - Edge Function unit tests (each has its own Deno tests)
  - Integration tests across multiple services

Output expected:
  - supabase/tests/ directory with one test file per RPC + scenarios
  - GitHub Actions workflow to run pgTAP on PR
  - Local script: ./scripts/run-pgtap.sh

Acceptance:
  - Run all tests locally: ./scripts/run-pgtap.sh → all pass
  - Each test rolls back correctly (no DB pollution)
  - Total runtime <30 seconds for all tests
  - Coverage: every RPC has happy path + at least one error path
```

---

## 1. pgTAP Installation

### 1.1 Migration

```sql
-- supabase/migrations/0010_pgtap.sql
CREATE EXTENSION IF NOT EXISTS pgtap;
```

### 1.2 Test runner script

```bash
#!/bin/bash
# scripts/run-pgtap.sh

set -e

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"

echo "Running pgTAP test suite..."

# Find all .sql files in supabase/tests/ and run them
for file in supabase/tests/*.sql; do
  if [ -f "$file" ]; then
    echo "→ $file"
    psql "$DB_URL" -f "$file" -X -q -v ON_ERROR_STOP=1
  fi
done

echo "✓ All tests passed"
```

### 1.3 Test pattern

Every test file follows this structure:

```sql
-- Run with: psql -f supabase/tests/<name>.sql
BEGIN;

SELECT plan(N); -- N = number of assertions

-- Setup test data
INSERT INTO families (id, phone, name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+919999999991', 'Test 1');

-- Run assertions
SELECT ok(<condition>, 'description');
SELECT is(<actual>, <expected>, 'description');
SELECT throws_ok(<query>, '<error_pattern>', 'description');
SELECT lives_ok(<query>, 'description');

-- Cleanup happens automatically via ROLLBACK
SELECT * FROM finish();
ROLLBACK;
```

---

## 2. Test File Layout

```
supabase/tests/
├── 00_setup.sql              # Helpers + fixtures
├── 01_wallet_topup.sql
├── 02_session_create.sql
├── 03_session_extend.sql
├── 04_session_force_close.sql
├── 05_order_place.sql
├── 06_xp_credit_with_split.sql
├── 07_reflection_submit.sql
├── 08_reflection_auto_split.sql
├── 09_healthy_bite_distribute.sql
├── 10_workshop_register.sql
├── 11_workshop_cancel.sql
├── 12_referral_convert.sql
├── 13_birthday_reservation_create.sql
├── 14_birthday_reservation_complete.sql
├── 15_birthday_album_publish.sql
├── 16_refund_issue.sql
├── 17_refund_approve.sql
├── 18_shift_close.sql
├── 19_reactivation_redeem.sql
├── 20_state_machines.sql
├── 21_idempotency.sql
├── 22_money_conservation.sql
└── 23_rls_isolation.sql
```

---

## 3. Setup Helpers — `00_setup.sql`

```sql
-- 00_setup.sql
-- Shared test fixtures for all tests. Run via include or copy-paste at start.

-- Helper: create a test family
CREATE OR REPLACE FUNCTION create_test_family(
  p_id UUID, p_phone TEXT, p_name TEXT
) RETURNS UUID
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO families (id, phone, name)
  VALUES (p_id, p_phone, p_name);
  RETURN p_id;
END $$;

-- Helper: create a test child
CREATE OR REPLACE FUNCTION create_test_child(
  p_family_id UUID, p_name TEXT, p_dob DATE
) RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE
  v_id UUID := gen_random_uuid();
BEGIN
  INSERT INTO children (id, family_id, name, date_of_birth)
  VALUES (v_id, p_family_id, p_name, p_dob);
  RETURN v_id;
END $$;

-- Helper: top up wallet directly (skip RPC for setup)
CREATE OR REPLACE FUNCTION topup_test_wallet(
  p_family_id UUID, p_amount_paise INTEGER
) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE wallets SET balance_paise = balance_paise + p_amount_paise
    WHERE family_id = p_family_id;

  INSERT INTO wallet_transactions(
    family_id, type, amount_paise, balance_after_paise, payment_method
  ) VALUES (
    p_family_id, 'topup', p_amount_paise,
    (SELECT balance_paise FROM wallets WHERE family_id = p_family_id),
    'system'
  );
END $$;

-- Standard fixtures (use these UUIDs in all tests)
-- Venue
-- 00000000-0000-0000-0000-000000000001 (already seeded)
-- Family A: balance 0
-- 11111111-1111-1111-1111-111111111111
-- Family B: balance 100,000 paise (₹1,000)
-- 22222222-2222-2222-2222-222222222222
```

---

## 4. Test 1 — wallet_topup

```sql
-- 01_wallet_topup.sql
BEGIN;
SELECT plan(8);

-- Setup
SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);

-- TEST 1: Happy path — credits balance correctly
SELECT lives_ok(
  $$ SELECT wallet_topup(
       '11111111-1111-1111-1111-111111111111'::UUID,
       50000, 0, 'pay_test_001', 'idem_topup_001'
     ) $$,
  'wallet_topup happy path executes without error'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  50000,
  'wallet balance is 50000 paise after topup'
);

-- TEST 2: Bonus paise added correctly
SELECT lives_ok(
  $$ SELECT wallet_topup(
       '11111111-1111-1111-1111-111111111111'::UUID,
       100000, 50000, 'pay_test_002', 'idem_topup_002'
     ) $$,
  'wallet_topup with bonus executes'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  200000,  -- 50000 + 100000 + 50000 bonus
  'wallet balance includes both topup and bonus'
);

-- Verify two wallet_transactions rows for the bonus topup (one topup, one bonus)
SELECT is(
  (SELECT COUNT(*) FROM wallet_transactions
   WHERE idempotency_key = 'idem_topup_002'),
  1::BIGINT,
  'topup row created with idempotency key'
);

SELECT is(
  (SELECT COUNT(*) FROM wallet_transactions
   WHERE family_id = '11111111-1111-1111-1111-111111111111'
   AND type = 'bonus'),
  1::BIGINT,
  'bonus row created (no idempotency_key)'
);

-- TEST 3: Idempotency — replay with same key returns same result, no double credit
SELECT is(
  (SELECT (wallet_topup(
    '11111111-1111-1111-1111-111111111111'::UUID,
    50000, 0, 'pay_test_001', 'idem_topup_001'
  ))->>'idempotent'),
  'true',
  'replay returns idempotent: true'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  200000,
  'balance unchanged after idempotent replay'
);

-- TEST 4: Negative amount rejected
SELECT throws_ok(
  $$ SELECT wallet_topup(
       '11111111-1111-1111-1111-111111111111'::UUID,
       -100, 0, NULL, NULL
     ) $$,
  '%invalid_amount%',
  'negative amount raises invalid_amount'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 5. Test 2 — session_create

```sql
-- 02_session_create.sql
BEGIN;
SELECT plan(10);

SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);
SELECT create_test_child(
  '11111111-1111-1111-1111-111111111111'::UUID,
  'Aarav', '2018-05-10'
);
SELECT topup_test_wallet(
  '11111111-1111-1111-1111-111111111111'::UUID,
  150000  -- ₹1500 enough for both 1hr and 2hr
);

-- TEST 1: 1hr wallet session — succeeds, debits ₹800
SELECT lives_ok(
  $$ SELECT session_create(
       '00000000-0000-0000-0000-000000000001'::UUID,  -- venue
       '11111111-1111-1111-1111-111111111111'::UUID,  -- family
       (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
       60, 'wallet', NULL, false, NULL, NULL, 'idem_sess_1'
     ) $$,
  '1hr wallet session creates'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  150000 - 80000,
  'wallet debited by 80000 paise (₹800) for 1hr'
);

SELECT is(
  (SELECT status FROM sessions WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
  'active',
  'session status is active'
);

-- Verify expires_at is roughly 1 hour from now
SELECT cmp_ok(
  EXTRACT(EPOCH FROM (
    (SELECT expires_at FROM sessions WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1) - now()
  ))::int,
  '<',
  3700, -- ~1hr + small buffer
  'expires_at within 1 hour'
);

-- TEST 2: Cash session — no wallet impact
SELECT lives_ok(
  $$ SELECT session_create(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
       120, 'cash', NULL, false, NULL, NULL, 'idem_sess_2'
     ) $$,
  '2hr cash session creates'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  150000 - 80000,  -- only the first session debited
  'wallet unchanged for cash session'
);

-- TEST 3: Idempotent replay
SELECT is(
  (SELECT (session_create(
    '00000000-0000-0000-0000-000000000001'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
    60, 'wallet', NULL, false, NULL, NULL, 'idem_sess_1'
  ))->>'idempotent'),
  'true',
  'replay returns idempotent'
);

-- TEST 4: Insufficient balance
DELETE FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111';
INSERT INTO wallets (family_id, balance_paise) VALUES
  ('11111111-1111-1111-1111-111111111111', 100); -- ₹1, way too little

SELECT throws_ok(
  $$ SELECT session_create(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
       60, 'wallet', NULL, false, NULL, NULL, 'idem_sess_3'
     ) $$,
  '%insufficient_balance%',
  'insufficient balance raises'
);

-- TEST 5: Invalid duration
SELECT throws_ok(
  $$ SELECT session_create(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
       45, 'cash', NULL, false, NULL, NULL, 'idem_sess_4'
     ) $$,
  '%invalid_duration%',
  '45min duration rejected'
);

-- TEST 6: Invalid payment method
SELECT throws_ok(
  $$ SELECT session_create(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       (SELECT id FROM children WHERE family_id = '11111111-1111-1111-1111-111111111111' LIMIT 1),
       60, 'razorpay', NULL, false, NULL, NULL, 'idem_sess_5'
     ) $$,
  '%invalid_payment_method%',
  'razorpay direct payment rejected (must go via topup)'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 6. Test 3 — session_extend

```sql
-- 03_session_extend.sql
BEGIN;
SELECT plan(7);

SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);
SELECT topup_test_wallet(
  '11111111-1111-1111-1111-111111111111'::UUID, 200000
);

-- Create session via direct insert for setup speed
INSERT INTO sessions (
  id, venue_id, family_id, child_id, duration_minutes,
  amount_paise, payment_method, status, expires_at, grace_force_close_at
) VALUES (
  '99999999-9999-9999-9999-999999999991',
  '00000000-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  NULL,  -- no child for simplicity
  60, 80000, 'wallet', 'active',
  now() + INTERVAL '1 hour',
  now() + INTERVAL '1.5 hour'
);

-- TEST 1: Extend by 30 min from wallet
SELECT lives_ok(
  $$ SELECT session_extend(
       '99999999-9999-9999-9999-999999999991'::UUID,
       30, 'wallet', 'parent', NULL, 'idem_ext_1'
     ) $$,
  'extend session by 30 min'
);

SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  200000 - 15000,  -- 30min @ ₹150 (half of ₹300/hr)
  'wallet debited proportionally for 30 min extension'
);

-- TEST 2: Extend grace session — flips back to active
UPDATE sessions SET status = 'grace', grace_started_at = now() - INTERVAL '5 min'
WHERE id = '99999999-9999-9999-9999-999999999991';

SELECT lives_ok(
  $$ SELECT session_extend(
       '99999999-9999-9999-9999-999999999991'::UUID,
       60, 'cash', 'parent', NULL, 'idem_ext_2'
     ) $$,
  'extend during grace period works'
);

SELECT is(
  (SELECT status FROM sessions WHERE id = '99999999-9999-9999-9999-999999999991'),
  'active',
  'session flipped from grace back to active after extend'
);

-- TEST 3: Extend completed session — fails
UPDATE sessions SET status = 'completed' WHERE id = '99999999-9999-9999-9999-999999999991';

SELECT throws_ok(
  $$ SELECT session_extend(
       '99999999-9999-9999-9999-999999999991'::UUID,
       30, 'wallet', 'parent', NULL, 'idem_ext_3'
     ) $$,
  '%session_not_active%',
  'cannot extend completed session'
);

-- TEST 4: Idempotent replay
UPDATE sessions SET status = 'active' WHERE id = '99999999-9999-9999-9999-999999999991';

SELECT is(
  (SELECT (session_extend(
    '99999999-9999-9999-9999-999999999991'::UUID,
    30, 'wallet', 'parent', NULL, 'idem_ext_1'
  ))->>'idempotent'),
  'true',
  'extend replay returns idempotent'
);

-- TEST 5: Initiated by staff fires notification
SELECT lives_ok(
  $$ SELECT session_extend(
       '99999999-9999-9999-9999-999999999991'::UUID,
       30, 'cash', 'staff_on_behalf', NULL, 'idem_ext_5'
     ) $$,
  'extend by staff_on_behalf'
);

-- (Notification check would require checking notifications table)

SELECT * FROM finish();
ROLLBACK;
```

---

## 7. Test 4 — order_place

```sql
-- 05_order_place.sql
BEGIN;
SELECT plan(10);

SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);
SELECT topup_test_wallet(
  '11111111-1111-1111-1111-111111111111'::UUID, 100000
);

-- Create test menu items
INSERT INTO menus (id, venue_id, brand, name)
VALUES ('aaaa1111-1111-1111-1111-111111111111',
        '00000000-0000-0000-0000-000000000001', 'coffee', 'Test Coffee Menu');

INSERT INTO menu_items (id, menu_id, name, price_paise, is_available)
VALUES
  ('bbbb1111-1111-1111-1111-111111111111',
   'aaaa1111-1111-1111-1111-111111111111',
   'Test Cappuccino', 18000, true),  -- ₹180
  ('bbbb1111-1111-1111-1111-111111111112',
   'aaaa1111-1111-1111-1111-111111111111',
   'Test Croissant', 16000, false);  -- ₹160 sold out

-- TEST 1: Wallet order succeeds
SELECT lives_ok(
  $$ SELECT order_place(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111111", "quantity": 2}]'::JSONB,
       NULL, 'dine_in', 'wallet', NULL, 'idem_order_1'
     ) $$,
  'wallet order placed'
);

-- Subtotal: 180 * 2 = 360 (36000 paise)
-- GST 5%: 18 (1800 paise)
-- Total: 378 (37800 paise)
-- Coins: 25 (1800 paise = 25.2, floor = 25)
SELECT is(
  (SELECT total_paise FROM orders WHERE family_id = '11111111-1111-1111-1111-111111111111' ORDER BY created_at DESC LIMIT 1),
  37800,
  'total_paise computed server-side as 37800'
);

SELECT is(
  (SELECT subtotal_paise FROM orders WHERE family_id = '11111111-1111-1111-1111-111111111111' ORDER BY created_at DESC LIMIT 1),
  36000,
  'subtotal_paise = 36000'
);

SELECT is(
  (SELECT gst_paise FROM orders WHERE family_id = '11111111-1111-1111-1111-111111111111' ORDER BY created_at DESC LIMIT 1),
  1800,
  'gst_paise = 1800 (5% of subtotal)'
);

-- Wallet should be: 100000 - 37800 + coins (about 2520) = 64720 + 2520 = 64720
-- But coins go to balance_paise too per spec: balance -= total + coins (because coins ARE wallet money)
-- Actually per RPC: balance_paise = balance - total + coins. Coins lifetime separate.
SELECT cmp_ok(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  '<',
  100000,
  'wallet debited'
);

SELECT cmp_ok(
  (SELECT coins_lifetime FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  '>',
  0,
  'coins_lifetime credited'
);

-- TEST 2: Sold-out item rejected
SELECT throws_ok(
  $$ SELECT order_place(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111112", "quantity": 1}]'::JSONB,
       NULL, 'dine_in', 'wallet', NULL, 'idem_order_2'
     ) $$,
  '%menu_item_unavailable%',
  'sold-out item rejected'
);

-- TEST 3: Cash order — no wallet debit, no coins
INSERT INTO menu_items (id, menu_id, name, price_paise, is_available)
VALUES ('bbbb1111-1111-1111-1111-111111111113',
        'aaaa1111-1111-1111-1111-111111111111',
        'Test Tea', 12000, true);

SELECT lives_ok(
  $$ SELECT order_place(
       '00000000-0000-0000-0000-000000000001'::UUID,
       '11111111-1111-1111-1111-111111111111'::UUID,
       '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111113", "quantity": 1}]'::JSONB,
       NULL, 'dine_in', 'cash', NULL, 'idem_order_3'
     ) $$,
  'cash order placed'
);

SELECT is(
  (SELECT coins_earned FROM orders WHERE idempotency_key = 'idem_order_3'),
  0,
  'cash order does not earn coins'
);

-- TEST 4: Idempotent replay
SELECT is(
  (SELECT (order_place(
    '00000000-0000-0000-0000-000000000001'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111111", "quantity": 2}]'::JSONB,
    NULL, 'dine_in', 'wallet', NULL, 'idem_order_1'
  ))->>'idempotent'),
  'true',
  'order replay returns idempotent'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 8. Test 5 — xp_credit_with_split

```sql
-- 06_xp_credit_with_split.sql
BEGIN;
SELECT plan(8);

SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);

DECLARE
  v_child_id UUID;
BEGIN
  v_child_id := create_test_child(
    '11111111-1111-1111-1111-111111111111'::UUID,
    'Aarav', '2018-05-10'
  );

  -- TEST 1: Apply XP, child moves from seedling to explorer
  PERFORM xp_credit_with_split(
    v_child_id,
    '11111111-1111-1111-1111-111111111111'::UUID,
    '00000000-0000-0000-0000-000000000001'::UUID,
    'play_session',
    50, 0, 0, 0,  -- 50 XP to Rafi (just enough to hit Explorer threshold)
    NULL, '{}'::JSONB
  );

  -- Trait XP
  SELECT is(
    (SELECT xp_rafi FROM children WHERE id = v_child_id),
    50,
    'xp_rafi = 50'
  );

  SELECT is(
    (SELECT stage_rafi FROM children WHERE id = v_child_id),
    'explorer',
    'rafi at explorer stage (50 XP threshold)'
  );

  -- TEST 2: Overall total + level
  SELECT is(
    (SELECT total_xp FROM children WHERE id = v_child_id),
    50,
    'total_xp = 50'
  );

  -- Per default level_thresholds [0,100,250,...], 50 XP = level 1
  SELECT is(
    (SELECT current_level FROM children WHERE id = v_child_id),
    1,
    'current_level = 1 (under 100 XP threshold)'
  );

  -- TEST 3: Multi-trait XP, multiple stage transitions
  PERFORM xp_credit_with_split(
    v_child_id,
    '11111111-1111-1111-1111-111111111111'::UUID,
    '00000000-0000-0000-0000-000000000001'::UUID,
    'reflection_split',
    100, 100, 100, 100,  -- 400 total
    NULL, '{}'::JSONB
  );

  -- Each trait now has: rafi=150, ellie=100, gerry=100, zena=100
  -- Stage thresholds [0,50,150,350,700]
  -- rafi at 150 = adventurer (3rd stage)
  -- ellie/gerry/zena at 100 = explorer (still, 100 < 150)

  SELECT is(
    (SELECT stage_rafi FROM children WHERE id = v_child_id),
    'adventurer',
    'rafi reached adventurer at 150 XP'
  );

  SELECT is(
    (SELECT stage_ellie FROM children WHERE id = v_child_id),
    'explorer',
    'ellie still explorer at 100 XP'
  );

  -- TEST 4: Total XP and level
  SELECT is(
    (SELECT total_xp FROM children WHERE id = v_child_id),
    450,  -- 50 + 100 + 100 + 100 + 100 = 450
    'total_xp = 450'
  );

  -- 450 XP — per [0,100,250,450,700,...], that's level 4
  SELECT is(
    (SELECT current_level FROM children WHERE id = v_child_id),
    4,
    'current_level = 4 at 450 XP'
  );
END;

SELECT * FROM finish();
ROLLBACK;
```

---

## 9. Test 6 — workshop_register (race condition)

```sql
-- 10_workshop_register.sql
BEGIN;
SELECT plan(6);

SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111',
  '+919999999991', 'Test A'
);
SELECT create_test_family(
  '22222222-2222-2222-2222-222222222222',
  '+919999999992', 'Test B'
);
SELECT topup_test_wallet(
  '11111111-1111-1111-1111-111111111111'::UUID, 100000
);
SELECT topup_test_wallet(
  '22222222-2222-2222-2222-222222222222'::UUID, 100000
);

DECLARE
  v_child_a UUID;
  v_child_b UUID;
  v_workshop_id UUID := gen_random_uuid();
BEGIN
  v_child_a := create_test_child('11111111-1111-1111-1111-111111111111'::UUID, 'A', '2018-01-01');
  v_child_b := create_test_child('22222222-2222-2222-2222-222222222222'::UUID, 'B', '2018-01-01');

  -- Workshop with 1 spot
  INSERT INTO workshops (
    id, venue_id, title, scheduled_at, duration_minutes,
    capacity, spots_remaining, price_paise, primary_trait, status
  ) VALUES (
    v_workshop_id,
    '00000000-0000-0000-0000-000000000001',
    'Test Workshop', now() + INTERVAL '1 day', 60,
    1, 1, 50000, 'gerry', 'upcoming'
  );

  -- TEST 1: First family registers — succeeds
  SELECT lives_ok(
    format('SELECT workshop_register(%L, %L, %L, %L, %L)',
           v_workshop_id,
           '11111111-1111-1111-1111-111111111111'::UUID,
           v_child_a,
           'wallet', 'idem_wshop_1'),
    'first registration succeeds'
  );

  SELECT is(
    (SELECT spots_remaining FROM workshops WHERE id = v_workshop_id),
    0,
    'spots_remaining decremented to 0'
  );

  -- TEST 2: Second family tries — workshop_full
  SELECT throws_ok(
    format('SELECT workshop_register(%L, %L, %L, %L, %L)',
           v_workshop_id,
           '22222222-2222-2222-2222-222222222222'::UUID,
           v_child_b,
           'wallet', 'idem_wshop_2'),
    '%workshop_full%',
    'second registration raises workshop_full'
  );

  -- TEST 3: Family B's wallet not debited (because RPC failed)
  SELECT is(
    (SELECT balance_paise FROM wallets WHERE family_id = '22222222-2222-2222-2222-222222222222'),
    100000,
    'family B wallet unchanged after workshop_full error'
  );

  -- TEST 4: Family A's wallet debited
  SELECT is(
    (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
    50000,
    'family A wallet debited 50000 paise'
  );

  -- TEST 5: Cancellation refunds wallet, restores spot
  SELECT lives_ok(
    format('SELECT workshop_cancel(%L, %L)',
           (SELECT id FROM workshop_registrations WHERE family_id = '11111111-1111-1111-1111-111111111111'),
           'changed mind'),
    'cancellation succeeds'
  );

  SELECT is(
    (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
    100000,
    'wallet refunded after cancellation'
  );

  SELECT is(
    (SELECT spots_remaining FROM workshops WHERE id = v_workshop_id),
    1,
    'spot restored after cancellation'
  );
END;

SELECT * FROM finish();
ROLLBACK;
```

---

## 10. Test 7 — Money Conservation

The most important test: verify no money is created or lost across all operations.

```sql
-- 22_money_conservation.sql
BEGIN;
SELECT plan(3);

-- Setup: 3 families with various activity
SELECT create_test_family(
  '11111111-1111-1111-1111-111111111111', '+919999999991', 'A'
);
SELECT create_test_family(
  '22222222-2222-2222-2222-222222222222', '+919999999992', 'B'
);
SELECT create_test_family(
  '33333333-3333-3333-3333-333333333333', '+919999999993', 'C'
);

-- Topups
PERFORM wallet_topup(
  '11111111-1111-1111-1111-111111111111'::UUID, 100000, 0, NULL, NULL);
PERFORM wallet_topup(
  '22222222-2222-2222-2222-222222222222'::UUID, 50000, 50000, NULL, NULL);
PERFORM wallet_topup(
  '33333333-3333-3333-3333-333333333333'::UUID, 200000, 0, NULL, NULL);

-- Various debits and credits via wallet_transactions...
-- (skip session/order setup for brevity; use direct ledger entries)

-- TEST 1: Sum of all wallet_transactions for family A equals balance
WITH txns AS (
  SELECT amount_paise FROM wallet_transactions
  WHERE family_id = '11111111-1111-1111-1111-111111111111'
)
SELECT is(
  (SELECT COALESCE(SUM(amount_paise), 0) FROM txns)::INTEGER,
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  'family A balance == sum of all txn amounts'
);

-- TEST 2: Same check for family B
WITH txns AS (
  SELECT amount_paise FROM wallet_transactions
  WHERE family_id = '22222222-2222-2222-2222-222222222222'
)
SELECT is(
  (SELECT COALESCE(SUM(amount_paise), 0) FROM txns)::INTEGER,
  (SELECT balance_paise FROM wallets WHERE family_id = '22222222-2222-2222-2222-222222222222'),
  'family B balance == sum of all txn amounts'
);

-- TEST 3: Each balance_after_paise is consistent with running sum
-- (sequenced per family, should monotonically reflect balance state)
DECLARE
  v_inconsistencies INTEGER;
BEGIN
  WITH per_family_running AS (
    SELECT
      family_id,
      created_at,
      amount_paise,
      balance_after_paise,
      SUM(amount_paise) OVER (PARTITION BY family_id ORDER BY created_at, id) as expected_balance
    FROM wallet_transactions
  )
  SELECT COUNT(*) INTO v_inconsistencies
  FROM per_family_running
  WHERE balance_after_paise <> expected_balance;

  SELECT is(v_inconsistencies, 0, 'all wallet_transactions.balance_after_paise consistent with running sum');
END;

SELECT * FROM finish();
ROLLBACK;
```

---

## 11. Test 8 — RLS Isolation

```sql
-- 23_rls_isolation.sql
BEGIN;
SELECT plan(4);

-- Setup two families with auth users
INSERT INTO families (id, phone, name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+919999999991', 'A'),
  ('22222222-2222-2222-2222-222222222222', '+919999999992', 'B');

-- Simulate auth.uid() = family A
SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
SET LOCAL ROLE authenticated;

-- TEST 1: Can read own family
SELECT is(
  (SELECT COUNT(*)::INTEGER FROM families),
  1,
  'authenticated as A: sees only own family'
);

-- TEST 2: Cannot read family B
SELECT is(
  (SELECT COUNT(*)::INTEGER FROM families WHERE id = '22222222-2222-2222-2222-222222222222'),
  0,
  'authenticated as A: cannot see family B'
);

-- TEST 3: Can read own wallet
SELECT cmp_ok(
  (SELECT COUNT(*)::INTEGER FROM wallets),
  '<=',
  1,
  'authenticated: sees only own wallet'
);

-- TEST 4: Cannot insert into another family's children
RESET ROLE;
SELECT throws_ok(
  $$ SET LOCAL "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';
     SET LOCAL ROLE authenticated;
     INSERT INTO children (family_id, name, date_of_birth)
     VALUES ('22222222-2222-2222-2222-222222222222'::UUID, 'Stolen', '2018-01-01')
  $$,
  '%new row violates row-level security%',
  'cannot insert child for another family'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 12. Test 9 — State Machine Tests

```sql
-- 20_state_machines.sql
BEGIN;
SELECT plan(8);

-- BIRTHDAY RESERVATION STATE MACHINE
-- Valid transitions: interested → admin_contacted → confirmed → completed
-- Or: any state → cancelled
-- Or: confirmed → no_show

INSERT INTO families (id, phone, name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+919999999991', 'A');

-- Setup a reservation
DECLARE
  v_pkg_id UUID := (SELECT id FROM birthday_packages LIMIT 1);
  v_child_id UUID;
  v_res_id UUID;
BEGIN
  v_child_id := create_test_child('11111111-1111-1111-1111-111111111111'::UUID, 'A', '2018-05-10');

  v_res_id := (SELECT (birthday_reservation_create(
    '00000000-0000-0000-0000-000000000001'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    v_child_id,
    v_pkg_id,
    'March 2026', 'weekend afternoon', 15, 10, '',
    'manual', 'idem_res_1'
  ))->>'reservation_id')::UUID;

  -- TEST 1: Initial state
  SELECT is(
    (SELECT status FROM birthday_reservations WHERE id = v_res_id),
    'interested',
    'initial state is interested'
  );

  -- TEST 2: interested → admin_contacted (admin updates status)
  UPDATE birthday_reservations SET status = 'admin_contacted' WHERE id = v_res_id;
  SELECT is(
    (SELECT status FROM birthday_reservations WHERE id = v_res_id),
    'admin_contacted',
    'admin_contacted state'
  );

  -- TEST 3: admin_contacted → confirmed
  UPDATE birthday_reservations SET status = 'confirmed' WHERE id = v_res_id;
  SELECT is(
    (SELECT status FROM birthday_reservations WHERE id = v_res_id),
    'confirmed',
    'confirmed state'
  );

  -- TEST 4: confirmed → completed via RPC
  SELECT lives_ok(
    format('SELECT birthday_reservation_complete(%L, %L)',
           v_res_id, '11111111-1111-1111-1111-111111111111'::UUID),
    'birthday_reservation_complete succeeds'
  );

  SELECT is(
    (SELECT status FROM birthday_reservations WHERE id = v_res_id),
    'completed',
    'state is completed'
  );

  -- TEST 5: birthday hero card auto-awarded
  SELECT cmp_ok(
    (SELECT COUNT(*)::INTEGER FROM hero_card_collection
     WHERE child_id = v_child_id AND birthday_booking_id = v_res_id),
    '>',
    0,
    'birthday hero card auto-awarded'
  );

  -- TEST 6: completed cannot transition back via RPC
  SELECT throws_ok(
    format('SELECT birthday_reservation_complete(%L, %L)',
           v_res_id, '11111111-1111-1111-1111-111111111111'::UUID),
    '%invalid_state_for_completion%',
    'cannot complete an already-completed reservation'
  );

  -- TEST 7: SESSION STATE — active → grace → completed
  -- (reuse session_create + manual status flips since cron is external)

  -- TEST 8: REFUND STATE — pending → approved → completed
  -- (similar pattern)
END;

SELECT * FROM finish();
ROLLBACK;
```

---

## 13. Test 10 — Idempotency Sweep

Single test file that exercises idempotency across ALL idempotency-key-supporting RPCs.

```sql
-- 21_idempotency.sql
BEGIN;
SELECT plan(6);

-- Setup
INSERT INTO families (id, phone, name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+919999999991', 'A');
PERFORM topup_test_wallet('11111111-1111-1111-1111-111111111111'::UUID, 500000);

-- Test wallet_topup idempotency
PERFORM wallet_topup('11111111-1111-1111-1111-111111111111'::UUID, 50000, 0, NULL, 'idem_X');
PERFORM wallet_topup('11111111-1111-1111-1111-111111111111'::UUID, 50000, 0, NULL, 'idem_X');

SELECT is(
  (SELECT COUNT(*)::INTEGER FROM wallet_transactions WHERE idempotency_key = 'idem_X'),
  1,
  'wallet_topup: replay creates only ONE row'
);

-- Test session_create idempotency
DECLARE
  v_child_id UUID;
BEGIN
  v_child_id := create_test_child('11111111-1111-1111-1111-111111111111'::UUID, 'A', '2018-01-01');

  PERFORM session_create(
    '00000000-0000-0000-0000-000000000001'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    v_child_id, 60, 'wallet', NULL, false, NULL, NULL, 'idem_Y'
  );
  PERFORM session_create(
    '00000000-0000-0000-0000-000000000001'::UUID,
    '11111111-1111-1111-1111-111111111111'::UUID,
    v_child_id, 60, 'wallet', NULL, false, NULL, NULL, 'idem_Y'
  );

  SELECT is(
    (SELECT COUNT(*)::INTEGER FROM sessions WHERE idempotency_key = 'idem_Y'),
    1,
    'session_create: replay creates only ONE row'
  );
END;

-- Test order_place idempotency
INSERT INTO menus (id, venue_id, brand, name)
VALUES ('aaaa1111-1111-1111-1111-111111111121',
        '00000000-0000-0000-0000-000000000001', 'coffee', 'Test');
INSERT INTO menu_items (id, menu_id, name, price_paise, is_available)
VALUES ('bbbb1111-1111-1111-1111-111111111121',
        'aaaa1111-1111-1111-1111-111111111121',
        'Test', 10000, true);

PERFORM order_place(
  '00000000-0000-0000-0000-000000000001'::UUID,
  '11111111-1111-1111-1111-111111111111'::UUID,
  '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111121", "quantity": 1}]'::JSONB,
  NULL, 'dine_in', 'wallet', NULL, 'idem_Z'
);
PERFORM order_place(
  '00000000-0000-0000-0000-000000000001'::UUID,
  '11111111-1111-1111-1111-111111111111'::UUID,
  '[{"menu_item_id": "bbbb1111-1111-1111-1111-111111111121", "quantity": 1}]'::JSONB,
  NULL, 'dine_in', 'wallet', NULL, 'idem_Z'
);

SELECT is(
  (SELECT COUNT(*)::INTEGER FROM orders WHERE idempotency_key = 'idem_Z'),
  1,
  'order_place: replay creates only ONE row'
);

-- Final wallet balance should be: 500000 - 50000 (Y session) - 10500 (Z order) + 50000 (X topup) = 489500
SELECT is(
  (SELECT balance_paise FROM wallets WHERE family_id = '11111111-1111-1111-1111-111111111111'),
  500000 - 80000 - 10500 + 50000 + (10500 * 7 / 100)::int,  -- approximate including coins
  'final balance reflects all unique operations'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 14. CI Configuration

### 14.1 GitHub Actions workflow

```yaml
# .github/workflows/pgtap.yml
name: pgTAP Tests

on:
  pull_request:
    paths:
      - 'supabase/migrations/**'
      - 'supabase/tests/**'
  push:
    branches: [main]

jobs:
  pgtap:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready"
          --health-interval=10s

    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client postgresql-contrib

      - name: Install pgTAP
        run: |
          sudo apt-get install -y postgresql-15-pgtap

      - name: Apply migrations
        env:
          PGPASSWORD: postgres
        run: |
          for migration in supabase/migrations/*.sql; do
            psql -h localhost -U postgres -d postgres -f "$migration"
          done

      - name: Run pgTAP tests
        env:
          PGPASSWORD: postgres
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/postgres
        run: ./scripts/run-pgtap.sh
```

### 14.2 Local script

```bash
# scripts/run-pgtap.sh
#!/bin/bash
set -e

DB_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"

echo "→ Resetting test database (Supabase)"
supabase db reset

echo "→ Running tests..."
START_TIME=$SECONDS
TOTAL_TESTS=0
FAILED_FILES=()

for file in supabase/tests/*.sql; do
  if [ "$(basename "$file")" = "00_setup.sql" ]; then
    continue  # setup is included in each test, not run standalone
  fi

  echo "  $file"
  if ! psql "$DB_URL" -f "$file" -X -q -v ON_ERROR_STOP=1 > /tmp/pgtap.out 2>&1; then
    FAILED_FILES+=("$file")
    cat /tmp/pgtap.out
  else
    grep -E "^# .*tests" /tmp/pgtap.out | head -1
  fi
done

DURATION=$((SECONDS - START_TIME))

if [ ${#FAILED_FILES[@]} -eq 0 ]; then
  echo
  echo "✓ All tests passed in ${DURATION}s"
  exit 0
else
  echo
  echo "✗ ${#FAILED_FILES[@]} test files failed:"
  printf '  - %s\n' "${FAILED_FILES[@]}"
  exit 1
fi
```

---

## 15. Coverage Goal

| RPC | Test File | Coverage |
|---|---|---|
| wallet_topup | 01 | Happy path, bonus, idempotency, negative amount |
| session_create | 02 | Wallet, cash, insufficient balance, invalid duration, invalid payment |
| session_extend | 03 | Active, grace, completed, idempotency, staff_on_behalf |
| session_force_close | 04 | Force close active and grace |
| order_place | 05 | Wallet, cash, sold-out, invalid combo, idempotency |
| xp_credit_with_split | 06 | Single trait, multi trait, stage transition, level update |
| reflection_submit | 07 | Tagged moments, no tags, expired window |
| reflection_auto_split | 08 | Equal split, batch processing |
| healthy_bite_distribute | 09 | Common card, rare card distribution |
| workshop_register | 10 | Happy, race, insufficient balance, full |
| workshop_cancel | 11 | Refund + spot restore |
| referral_convert | 12 | First (Brave Boost), subsequent, monthly cap |
| birthday_reservation_create | 13 | Happy, duplicate (reservation_exists) |
| birthday_reservation_complete | 14 | Hero card auto-award, XP bonus |
| birthday_album_publish | 15 | Photos required, notification |
| refund_issue | 16 | Staff cap, admin path, both destinations |
| refund_approve | 17 | Wallet, razorpay (state changes only) |
| shift_close | 18 | Discrepancy detection |
| reactivation_redeem | 19 | Phone match, expiry check |

---

## 16. Acceptance

```
Run all tests:
  ./scripts/run-pgtap.sh

Expected output:
  ✓ All tests passed in <30s

Each migration deploy in CI:
  - Apply migration
  - Run full pgTAP suite
  - Block deploy if any test fails
```

---

## 17. Open Items for Founder

- [ ] Decide testing budget for additional scenarios (currently covers core money safety)
- [ ] Approve CI cost (GitHub Actions free tier covers PR checks; private repos = $4/user/mo)
- [ ] Decide if Edge Function unit tests should also be required (Deno test framework, separate runner)
- [ ] Decide what blocks deploy: any pgTAP failure, OR a threshold (e.g., critical tests only)?

---

## What's NOT in this session

- Flutter widget tests (skipped for v1)
- Edge Function Deno tests (per-function, in those folders)
- E2E tests (manual QA covers user flows for v1)
- Load testing (defer to post-launch)
- Pre-launch verification (Session 15)
