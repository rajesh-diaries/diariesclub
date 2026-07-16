-- ===========================================================================
--  Party pipeline test suite — T1..T10 (founder spec, 2026-07-12)
--
--  RUN ON A DISPOSABLE BRANCH/SHADOW DB ONLY. Never on prod.
--  Requires 0236 + 0237 applied. Run as postgres in ONE batch; staff/admin
--  identity is simulated via request.jwt.claims (what auth.uid() reads).
--  Re-runs: reset the branch first (fixtures use fixed UUIDs/phones).
--
--  T1  lead create returns id
--  T2  same phone+date dedupes to same lead and appends note
--  T3  state machine: new→contacted→quoted legal; advance-to-'won' raises
--  T4  convert: lead won, reservation confirmed, exactly 11 checklist items
--  T4b convert replay returns same reservation
--  T5  money: advance/replay/balance/refund against derived columns
--  T6  slot check: overlap on same date/slot; clear elsewhere; block row
--  T7  checklist toggle stamps done_by/done_at; consistency holds
--  T8  stale sweep moves exactly the 8-day-old lead
--  T9  repeat generator: exactly 1 lead for a 320-day-old completed party;
--      second run 0
--  T10 report has all five keys and won ≥ 1
-- ===========================================================================

-- ── Result + state scratch tables ──────────────────────────────────────────
CREATE TEMP TABLE _t (seq SERIAL, test TEXT, ok BOOLEAN, detail TEXT);
CREATE TEMP TABLE _vars (k TEXT PRIMARY KEY, v TEXT);

-- ── Fixtures (as postgres, direct writes) ──────────────────────────────────
DO $fixtures$
DECLARE
  c_venue   UUID := '00000000-0000-0000-0000-000000000001'; -- seeded Kondapur
  c_tablet  UUID := '11111111-1111-1111-1111-111111111111'; -- tablet auth user
  c_admin   UUID := '22222222-2222-2222-2222-222222222222'; -- admin auth user
  c_staff   UUID := '33333333-3333-3333-3333-333333333333';
  c_pkg     UUID := '44444444-4444-4444-4444-444444444444';
  c_rfam    UUID := '55555555-5555-5555-5555-555555555555'; -- repeat family (=auth id)
  c_rchild  UUID := '66666666-6666-6666-6666-666666666666';
  c_rres    UUID := '77777777-7777-7777-7777-777777777777'; -- completed 320d-old party
