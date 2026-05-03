# Session 1 — Database Schema + RLS

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.

---

## Session Header

```
I am building Diaries Club — a Flutter + Supabase app for a kids play area
in Hyderabad. Permanent context above (00_CONTEXT.md) covers business priorities,
tech stack, locked decisions, conventions.

This session: Database Schema + Row-Level Security
Estimated time: 2–3 hours
What to build: Complete Supabase Postgres schema for v1 — every table, index,
  trigger, RLS policy, seed data needed before any RPC or Flutter code.
What NOT to build: RPC functions (next session), Edge Functions, Flutter code.
Output expected: A single `supabase/migrations/0001_initial_schema.sql` file
  that is idempotent (CREATE TABLE IF NOT EXISTS, etc.) and can be re-run
  safely. All money in paise. All timestamps TIMESTAMPTZ. All UUIDs.
Acceptance:
  - File runs cleanly on a fresh Supabase project (psql / SQL editor)
  - Can be re-run without errors
  - One venue ('Play Diaries Kondapur') and its venue_config row are seeded
  - Wallet auto-create trigger fires on new family insert (test by inserting a family)
  - RLS prevents cross-family data access (test with two auth.uid() values)
```

---

## 1. Identity & Money

### `venues`

```sql
CREATE TABLE IF NOT EXISTS venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,                        -- E.164: +919876543210
  whatsapp TEXT,                     -- E.164
  max_capacity INTEGER DEFAULT 50,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `families` — IMPORTANT: `id = auth.users.id`

```sql
CREATE TABLE IF NOT EXISTS families (
  -- families.id MUST equal auth.users.id (Supabase Auth UUID).
  -- Insert with the user's auth UID; do NOT rely on gen_random_uuid().
  id UUID PRIMARY KEY,
  phone TEXT UNIQUE NOT NULL,        -- E.164 canonical: +919876543210
  name TEXT NOT NULL,
  email TEXT,                        -- optional, for GST invoices
  referral_code TEXT UNIQUE NOT NULL DEFAULT upper(substr(md5(random()::text), 1, 8)),
  marketing_consent BOOLEAN DEFAULT false,
  fcm_token TEXT,                    -- last-known FCM device token
  fcm_platform TEXT CHECK (fcm_platform IN ('ios', 'android', 'web')),
  app_version TEXT,                  -- last-seen version, e.g. "1.0.0+1"
  is_cafe_only BOOLEAN DEFAULT false, -- TRUE if signed up without children
  has_children BOOLEAN DEFAULT false, -- denormalised flag for fast Home tab routing
  -- Soft-delete / anonymisation (DPDP compliance)
  deleted_at TIMESTAMPTZ,            -- when anonymisation was performed
  is_anonymised BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_active_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_families_phone ON families(phone) WHERE deleted_at IS NULL;
```

### Phone-format guard (trigger)

```sql
-- Reject any phone not in E.164 format
CREATE OR REPLACE FUNCTION validate_phone_e164() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.phone !~ '^\+91[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'invalid_phone_format: must be E.164 +91XXXXXXXXXX';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER families_validate_phone
BEFORE INSERT OR UPDATE OF phone ON families
FOR EACH ROW EXECUTE FUNCTION validate_phone_e164();
```

### `children`

```sql
CREATE TABLE IF NOT EXISTS children (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  date_of_birth DATE NOT NULL,
  photo_url TEXT,                    -- 1080×1080 max, ≤500 KB JPEG
  delivery_address TEXT,
  -- Favourite hero (cosmetic avatar only — all four still earn XP)
  favourite_hero TEXT NOT NULL DEFAULT 'ellie'
    CHECK (favourite_hero IN ('rafi', 'ellie', 'gerry', 'zena')),
  -- Per-trait XP (each hero levels independently)
  xp_rafi    INTEGER DEFAULT 0,      -- Brave
  xp_ellie   INTEGER DEFAULT 0,      -- Kind
  xp_gerry   INTEGER DEFAULT 0,      -- Curious
  xp_zena    INTEGER DEFAULT 0,      -- Creative
  -- Per-trait stage (denormalised for fast reads; recomputed by xp_credit RPC)
  stage_rafi  TEXT DEFAULT 'seedling' CHECK (stage_rafi  IN ('seedling','explorer','adventurer','champion','legend')),
  stage_ellie TEXT DEFAULT 'seedling' CHECK (stage_ellie IN ('seedling','explorer','adventurer','champion','legend')),
  stage_gerry TEXT DEFAULT 'seedling' CHECK (stage_gerry IN ('seedling','explorer','adventurer','champion','legend')),
  stage_zena  TEXT DEFAULT 'seedling' CHECK (stage_zena  IN ('seedling','explorer','adventurer','champion','legend')),
  -- Overall (derived sum)
  total_xp INTEGER DEFAULT 0,
  current_level INTEGER DEFAULT 1,
  current_overall_stage TEXT DEFAULT 'seedling'
    CHECK (current_overall_stage IN ('seedling','explorer','adventurer','champion','legend')),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_children_family ON children(family_id);
```

### `wallets` — auto-create on family insert

```sql
CREATE TABLE IF NOT EXISTS wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID UNIQUE NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  balance_paise INTEGER DEFAULT 0 CHECK (balance_paise >= 0),
  -- Diaries Coins are SAME currency (just labelled differently in tx history)
  -- The coins_balance column tracks lifetime coin earnings for display ("you have earned 450 coins")
  -- but the spendable amount is balance_paise.
  coins_lifetime INTEGER DEFAULT 0 CHECK (coins_lifetime >= 0),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Trigger: every new family gets a wallet automatically
CREATE OR REPLACE FUNCTION create_wallet_for_family() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO wallets (family_id) VALUES (NEW.id)
  ON CONFLICT (family_id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER families_create_wallet
AFTER INSERT ON families
FOR EACH ROW EXECUTE FUNCTION create_wallet_for_family();
```

### `wallet_transactions` — append-only ledger

```sql
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id),
  type TEXT NOT NULL CHECK (type IN (
    'topup','bonus','session_debit','extension_debit',
    'order_debit','workshop_debit','birthday_deposit_debit','birthday_balance_debit',
    'refund','coins_credit','coins_debit',
    'reactivation_credit',  -- ₹200 welcome-back for paper-book contacts
    'visit_bonus',          -- visit-frequency rewards
    'streak_milestone',     -- streak rewards
    'manual_credit','manual_debit'  -- admin adjustments
  )),
  amount_paise INTEGER NOT NULL,            -- signed: positive = credit, negative = debit
  balance_after_paise INTEGER NOT NULL,
  coins_amount INTEGER DEFAULT 0,           -- coin-equivalent display value
  payment_method TEXT CHECK (payment_method IN ('wallet','cash','razorpay','system')),
  -- 'system' is for non-cash credits (reactivation, bonuses, milestones, refunds)
  razorpay_payment_id TEXT,
  reference_id UUID,                        -- session_id, order_id, etc.
  reference_type TEXT,
  idempotency_key TEXT UNIQUE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_wallet_tx_family ON wallet_transactions(family_id, created_at DESC);
CREATE INDEX idx_wallet_tx_idempotency ON wallet_transactions(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX idx_wallet_tx_razorpay ON wallet_transactions(razorpay_payment_id) WHERE razorpay_payment_id IS NOT NULL;
```

---

## 2. Sessions, Pre-Bookings, Orders

### `sessions`

```sql
CREATE TABLE IF NOT EXISTS sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  family_id UUID REFERENCES families(id),
  child_id UUID REFERENCES children(id),
  staff_pin_id UUID REFERENCES staff(id),  -- which staff (by PIN) created it
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes IN (60, 120)),
  amount_paise INTEGER NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('wallet','cash','razorpay')),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','grace','completed','void','auto_closed')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  grace_started_at TIMESTAMPTZ,
  grace_force_close_at TIMESTAMPTZ, -- expires_at + grace_max_minutes (computed at insert)
  completed_at TIMESTAMPTZ,
  healthy_bite_earned BOOLEAN DEFAULT false,
  healthy_bite_distributed BOOLEAN DEFAULT false,
  total_xp_earned INTEGER DEFAULT 0,            -- before reflection
  reflection_status TEXT DEFAULT 'pending'      -- pending | reflected | auto_split
    CHECK (reflection_status IN ('pending','reflected','auto_split')),
  reflection_deadline TIMESTAMPTZ,              -- completed_at + 24h
  is_guest BOOLEAN DEFAULT false,
  guest_phone TEXT,                             -- E.164
  pre_booking_id UUID,                          -- if this session came from a pre-booking
  notes TEXT,
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_sessions_venue_active ON sessions(venue_id, status) WHERE status IN ('active','grace');
CREATE INDEX idx_sessions_family ON sessions(family_id, created_at DESC);
CREATE INDEX idx_sessions_child ON sessions(child_id, created_at DESC);
CREATE INDEX idx_sessions_reflection_pending ON sessions(reflection_deadline)
  WHERE reflection_status = 'pending';
```

### `session_extensions`

```sql
CREATE TABLE IF NOT EXISTS session_extensions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES sessions(id),
  duration_minutes INTEGER NOT NULL,
  amount_paise INTEGER NOT NULL,
  payment_method TEXT NOT NULL,
  new_expires_at TIMESTAMPTZ NOT NULL,
  staff_pin_id UUID REFERENCES staff(id),
  initiated_by TEXT CHECK (initiated_by IN ('parent','staff_on_behalf')),
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `session_pre_bookings` — NEW (Return-2)

```sql
CREATE TABLE IF NOT EXISTS session_pre_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  family_id UUID NOT NULL REFERENCES families(id),
  child_id UUID NOT NULL REFERENCES children(id),
  scheduled_start TIMESTAMPTZ NOT NULL,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes IN (60, 120)),
  amount_paise INTEGER NOT NULL,
  hold_amount_paise INTEGER NOT NULL,           -- partial hold from wallet (e.g. 50%)
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved','redeemed','expired','cancelled')),
  redeemed_session_id UUID REFERENCES sessions(id),
  expires_at TIMESTAMPTZ NOT NULL,              -- 30 min after scheduled_start
  cancellation_reason TEXT,
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_pre_bookings_venue_upcoming ON session_pre_bookings(venue_id, scheduled_start)
  WHERE status = 'reserved';
CREATE INDEX idx_pre_bookings_family ON session_pre_bookings(family_id, scheduled_start DESC);
```

### `qr_nonces` — single-use QR enforcement

```sql
CREATE TABLE IF NOT EXISTS qr_nonces (
  nonce UUID PRIMARY KEY,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_qr_nonces_unused ON qr_nonces(expires_at) WHERE used_at IS NULL;
```

### `orders` — Coffee + FIT food

```sql
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  family_id UUID REFERENCES families(id),
  staff_pin_id UUID REFERENCES staff(id),
  fulfillment_mode TEXT NOT NULL CHECK (fulfillment_mode IN ('dine_in','takeaway','table_service')),
  -- table_service = "while-you-wait" order delivered to parent's seat
  payment_method TEXT NOT NULL CHECK (payment_method IN ('wallet','cash','razorpay')),
  subtotal_paise INTEGER NOT NULL,         -- pre-GST, server-calculated
  gst_paise INTEGER NOT NULL,              -- 5%, server-calculated
  combo_discount_paise INTEGER DEFAULT 0,  -- if a combo was applied
  total_paise INTEGER NOT NULL,
  coins_earned INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','preparing','ready','served','cancelled')),
  combo_id UUID REFERENCES combos(id),
  invoice_pdf_url TEXT,                    -- generated by Edge Function
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_orders_venue ON orders(venue_id, created_at DESC);
CREATE INDEX idx_orders_family ON orders(family_id, created_at DESC);
```

### `order_items`

```sql
CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES menu_items(id),
  brand TEXT NOT NULL CHECK (brand IN ('coffee','fit')),
  name_snapshot TEXT NOT NULL,             -- denormalised name at order time
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price_paise INTEGER NOT NULL,       -- server-looked-up price at order time
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `combos` — fixed bundles (Cross-3)

```sql
CREATE TABLE IF NOT EXISTS combos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  name TEXT NOT NULL,                      -- "Play + Café", "Family Saturday", "Kid's Combo"
  description TEXT,
  cover_image_url TEXT,
  price_paise INTEGER NOT NULL,            -- combo bundled price (already discounted)
  inclusions JSONB NOT NULL,               -- {"session_minutes": 60, "menu_item_ids": [...], "drink_count": 2}
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 3. Catalog (Menus, Items, Workshops)

```sql
CREATE TABLE IF NOT EXISTS menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  brand TEXT NOT NULL CHECK (brand IN ('coffee','fit')),
  name TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id UUID NOT NULL REFERENCES menus(id),
  name TEXT NOT NULL,
  description TEXT,
  price_paise INTEGER NOT NULL CHECK (price_paise > 0),
  image_url TEXT,
  category TEXT,
  allergens TEXT[],
  is_available BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_menu_items_menu ON menu_items(menu_id, sort_order);
```

### Workshops + race-condition-safe spot decrement

```sql
CREATE TABLE IF NOT EXISTS workshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  title TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  duration_minutes INTEGER NOT NULL,
  age_group_min INTEGER,
  age_group_max INTEGER,
  capacity INTEGER NOT NULL CHECK (capacity > 0),
  spots_remaining INTEGER NOT NULL CHECK (spots_remaining >= 0),  -- atomic decrement guard
  spots_remaining_lock CHECK (spots_remaining <= capacity),
  price_paise INTEGER NOT NULL,
  primary_trait TEXT CHECK (primary_trait IN ('rafi','ellie','gerry','zena')),
  -- workshop type contributes XP to a specific trait (e.g. art workshop = creative = zena)
  xp_award INTEGER DEFAULT 100,
  status TEXT DEFAULT 'upcoming'
    CHECK (status IN ('upcoming','completed','cancelled')),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workshop_registrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id),
  family_id UUID NOT NULL REFERENCES families(id),
  child_id UUID NOT NULL REFERENCES children(id),
  payment_method TEXT NOT NULL,
  amount_paise INTEGER NOT NULL,
  attended BOOLEAN DEFAULT false,
  xp_credited BOOLEAN DEFAULT false,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,
  idempotency_key TEXT UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_wshop_reg_workshop ON workshop_registrations(workshop_id) WHERE cancelled_at IS NULL;
CREATE INDEX idx_wshop_reg_family ON workshop_registrations(family_id, created_at DESC);
```

---

## 4. Gamification

### `xp_events` — append-only ledger

```sql
CREATE TABLE IF NOT EXISTS xp_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES children(id),
  family_id UUID NOT NULL REFERENCES families(id),
  venue_id UUID REFERENCES venues(id),
  event_type TEXT NOT NULL CHECK (event_type IN (
    'play_session','reflection_split','auto_split',
    'healthy_bite','workshop',
    'birthday_hosted','birthday_guest','first_session',
    'streak_bonus','referral_bonus','birthday_bonus',
    'visit_milestone','manual_admin'
  )),
  -- Per-trait split: at least one of these is non-zero
  xp_rafi  INTEGER DEFAULT 0,
  xp_ellie INTEGER DEFAULT 0,
  xp_gerry INTEGER DEFAULT 0,
  xp_zena  INTEGER DEFAULT 0,
  reference_id UUID,                       -- session_id, workshop_reg_id, etc.
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_xp_child ON xp_events(child_id, created_at DESC);
CREATE INDEX idx_xp_session_ref ON xp_events(reference_id);
```

### `streak_records` — IST Mon–Sun weeks

```sql
CREATE TABLE IF NOT EXISTS streak_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID UNIQUE NOT NULL REFERENCES children(id),
  current_streak_weeks INTEGER DEFAULT 0,
  longest_streak_weeks INTEGER DEFAULT 0,
  total_visit_stars INTEGER DEFAULT 0,
  last_visit_date_ist DATE,                -- explicitly IST date
  last_streak_week_ist DATE,               -- ISO Mon of the last counted week, IST
  milestone_3_achieved BOOLEAN DEFAULT false,
  milestone_5_achieved BOOLEAN DEFAULT false,
  milestone_10_achieved BOOLEAN DEFAULT false,
  milestone_10_badge_mailed BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

### `hero_card_definitions` + `hero_card_collection`

```sql
CREATE TABLE IF NOT EXISTS hero_card_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  hero TEXT NOT NULL CHECK (hero IN ('rafi','ellie','gerry','zena')),
  is_rare BOOLEAN DEFAULT false,
  is_birthday_exclusive BOOLEAN DEFAULT false,
  image_url TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hero_card_collection (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES children(id),
  card_id UUID NOT NULL REFERENCES hero_card_definitions(id),
  earned_at TIMESTAMPTZ DEFAULT now(),
  session_id UUID REFERENCES sessions(id),
  birthday_booking_id UUID,                -- for birthday-exclusive cards
  UNIQUE(child_id, card_id)
);
```

### `gift_ladder` + `gift_redemptions`

```sql
CREATE TABLE IF NOT EXISTS gift_ladder (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  level_required INTEGER NOT NULL,         -- overall level
  gift_name TEXT NOT NULL,
  gift_description TEXT,
  delivery_method TEXT CHECK (delivery_method IN ('venue','mail')),
  is_active BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS gift_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID NOT NULL REFERENCES children(id),
  gift_id UUID NOT NULL REFERENCES gift_ladder(id),
  venue_id UUID NOT NULL REFERENCES venues(id),
  staff_pin_id UUID REFERENCES staff(id),
  issued_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(child_id, gift_id)
);
```

### Brand badges (Cross-5)

```sql
CREATE TABLE IF NOT EXISTS brand_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id),
  brand TEXT NOT NULL CHECK (brand IN ('play','coffee','fit','triple_threat')),
  -- 'triple_threat' = used all three brands in one visit
  tier TEXT NOT NULL CHECK (tier IN ('regular','champion','legend')),
  earned_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(family_id, brand, tier)
);

CREATE INDEX idx_brand_badges_family ON brand_badges(family_id);
```

### Visit milestones

```sql
CREATE TABLE IF NOT EXISTS visit_milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id),
  visit_count INTEGER NOT NULL,            -- 5, 10, 25, 50, 100, etc.
  reward_paise INTEGER,
  reward_xp_bonus INTEGER,
  awarded_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(family_id, visit_count)
);
```

---

## 5. Birthday — Booking Funnel (PRIMARY GOAL)

### `birthday_packages` — fixed tiers (Birthday-4)

```sql
CREATE TABLE IF NOT EXISTS birthday_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  name TEXT NOT NULL,                      -- "Basic", "Hero Adventure", "Legendary"
  tier TEXT NOT NULL CHECK (tier IN ('basic','hero_adventure','legendary','custom')),
  description TEXT,
  cover_image_url TEXT,
  gallery_image_urls TEXT[],
  price_paise INTEGER NOT NULL,
  duration_hours INTEGER DEFAULT 2,
  max_kids INTEGER NOT NULL,
  max_adults INTEGER NOT NULL,
  -- Inclusions structured for the package detail screen
  inclusions JSONB NOT NULL,
  -- Example: { "play_session": "2hr exclusive", "decor": "themed", "food_kids": "FIT party platter",
  --           "food_adults": "Coffee Diaries spread", "cake": "themed 1kg", "host": "1 trained host" }
  hero_theme TEXT CHECK (hero_theme IN ('rafi','ellie','gerry','zena','mixed')),
  deposit_paise INTEGER NOT NULL,          -- amount required to confirm a reservation
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### `birthday_availability` — admin-managed slot calendar