BEGIN
  -- auth users: tablet, admin, repeat-family (0015 §5 shape)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at)
  VALUES
    (c_tablet, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'test-tablet@diariesclub.local', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (c_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'test-admin@diariesclub.local', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (c_rfam, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'test-repeat-family@diariesclub.local', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO tablet_devices (venue_id, device_label, auth_user_id, is_active)
  VALUES (c_venue, 'TEST tablet', c_tablet, true)
  ON CONFLICT (auth_user_id) DO NOTHING;

  INSERT INTO staff (id, venue_id, name, phone, pin_hash, role, is_active)
  VALUES (c_staff, c_venue, 'TEST Staff', '+919999900001', 'test-hash', 'manager', true)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO admin_users (auth_user_id, name, email, role, is_active)
  VALUES (c_admin, 'TEST Admin', 'test-admin@diariesclub.local', 'admin', true)
  ON CONFLICT (auth_user_id) DO NOTHING;

  INSERT INTO birthday_packages (id, venue_id, name, tier, price_paise,
                                 duration_hours, max_kids, max_adults,
                                 inclusions, deposit_paise, is_active)
  VALUES (c_pkg, c_venue, 'TEST Party Package', 'custom', 4000000,
          3, 30, 60, '[]'::jsonb, 1000000, true)
  ON CONFLICT (id) DO NOTHING;

  -- Repeat-cron fixture: family + child + COMPLETED party 320 days ago
  INSERT INTO families (id, phone, name)
  VALUES (c_rfam, '+919876500001', 'Repeat Parent')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO children (id, family_id, name, date_of_birth)
  VALUES (c_rchild, c_rfam, 'Repeat Kid', '2019-03-15')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO birthday_reservations (id, venue_id, family_id, child_id, package_id,
                                     slot_date, slot, num_kids, num_adults,
                                     package_price_paise, deposit_paid_paise,
                                     balance_paise, total_paid_paise, status)
  VALUES (c_rres, c_venue, c_rfam, c_rchild, c_pkg,
          (now() AT TIME ZONE 'Asia/Kolkata')::DATE - 320, 'evening', 12, 20,
          3500000, 3500000, 0, 3500000, 'completed')
  ON CONFLICT (id) DO NOTHING;

  -- Stale-sweep fixtures: one 8-day-old open lead, one 2-day-old
  INSERT INTO party_leads (venue_id, source, status, parent_name, phone,
                           created_at, updated_at)
  VALUES
    (c_venue, 'phone', 'contacted', 'Stale Parent', '+919876500002',
     now() - INTERVAL '9 days', now() - INTERVAL '8 days'),
    (c_venue, 'phone', 'new', 'Fresh Parent', '+919876500003',
     now() - INTERVAL '2 days', now() - INTERVAL '2 days');

  -- Slot-check block fixture: venue blocked (maintenance) 31 days out
  INSERT INTO birthday_availability (venue_id, slot_date, slot_start_time,
                                     slot_end_time, is_blocked, block_reason)
  VALUES (c_venue, (now() AT TIME ZONE 'Asia/Kolkata')::DATE + 31,
          '09:00', '21:00', true, 'TEST maintenance')
  ON CONFLICT (venue_id, slot_date, slot_start_time) DO NOTHING;

  INSERT INTO _vars VALUES
    ('venue',  c_venue::TEXT),  ('staff', c_staff::TEXT),
    ('pkg',    c_pkg::TEXT),    ('rres',  c_rres::TEXT),
    ('tablet', c_tablet::TEXT), ('admin', c_admin::TEXT);
END $fixtures$;

-- ── Act as the venue tablet (staff lane) ───────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', false);

-- ── T1: lead create returns id ─────────────────────────────────────────────
DO $t1$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_pkg   UUID := (SELECT v FROM _vars WHERE k = 'pkg')::UUID;
  v_date  DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE + 30;
  r JSONB;
BEGIN
  r := party_lead_create(
    p_source := 'phone', p_parent_name := 'Asha', p_phone := '+919876500010',
    p_staff_pin_id := v_staff, p_child_name := 'Vivaan',
    p_child_dob := '2020-01-10', p_guest_estimate := 25,
    p_event_date_requested := v_date, p_slot_pref := 'evening',
    p_package_id := v_pkg, p_note := 'wants jungle theme');

  IF (r->>'lead_id') IS NULL THEN
    RAISE EXCEPTION 'T1: no lead_id in %', r;
  END IF;
  IF (r->>'deduped')::BOOLEAN THEN
    RAISE EXCEPTION 'T1: fresh lead flagged deduped';
  END IF;

  INSERT INTO _vars VALUES ('lead1', r->>'lead_id'), ('lead1_date', v_date::TEXT);
  INSERT INTO _t(test, ok, detail) VALUES ('T1 lead create', true, 'lead_id ' || (r->>'lead_id'));
END $t1$;

-- ── T2: same phone+date dedupes and appends note ───────────────────────────
DO $t2$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_date  DATE := (SELECT v FROM _vars WHERE k = 'lead1_date')::DATE;
  v_lead1 UUID := (SELECT v FROM _vars WHERE k = 'lead1')::UUID;
  r JSONB; v_notes INTEGER;
BEGIN
  r := party_lead_create(
    p_source := 'phone', p_parent_name := 'Asha again', p_phone := '+91 98765 00010',
    p_staff_pin_id := v_staff, p_event_date_requested := v_date,
    p_note := 'called back about veg menu');

  IF (r->>'lead_id')::UUID <> v_lead1 THEN
    RAISE EXCEPTION 'T2: dedupe returned different lead % vs %', r->>'lead_id', v_lead1;
  END IF;
  IF NOT (r->>'deduped')::BOOLEAN THEN
    RAISE EXCEPTION 'T2: repeat call not flagged deduped';
  END IF;

  SELECT COUNT(*) INTO v_notes FROM party_lead_notes WHERE lead_id = v_lead1;
  IF v_notes < 2 THEN
    RAISE EXCEPTION 'T2: expected >=2 notes (initial + repeat), got %', v_notes;
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T2 dedupe + note append', true, format('same lead, %s notes', v_notes));
END $t2$;

-- ── T3: state machine — legal path works, advance-to-won raises ────────────
DO $t3$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_lead1 UUID := (SELECT v FROM _vars WHERE k = 'lead1')::UUID;
  r JSONB; v_raised BOOLEAN := false; v_status TEXT;
BEGIN
  r := party_lead_advance(v_lead1, 'contacted', v_staff,
                          p_note := 'spoke, sending quote');
  r := party_lead_advance(v_lead1, 'quoted', v_staff,
                          p_next_follow_up_at := now() + INTERVAL '2 days');

  SELECT status INTO v_status FROM party_leads WHERE id = v_lead1;
  IF v_status <> 'quoted' THEN
    RAISE EXCEPTION 'T3: expected quoted, got %', v_status;
  END IF;

  BEGIN
    r := party_lead_advance(v_lead1, 'won', v_staff);
  EXCEPTION WHEN OTHERS THEN
    v_raised := true;
    IF SQLERRM NOT LIKE '%won_only_via_convert%' THEN
      RAISE EXCEPTION 'T3: wrong error for advance-to-won: %', SQLERRM;
    END IF;
  END;
  IF NOT v_raised THEN
    RAISE EXCEPTION 'T3: advance-to-won did not raise';
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T3 state machine', true, 'new→contacted→quoted ok; won raises won_only_via_convert');
END $t3$;

-- ── T4 + T4b: convert instantiates booking + 11 items; replay is stable ────
DO $t4$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_pkg   UUID := (SELECT v FROM _vars WHERE k = 'pkg')::UUID;
  v_lead1 UUID := (SELECT v FROM _vars WHERE k = 'lead1')::UUID;
  v_date  DATE := (SELECT v FROM _vars WHERE k = 'lead1_date')::DATE;
  r JSONB; r2 JSONB; v_res UUID; v_items INTEGER;
  v_lstatus TEXT; v_rstatus TEXT; v_trig TEXT;
BEGIN
  r := party_lead_convert(
    p_lead_id := v_lead1, p_staff_pin_id := v_staff, p_package_id := v_pkg,
    p_slot_date := v_date, p_slot := 'evening', p_price_paise := 4000000,
    p_num_kids := 15, p_num_adults := 30,
    p_slot_start_time := '17:00', p_slot_end_time := '20:00',
    p_idempotency_key := 'test-convert-1');

  v_res := (r->>'reservation_id')::UUID;
  IF v_res IS NULL THEN RAISE EXCEPTION 'T4: no reservation_id in %', r; END IF;
  IF (r->>'replay')::BOOLEAN THEN RAISE EXCEPTION 'T4: first convert flagged replay'; END IF;

  SELECT status INTO v_lstatus FROM party_leads WHERE id = v_lead1;
  SELECT status, triggered_by INTO v_rstatus, v_trig
    FROM birthday_reservations WHERE id = v_res;
  SELECT COUNT(*) INTO v_items FROM party_checklist_items WHERE reservation_id = v_res;

  IF v_lstatus <> 'won' THEN RAISE EXCEPTION 'T4: lead status % not won', v_lstatus; END IF;
  IF v_rstatus <> 'confirmed' THEN RAISE EXCEPTION 'T4: reservation % not confirmed', v_rstatus; END IF;
  IF v_trig <> 'phone' THEN RAISE EXCEPTION 'T4: triggered_by % <> lead source phone', v_trig; END IF;
  IF v_items <> 11 THEN RAISE EXCEPTION 'T4: expected exactly 11 checklist items, got %', v_items; END IF;
  -- the walk-in path materialised a family keyed on the lead phone
  IF NOT EXISTS (SELECT 1 FROM families WHERE phone = '+919876500010' AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'T4: family not created/linked for lead phone';
  END IF;

  INSERT INTO _vars VALUES ('res1', v_res::TEXT);
  INSERT INTO _t(test, ok, detail)
  VALUES ('T4 convert', true, format('won, confirmed, triggered_by=phone, %s items', v_items));

  -- T4b: replay
  r2 := party_lead_convert(
    p_lead_id := v_lead1, p_staff_pin_id := v_staff, p_package_id := v_pkg,
    p_slot_date := v_date, p_slot := 'evening', p_price_paise := 4000000,
    p_num_kids := 15, p_num_adults := 30,
    p_idempotency_key := 'test-convert-2');

  IF NOT (r2->>'replay')::BOOLEAN THEN RAISE EXCEPTION 'T4b: second convert not flagged replay'; END IF;
  IF (r2->>'reservation_id')::UUID <> v_res THEN
    RAISE EXCEPTION 'T4b: replay returned different reservation';
  END IF;
  IF (SELECT COUNT(*) FROM party_checklist_items WHERE reservation_id = v_res) <> 11 THEN
    RAISE EXCEPTION 'T4b: replay duplicated checklist items';
  END IF;

  INSERT INTO _t(test, ok, detail) VALUES ('T4b convert replay', true, 'same reservation, no dupes');
END $t4$;

-- ── T5: money — advance / replay / balance / refund on derived columns ─────
DO $t5$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_res   UUID := (SELECT v FROM _vars WHERE k = 'res1')::UUID;
  r JSONB; r_replay JSONB;
  v_dep INTEGER; v_bal INTEGER; v_cnt INTEGER; v_dir SMALLINT;
BEGIN
  -- advance ₹15,000
  r := party_payment_record(v_res, 'advance', 1500000, 'upi', v_staff, 'test-pay-1');
  SELECT deposit_paid_paise, balance_paise INTO v_dep, v_bal
    FROM birthday_reservations WHERE id = v_res;
  IF v_dep <> 1500000 THEN RAISE EXCEPTION 'T5: deposit % <> 1500000', v_dep; END IF;
  IF v_bal <> 2500000 THEN RAISE EXCEPTION 'T5: balance % <> 2500000 (price 4000000)', v_bal; END IF;
  -- Format is whatever the existing _next_invoice_number() emits (prod's
  -- captured version uses DC<yy>-<seq>-<suffix>, not the 0100 INV- shape).
  IF (r->>'invoice_no') IS NULL OR length(r->>'invoice_no') < 6 THEN
    RAISE EXCEPTION 'T5: bad invoice_no %', r->>'invoice_no';
  END IF;

  -- replay same idempotency key → no double charge
  r_replay := party_payment_record(v_res, 'advance', 1500000, 'upi', v_staff, 'test-pay-1');
  IF NOT (r_replay->>'replay')::BOOLEAN THEN RAISE EXCEPTION 'T5: replay not flagged'; END IF;
  IF (r_replay->>'payment_id') <> (r->>'payment_id') THEN
    RAISE EXCEPTION 'T5: replay returned different payment row';
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM party_payments WHERE reservation_id = v_res;
  IF v_cnt <> 1 THEN RAISE EXCEPTION 'T5: double charge! % rows after replay', v_cnt; END IF;
  SELECT deposit_paid_paise INTO v_dep FROM birthday_reservations WHERE id = v_res;
  IF v_dep <> 1500000 THEN RAISE EXCEPTION 'T5: deposit moved on replay: %', v_dep; END IF;

  -- balance ₹25,000 → settles to 0
  r := party_payment_record(v_res, 'balance', 2500000, 'cash', v_staff, 'test-pay-2');
  SELECT balance_paise INTO v_bal FROM birthday_reservations WHERE id = v_res;
  IF v_bal <> 0 THEN RAISE EXCEPTION 'T5: balance % <> 0 after settlement', v_bal; END IF;

  -- refund ₹5,000 → nets deposit down, raises balance
  r := party_payment_record(v_res, 'refund', 500000, 'cash', v_staff, 'test-pay-3');
  SELECT deposit_paid_paise, balance_paise INTO v_dep, v_bal
    FROM birthday_reservations WHERE id = v_res;
  IF v_dep <> 3500000 THEN RAISE EXCEPTION 'T5: post-refund deposit % <> 3500000', v_dep; END IF;
  IF v_bal <> 500000 THEN RAISE EXCEPTION 'T5: post-refund balance % <> 500000', v_bal; END IF;
  SELECT direction INTO v_dir FROM party_payments
    WHERE reservation_id = v_res AND kind = 'refund';
  IF v_dir <> -1 THEN RAISE EXCEPTION 'T5: refund direction % <> -1', v_dir; END IF;
  IF (r->>'invoice_no') IS NOT NULL THEN
    RAISE EXCEPTION 'T5: refund received an invoice number';
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T5 money + idempotency', true,
          'advance→15000_00/25000_00; replay no-op; balance→0; refund→35000_00/5000_00');
END $t5$;

-- ── T6: slot check — conflict on same date/slot, clear elsewhere, block ────
DO $t6$
DECLARE
  v_venue UUID := (SELECT v FROM _vars WHERE k = 'venue')::UUID;
  v_date  DATE := (SELECT v FROM _vars WHERE k = 'lead1_date')::DATE;
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  r JSONB;
BEGIN
  r := party_slot_check(v_venue, v_date, 'evening');
  IF jsonb_array_length(r->'conflicts') < 1 THEN
    RAISE EXCEPTION 'T6: no conflict detected on booked date/slot: %', r;
  END IF;
  IF (r->>'clear')::BOOLEAN THEN RAISE EXCEPTION 'T6: booked slot reported clear'; END IF;

  r := party_slot_check(v_venue, v_today + 45, 'morning');
  IF jsonb_array_length(r->'conflicts') <> 0 OR jsonb_array_length(r->'blocks') <> 0
     OR NOT (r->>'clear')::BOOLEAN THEN
    RAISE EXCEPTION 'T6: clear slot not reported clear: %', r;
  END IF;

  r := party_slot_check(v_venue, v_today + 31, 'morning');
  IF jsonb_array_length(r->'blocks') < 1 THEN
    RAISE EXCEPTION 'T6: venue block not surfaced: %', r;
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T6 slot check', true, 'conflict + clear + block all detected (informational)');
END $t6$;

-- ── T7: checklist toggle stamps done_by/done_at ────────────────────────────
DO $t7$
DECLARE
  v_staff UUID := (SELECT v FROM _vars WHERE k = 'staff')::UUID;
  v_res   UUID := (SELECT v FROM _vars WHERE k = 'res1')::UUID;
  r JSONB; v_row party_checklist_items%ROWTYPE;
BEGIN
  r := party_checklist_toggle(v_res, 'decor', true, v_staff);
  SELECT * INTO v_row FROM party_checklist_items
    WHERE reservation_id = v_res AND item_key = 'decor';
  IF NOT v_row.is_done OR v_row.done_at IS NULL OR v_row.done_by_staff_id <> v_staff THEN
    RAISE EXCEPTION 'T7: toggle-on did not stamp done_by/done_at: %', to_jsonb(v_row);
  END IF;

  r := party_checklist_toggle(v_res, 'decor', false, v_staff);
  SELECT * INTO v_row FROM party_checklist_items
    WHERE reservation_id = v_res AND item_key = 'decor';
  IF v_row.is_done OR v_row.done_at IS NOT NULL OR v_row.done_by_staff_id IS NOT NULL THEN
    RAISE EXCEPTION 'T7: toggle-off did not clear stamps: %', to_jsonb(v_row);
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T7 checklist toggle', true, 'done⇔done_at consistency held both ways');
END $t7$;

-- ── Crons run as service (grant-gated; postgres in tests) ─────────────────
SELECT set_config('request.jwt.claims', '', false);

-- ── T8: stale sweep moves exactly the 8-day-old lead ───────────────────────
DO $t8$
DECLARE
  r JSONB; v_stale TEXT; v_fresh TEXT;
BEGIN
  r := party_stale_sweep();
  IF (r->>'swept')::INTEGER <> 1 THEN
    RAISE EXCEPTION 'T8: swept % leads, expected exactly 1', r->>'swept';
  END IF;

  SELECT status INTO v_stale FROM party_leads WHERE phone = '+919876500002';
  SELECT status INTO v_fresh FROM party_leads WHERE phone = '+919876500003';
  IF v_stale <> 'stale' THEN RAISE EXCEPTION 'T8: 8-day lead is %, not stale', v_stale; END IF;
  IF v_fresh <> 'new' THEN RAISE EXCEPTION 'T8: 2-day lead moved to %', v_fresh; END IF;

  INSERT INTO _t(test, ok, detail) VALUES ('T8 stale sweep', true, 'swept=1, fresh untouched');
END $t8$;

-- ── T9: repeat generator — exactly 1 lead, second run 0 ────────────────────
DO $t9$
DECLARE
  v_rres UUID := (SELECT v FROM _vars WHERE k = 'rres')::UUID;
  r JSONB; v_lead party_leads%ROWTYPE; v_expected DATE;
BEGIN
  r := party_repeat_lead_generate();
  IF (r->>'created')::INTEGER <> 1 THEN
    RAISE EXCEPTION 'T9: created % repeat leads, expected exactly 1', r->>'created';
  END IF;

  SELECT * INTO v_lead FROM party_leads WHERE repeat_of_reservation_id = v_rres;
  IF NOT FOUND THEN RAISE EXCEPTION 'T9: repeat lead missing'; END IF;
  IF v_lead.source <> 'repeat_customer' THEN
    RAISE EXCEPTION 'T9: source % <> repeat_customer', v_lead.source;
  END IF;
  IF v_lead.phone <> '+919876500001' THEN
    RAISE EXCEPTION 'T9: phone % <> family phone', v_lead.phone;
  END IF;
  v_expected := ((now() AT TIME ZONE 'Asia/Kolkata')::DATE - 320 + INTERVAL '1 year')::DATE;
  IF v_lead.event_date_requested <> v_expected THEN
    RAISE EXCEPTION 'T9: requested date % <> slot_date+1y (%)',
      v_lead.event_date_requested, v_expected;
  END IF;

  r := party_repeat_lead_generate();
  IF (r->>'created')::INTEGER <> 0 THEN
    RAISE EXCEPTION 'T9: second run created % (dedup broken)', r->>'created';
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T9 repeat generator', true, 'run1=1 lead (date=slot+1y), run2=0');
END $t9$;

-- ── Act as admin for the report ────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', false);

-- ── T10: report shape + won count ──────────────────────────────────────────
DO $t10$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  r JSONB;
BEGIN
  r := admin_party_pipeline_report(v_today - 1, v_today + 1);

  IF NOT (r ? 'by_source' AND r ? 'funnel' AND r ? 'bookings_ahead_4w'
          AND r ? 'lost_reasons' AND r ? 'money') THEN
    RAISE EXCEPTION 'T10: missing report keys, got %', (SELECT jsonb_agg(k) FROM jsonb_object_keys(r) k);
  END IF;
  IF COALESCE((r->'funnel'->>'won')::INTEGER, 0) < 1 THEN
    RAISE EXCEPTION 'T10: funnel.won = %, expected >= 1', r->'funnel'->>'won';
  END IF;
  IF jsonb_array_length(r->'bookings_ahead_4w') <> 4 THEN
    RAISE EXCEPTION 'T10: expected 4 weekly buckets, got %',
      jsonb_array_length(r->'bookings_ahead_4w');
  END IF;

  INSERT INTO _t(test, ok, detail)
  VALUES ('T10 pipeline report', true,
          format('5 keys, won=%s, conversion=%s%%, collected=%s paise',
                 r->'funnel'->>'won', r->'funnel'->>'conversion_pct',
                 r->'money'->>'collected_paise'));
END $t10$;

-- ── Results ────────────────────────────────────────────────────────────────
SELECT test, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, detail
  FROM _t ORDER BY seq;