```sql
CREATE TABLE IF NOT EXISTS birthday_availability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  slot_date DATE NOT NULL,                 -- IST date
  slot_start_time TIME NOT NULL,
  slot_end_time TIME NOT NULL,
  is_blocked BOOLEAN DEFAULT false,        -- admin can block holidays/maintenance
  block_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(venue_id, slot_date, slot_start_time)
);

CREATE INDEX idx_bd_avail_lookup ON birthday_availability(venue_id, slot_date);
```

### `birthday_reservations` — hybrid in-app reserve + admin close (Birthday-2)

```sql
CREATE TABLE IF NOT EXISTS birthday_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  family_id UUID NOT NULL REFERENCES families(id),
  child_id UUID NOT NULL REFERENCES children(id),
  package_id UUID NOT NULL REFERENCES birthday_packages(id),
  -- Slot
  slot_date DATE NOT NULL,
  slot_start_time TIME NOT NULL,
  slot_end_time TIME NOT NULL,
  -- Guest counts
  num_kids INTEGER NOT NULL,
  num_adults INTEGER NOT NULL,
  -- Money
  package_price_paise INTEGER NOT NULL,
  deposit_paid_paise INTEGER DEFAULT 0,
  balance_paise INTEGER NOT NULL,
  total_paid_paise INTEGER DEFAULT 0,
  -- Pipeline state
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN (
      'reserved',         -- parent tapped Reserve, deposit pending
      'deposit_paid',     -- deposit hit Razorpay webhook → admin needs to confirm
      'confirmed',        -- admin closed the deal (called/WhatsApped)
      'completed',        -- party happened
      'cancelled',        -- before completion
      'no_show'
    )),
  -- Admin close
  assigned_admin UUID,
  admin_contacted_at TIMESTAMPTZ,
  admin_confirmed_at TIMESTAMPTZ,
  admin_notes TEXT,
  -- Source (analytics)
  triggered_by TEXT CHECK (triggered_by IN (
    'home_card',           -- persistent home card
    'day_minus_90',        -- birthday journey D-90
    'day_minus_60','day_minus_30','day_minus_14','day_minus_7','day_minus_3',
    'hero_progression',    -- stage transition trigger
    'manual_admin'
  )),
  -- Lifecycle
  reservation_expires_at TIMESTAMPTZ,       -- auto-cancel if deposit not paid in 24h
  cancelled_reason TEXT,
  cancelled_at TIMESTAMPTZ,
  -- Post-event amplification artefacts (generated post-completion)
  birthday_hero_card_id UUID REFERENCES hero_card_definitions(id),
  album_ready_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_bd_res_venue_date ON birthday_reservations(venue_id, slot_date);
CREATE INDEX idx_bd_res_family ON birthday_reservations(family_id, created_at DESC);
CREATE INDEX idx_bd_res_status ON birthday_reservations(status);
```

### `birthday_party_photos` — Staff app photo capture

```sql
CREATE TABLE IF NOT EXISTS birthday_party_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id UUID NOT NULL REFERENCES birthday_reservations(id),
  photo_url TEXT NOT NULL,                 -- Supabase Storage signed URL
  uploaded_by_pin UUID REFERENCES staff(id),
  is_in_album BOOLEAN DEFAULT true,        -- parent can hide individual photos
  caption TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_bd_photos_res ON birthday_party_photos(reservation_id, created_at);
```

### `birthday_journey_state` — D-90 onwards

```sql
CREATE TABLE IF NOT EXISTS birthday_journey_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id UUID UNIQUE NOT NULL REFERENCES children(id),
  reservation_id UUID REFERENCES birthday_reservations(id),
  birthday_year INTEGER NOT NULL,
  arc_type TEXT DEFAULT 'discovery'
    CHECK (arc_type IN ('discovery','reserved','hosted','adventure','paused')),
  -- 'discovery'  = no reservation yet, journey is converting
  -- 'reserved'   = reservation made; remaining touchpoints prep them for the event
  -- 'hosted'     = post-event recap arc
  -- 'adventure'  = no birthday booked here; gentle "have an adventure with us" arc
  comms_paused BOOLEAN DEFAULT false,
  -- Sent flags (mark BEFORE dispatch — see §13 of context)
  d_minus_90_sent BOOLEAN DEFAULT false,
  d_minus_60_sent BOOLEAN DEFAULT false,
  d_minus_30_sent BOOLEAN DEFAULT false,
  d_minus_14_sent BOOLEAN DEFAULT false,
  d_minus_7_sent  BOOLEAN DEFAULT false,
  d_minus_3_sent  BOOLEAN DEFAULT false,
  d_minus_1_sent  BOOLEAN DEFAULT false,
  d_zero_sent     BOOLEAN DEFAULT false,
  d_plus_1_sent   BOOLEAN DEFAULT false, -- thank-you / post-event
  d_plus_7_sent   BOOLEAN DEFAULT false, -- album ready
  hero_progression_trigger_sent BOOLEAN DEFAULT false,
  birthday_bonus_credited BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 6. Referrals, Refunds, Notifications

```sql
CREATE TABLE IF NOT EXISTS referral_conversions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_family_id UUID NOT NULL REFERENCES families(id),
  new_family_id UUID NOT NULL REFERENCES families(id),
  triggering_session_id UUID REFERENCES sessions(id),
  -- Calendar-month cap (gifter only)
  conversion_month DATE NOT NULL,          -- first day of month, IST
  gifter_wallet_credit_paise INTEGER NOT NULL,
  gifter_xp_bonus_rafi INTEGER NOT NULL,   -- "Brave Boost"
  new_family_wallet_credit_paise INTEGER NOT NULL,
  is_first_referral BOOLEAN DEFAULT false, -- triggers Brave Boost
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_referral_gifter_month ON referral_conversions(referrer_family_id, conversion_month);
CREATE INDEX idx_referral_new ON referral_conversions(new_family_id);

CREATE TABLE IF NOT EXISTS refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id),
  reference_id UUID NOT NULL,
  reference_type TEXT NOT NULL CHECK (reference_type IN ('session','order','workshop','birthday','manual')),
  amount_paise INTEGER NOT NULL,
  destination TEXT CHECK (destination IN ('wallet','razorpay')),
  initiated_by TEXT CHECK (initiated_by IN ('staff','admin','auto')),
  staff_pin_id UUID REFERENCES staff(id),  -- for staff ≤₹500 path
  status TEXT DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','processing','completed')),
  reason TEXT NOT NULL,
  approved_by UUID,
  approved_at TIMESTAMPTZ,
  razorpay_refund_id TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_refunds_status ON refunds(status, created_at);

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES families(id),
  type TEXT NOT NULL CHECK (type IN (
    'session_started','hydration_nudge','healthy_bite_earned',
    'grace_started','extend_nudge','session_closed','recap_ready',
    'reflection_prompt','reflection_auto_split',
    'order_confirmed','order_ready',
    'hero_card_received','stage_transition_imminent','stage_transition_revealed','level_up',
    'birthday_d_minus_90','birthday_d_minus_60','birthday_d_minus_30',
    'birthday_d_minus_14','birthday_d_minus_7','birthday_d_minus_3',
    'birthday_d_minus_1','birthday_d_zero',
    'birthday_d_plus_1','birthday_album_ready',
    'birthday_hero_progression_trigger',
    'referral_reward','first_referral_brave_boost',
    'wallet_topup','wallet_low_balance',
    'visit_milestone','streak_milestone',
    'refund_processed','reactivation_welcome',
    'workshop_reminder','workshop_cancelled',
    'pre_booking_reminder','pre_booking_expired',
    'while_you_wait_food'
  )),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  deep_link TEXT,
  is_read BOOLEAN DEFAULT false,
  reference_id UUID,
  push_sent_at TIMESTAMPTZ,                -- best-effort dispatch time
  push_status TEXT CHECK (push_status IN ('queued','dispatched','failed','skipped')),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_notifications_family ON notifications(family_id, created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(family_id, is_read) WHERE is_read = false;
```

### `hero_recaps` — recap card + reflection state

```sql
CREATE TABLE IF NOT EXISTS hero_recaps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID UNIQUE NOT NULL REFERENCES sessions(id),
  child_id UUID NOT NULL REFERENCES children(id),
  image_url TEXT,                          -- generated PNG (Edge Function)
  total_xp_pool INTEGER NOT NULL,          -- the XP this session earned
  reflection_status TEXT DEFAULT 'pending'
    CHECK (reflection_status IN ('pending','reflected','auto_split')),
  reflection_at TIMESTAMPTZ,
  reflection_deadline TIMESTAMPTZ,
  -- The trait moments the parent tapped
  moment_tags TEXT[],                      -- e.g. ['tried_something_new','helped_friend']
  rare_card_earned BOOLEAN DEFAULT false,
  rare_card_id UUID REFERENCES hero_card_definitions(id),
  generated_at TIMESTAMPTZ,
  notification_sent BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_hero_recaps_pending ON hero_recaps(reflection_deadline)
  WHERE reflection_status = 'pending';
```

### `reflection_moments` — admin-configurable cards (8–12)

```sql
CREATE TABLE IF NOT EXISTS reflection_moments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tag TEXT UNIQUE NOT NULL,                -- 'tried_something_new', 'helped_friend', etc.
  display_text TEXT NOT NULL,              -- "Tried something new"
  icon TEXT,                               -- phosphor icon name
  primary_trait TEXT NOT NULL CHECK (primary_trait IN ('rafi','ellie','gerry','zena')),
  xp_weight DECIMAL(3, 2) DEFAULT 1.0,     -- weight when summing tapped moments
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0
);
```

---

## 7. Staff, Audit, Configuration

### `staff` — shared tablet login + per-staff PINs

```sql
CREATE TABLE IF NOT EXISTS staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  name TEXT NOT NULL,
  phone TEXT,                              -- E.164
  pin_hash TEXT NOT NULL,                  -- bcrypt hash of 4-digit PIN
  role TEXT DEFAULT 'staff' CHECK (role IN ('staff','venue_manager','hq_admin')),
  is_active BOOLEAN DEFAULT true,
  last_pin_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_staff_venue ON staff(venue_id) WHERE is_active = true;
```

### `shift_logs` — end-of-shift cash reconciliation (B3)

```sql
CREATE TABLE IF NOT EXISTS shift_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  -- A shift is the tablet, not a person. The PIN audit_log lists who did what during it.
  shift_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  shift_end TIMESTAMPTZ,
  expected_cash_paise INTEGER,             -- sum of cash transactions during shift
  counted_cash_paise INTEGER,              -- entered by staff at end-of-shift
  discrepancy_paise INTEGER GENERATED ALWAYS AS (counted_cash_paise - expected_cash_paise) STORED,
  notes TEXT,
  closed_by_pin UUID REFERENCES staff(id),
  status TEXT DEFAULT 'open' CHECK (status IN ('open','closed','disputed')),
  summary JSONB DEFAULT '{}'
);

CREATE INDEX idx_shift_open ON shift_logs(venue_id) WHERE status = 'open';
```

### `audit_log` — per-staff-PIN trail

```sql
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID,                           -- staff.id (if PIN); auth.users.id (if admin); NULL for system
  actor_type TEXT NOT NULL CHECK (actor_type IN ('staff','admin','system','customer')),
  action TEXT NOT NULL,                    -- 'wallet.credit','session.create','refund.approve', etc.
  entity_type TEXT NOT NULL,
  entity_id UUID,
  old_value JSONB,
  new_value JSONB,
  venue_id UUID,
  ip_address TEXT,                         -- admin web actions
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_actor ON audit_log(actor_id, created_at DESC);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
```

### `venue_config` — all configurable parameters

```sql
CREATE TABLE IF NOT EXISTS venue_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID UNIQUE NOT NULL REFERENCES venues(id),

  -- Pricing (paise)
  price_1hr_paise INTEGER DEFAULT 80000,         -- ₹800
  price_2hr_paise INTEGER DEFAULT 110000,        -- ₹1,100
  price_extension_paise INTEGER DEFAULT 30000,   -- ₹300/hr
  overtime_per_min_paise INTEGER DEFAULT 500,    -- ₹5/min

  -- Session rules
  grace_period_minutes INTEGER DEFAULT 10,
  grace_max_minutes INTEGER DEFAULT 30,           -- hard cap; auto-close beyond
  extend_nudge_after_minutes INTEGER DEFAULT 3,
  qr_expiry_minutes INTEGER DEFAULT 15,

  -- Loyalty
  cashback_percent DECIMAL(5,2) DEFAULT 7.00,    -- Diaries Coins on wallet orders
  reflection_window_hours INTEGER DEFAULT 24,    -- before auto-split

  -- XP defaults
  xp_per_minute INTEGER DEFAULT 1,
  xp_healthy_bite INTEGER DEFAULT 20,
  xp_workshop INTEGER DEFAULT 100,
  xp_birthday_host INTEGER DEFAULT 1000,
  xp_birthday_guest INTEGER DEFAULT 50,
  xp_first_session INTEGER DEFAULT 50,
  xp_streak_bonus INTEGER DEFAULT 25,
  xp_referral_bonus_rafi INTEGER DEFAULT 200,    -- "Brave Boost"
  xp_birthday_bonus INTEGER DEFAULT 100,

  -- Overall level thresholds (sum of trait XP)
  level_thresholds JSONB DEFAULT '[0,100,250,450,700,1000,1400,1900,2500,3200,4000,4900,5900,7000,8200,9500,10900,12400,14000,15700,17500]',

  -- Per-trait stage thresholds (Stage = Seedling/Explorer/Adventurer/Champion/Legend)
  trait_stage_thresholds JSONB DEFAULT '[0,50,150,350,700]',

  -- Referrals
  referral_gifter_credit_paise INTEGER DEFAULT 20000,         -- ₹200
  referral_new_family_credit_paise INTEGER DEFAULT 10000,     -- ₹100
  referral_monthly_cap INTEGER DEFAULT 5,                     -- gifter only, calendar month

  -- Wallet thresholds
  low_balance_threshold_paise INTEGER DEFAULT 20000,           -- ₹200
  reactivation_credit_paise INTEGER DEFAULT 20000,             -- ₹200 welcome-back
  reactivation_credit_expiry_days INTEGER DEFAULT 90,

  -- Top-up offers (JSON)
  topup_offers JSONB DEFAULT '[
    {"amount_paise":50000,"credit_paise":50000,"label":"","badge":""},
    {"amount_paise":100000,"credit_paise":100000,"label":"","badge":""},
    {"amount_paise":300000,"credit_paise":350000,"label":"Most Popular","badge":"🔥"},
    {"amount_paise":400000,"credit_paise":500000,"label":"Best Value","badge":"⭐"}
  ]',

  -- Visit-frequency rewards
  visit_milestones JSONB DEFAULT '[
    {"visits":5,"reward_paise":10000,"reward_xp":50},
    {"visits":10,"reward_paise":20000,"reward_xp":100},
    {"visits":25,"reward_paise":50000,"reward_xp":250},
    {"visits":50,"reward_paise":100000,"reward_xp":500},
    {"visits":100,"reward_paise":200000,"reward_xp":1000}
  ]',

  -- Pre-booking
  pre_booking_hold_percent DECIMAL(5,2) DEFAULT 50.00,        -- 50% hold
  pre_booking_grace_minutes INTEGER DEFAULT 30,               -- after scheduled_start

  -- App version control (per-platform)
  ios_min_supported_version TEXT DEFAULT '1.0.0',
  ios_latest_version TEXT DEFAULT '1.0.0',
  android_min_supported_version TEXT DEFAULT '1.0.0',
  android_latest_version TEXT DEFAULT '1.0.0',

  -- Wall of Legends
  wall_of_legends_enabled BOOLEAN DEFAULT true,
  wall_of_legends_anonymise BOOLEAN DEFAULT true,             -- 'A.' instead of 'Aarav'

  -- Two-person approval for debits
  require_two_person_for_debit BOOLEAN DEFAULT false,         -- defaults OFF for solo admin

  updated_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 8. Reactivation Campaign — One-Time Module

### `reactivation_contacts`

```sql
CREATE TABLE IF NOT EXISTS reactivation_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT UNIQUE NOT NULL,              -- E.164
  name TEXT,                               -- best-effort, may be null
  last_visit_date DATE,
  visit_count INTEGER,
  -- Credit setup
  credit_paise INTEGER NOT NULL DEFAULT 20000,
  credit_expires_at TIMESTAMPTZ NOT NULL,
  -- SMS dispatch
  sms_status TEXT DEFAULT 'pending'
    CHECK (sms_status IN ('pending','queued','dispatched','failed','skipped')),
  sms_msg91_id TEXT,
  sms_dispatched_at TIMESTAMPTZ,
  sms_failure_reason TEXT,
  -- Redemption
  redeemed_at TIMESTAMPTZ,
  redeemed_family_id UUID REFERENCES families(id),
  -- Import context
  imported_at TIMESTAMPTZ DEFAULT now(),
  imported_batch_id UUID,
  is_paused BOOLEAN DEFAULT false
);

CREATE INDEX idx_reactivation_phone ON reactivation_contacts(phone);
CREATE INDEX idx_reactivation_pending_sms ON reactivation_contacts(sms_status)
  WHERE sms_status = 'pending';
CREATE INDEX idx_reactivation_unredeemed ON reactivation_contacts(redeemed_at)
  WHERE redeemed_at IS NULL;
```

---

## 9. Wall of Legends — light social proof

```sql
CREATE TABLE IF NOT EXISTS wall_of_legends_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id UUID NOT NULL REFERENCES venues(id),
  ist_date DATE NOT NULL,
  total_families INTEGER DEFAULT 0,
  total_sessions INTEGER DEFAULT 0,
  stage_transitions INTEGER DEFAULT 0,
  birthdays_celebrated INTEGER DEFAULT 0,
  workshops_attended INTEGER DEFAULT 0,
  hero_cards_earned INTEGER DEFAULT 0,
  -- Anonymised highlights (rendered to feed)
  highlights JSONB DEFAULT '[]',
  -- e.g. [{"text":"A.'s Rafi reached Champion","timestamp":"...","trait":"rafi"}]
  computed_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(venue_id, ist_date)
);

CREATE INDEX idx_wol_venue_date ON wall_of_legends_daily(venue_id, ist_date DESC);
```

---

## 10. System Health & Monitoring

```sql
CREATE TABLE IF NOT EXISTS reconciliation_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('razorpay','manual')),
  ran_at TIMESTAMPTZ DEFAULT now(),
  payments_checked INTEGER DEFAULT 0,
  discrepancies_found INTEGER DEFAULT 0,
  total_corrected_paise INTEGER DEFAULT 0,
  details JSONB DEFAULT '{}',
  status TEXT CHECK (status IN ('success','partial','failed'))
);

CREATE TABLE IF NOT EXISTS system_health_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_at TIMESTAMPTZ DEFAULT now(),
  api_p95_ms INTEGER,
  edge_function_failure_rate DECIMAL(5,2),
  push_delivery_rate DECIMAL(5,2),
  active_sessions INTEGER,
  reconciliation_health TEXT,              -- 'green','yellow','red'
  notes TEXT
);
```

---

## 11. Row-Level Security

All tables get RLS enabled. Policies use a helper function for clarity:

```sql
-- Helper: current authenticated family_id (= auth.uid())
CREATE OR REPLACE FUNCTION auth_family_id() RETURNS UUID
LANGUAGE sql STABLE AS $$ SELECT auth.uid() $$;

-- Enable RLS on all customer-facing tables
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_extensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_pre_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE xp_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_card_collection ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE workshop_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_recaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE brand_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;

-- Customer policies (own data only)
CREATE POLICY families_self ON families
  FOR ALL USING (id = auth_family_id());

CREATE POLICY children_family ON children
  FOR ALL USING (family_id = auth_family_id());

CREATE POLICY wallets_family ON wallets
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY wallet_tx_family ON wallet_transactions
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY sessions_family ON sessions
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY pre_bookings_family ON session_pre_bookings
  FOR ALL USING (family_id = auth_family_id());

CREATE POLICY orders_family ON orders
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY order_items_family ON order_items
  FOR SELECT USING (
    order_id IN (SELECT id FROM orders WHERE family_id = auth_family_id())
  );

CREATE POLICY notifications_family ON notifications
  FOR ALL USING (family_id = auth_family_id());

CREATE POLICY xp_events_family ON xp_events
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY streak_family ON streak_records
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

CREATE POLICY hero_cards_family ON hero_card_collection
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

CREATE POLICY bd_res_family ON birthday_reservations
  FOR ALL USING (family_id = auth_family_id());

CREATE POLICY wshop_reg_family ON workshop_registrations
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY hero_recaps_family ON hero_recaps
  FOR ALL USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

CREATE POLICY brand_badges_family ON brand_badges
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY visit_milestones_family ON visit_milestones
  FOR SELECT USING (family_id = auth_family_id());

CREATE POLICY refunds_family ON refunds
  FOR SELECT USING (family_id = auth_family_id());

-- Public-read tables (no RLS or permissive policies):
-- venues, venue_config, menus, menu_items, workshops, hero_card_definitions,
-- gift_ladder, combos, birthday_packages, birthday_availability, reflection_moments,
-- wall_of_legends_daily

-- All RPC functions run with SECURITY DEFINER and validate ownership in the function body.
-- All Edge Functions use the service_role key (bypasses RLS) and validate within.
```

---

## 12. Seed Data — Required for v1 launch

```sql
-- One venue
INSERT INTO venues (id, name, address, phone, whatsapp, max_capacity)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Play Diaries Kondapur',
  'Kondapur, Hyderabad, Telangana',
  '+919876543210',                                -- placeholder, update before launch
  '+919876543210',
  50
) ON CONFLICT (id) DO NOTHING;

-- Default venue_config
INSERT INTO venue_config (venue_id) VALUES ('00000000-0000-0000-0000-000000000001')
ON CONFLICT (venue_id) DO NOTHING;

-- Default reflection moments (8 cards, 2 per trait)
INSERT INTO reflection_moments (tag, display_text, primary_trait, sort_order) VALUES
  ('tried_something_new',  'Tried something new',     'rafi',  10),
  ('took_a_leap',          'Took a leap',             'rafi',  20),
  ('shared_with_friend',   'Shared with a friend',    'ellie', 30),
  ('helped_a_friend',      'Helped a friend',         'ellie', 40),
  ('asked_questions',      'Asked lots of questions', 'gerry', 50),
  ('explored_new_corner',  'Explored a new corner',   'gerry', 60),
  ('made_up_a_game',       'Made up a game',          'zena',  70),
  ('drew_or_built',        'Drew or built something', 'zena',  80)
ON CONFLICT (tag) DO NOTHING;

-- 3 birthday packages (founder will refine pricing/inclusions)
INSERT INTO birthday_packages (venue_id, name, tier, description, price_paise, max_kids, max_adults, deposit_paise, hero_theme, inclusions, sort_order) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Birthday Basics',    'basic',          'A simple celebration: 2hr exclusive play time, themed decor, kids meal.',          1500000, 15, 10, 500000, 'mixed', '{"play_session":"2hr","decor":"basic","food_kids":"FIT meal","cake":"add-on"}', 10),
  ('00000000-0000-0000-0000-000000000001', 'Hero Adventure',     'hero_adventure', 'Full Hero theme experience: 2hr play, themed decor, FIT party platter, Coffee Diaries adult spread, themed cake, 1 host.', 2500000, 20, 15, 800000, 'rafi', '{"play_session":"2hr","decor":"hero_themed","food_kids":"FIT party platter","food_adults":"Coffee Diaries spread","cake":"themed 1kg","host":"1"}', 20),
  ('00000000-0000-0000-0000-000000000001', 'Legendary Birthday', 'legendary',      'The full experience: 3hr exclusive venue, full theme execution, premium food, themed cake, 2 hosts, photo album.', 4500000, 25, 20, 1500000, 'mixed', '{"play_session":"3hr exclusive","decor":"premium themed","food_kids":"FIT premium platter","food_adults":"Coffee Diaries premium","cake":"themed 2kg","host":"2","extras":"photo album"}', 30)
ON CONFLICT DO NOTHING;
```

---

## Acceptance Test (run after migration)

```sql
-- 1. Wallet auto-creation
INSERT INTO families (id, phone, name)
VALUES (gen_random_uuid(), '+919999999999', 'Test Family');
-- Expect: 1 wallet row created automatically. Assert with:
SELECT COUNT(*) FROM wallets WHERE family_id = (SELECT id FROM families WHERE phone='+919999999999');
-- Should be 1

-- 2. Phone format guard
INSERT INTO families (id, phone, name)
VALUES (gen_random_uuid(), '9999999999', 'Bad Phone');  -- Should RAISE EXCEPTION
INSERT INTO families (id, phone, name)
VALUES (gen_random_uuid(), '+19876543210', 'Bad Phone'); -- US prefix; Should RAISE EXCEPTION

-- 3. RLS isolation
-- Sign in as user A, query families: only A's row returns.
-- Sign in as user B, query families: only B's row returns.

-- 4. Idempotency uniqueness
-- Insert two wallet_transactions with same idempotency_key — second should fail with UNIQUE violation.

-- Cleanup:
DELETE FROM families WHERE phone IN ('+919999999999');
```

---

## Open Items for Founder

- [ ] Confirm three birthday package prices (₹15,000 / ₹25,000 / ₹45,000 placeholders)
- [ ] Confirm the 8 reflection moment cards (or expand to 12)
- [ ] Update Kondapur venue address + real phone/WhatsApp before launch
- [ ] Decide if `coins_lifetime` should reset annually for "Coffee Regular" badge logic
