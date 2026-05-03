-- ===========================================================================
--  Diaries Club v1.5 — 0001_initial_schema.sql
--  Initial schema + RLS + triggers + storage buckets + seed data.
--
--  Idempotent. Safe to re-run on a fresh or existing project:
--    - CREATE TABLE IF NOT EXISTS
--    - CREATE OR REPLACE FUNCTION
--    - DROP TRIGGER / DROP POLICY then CREATE
--    - ALTER TABLE ADD CONSTRAINT inside DO blocks (catch duplicate_object)
--    - INSERT ... ON CONFLICT DO NOTHING
--
--  Tables are created in dependency order (parents before children).
--  Two circular references resolved with deferred ALTER TABLE:
--    sessions.pre_booking_id <-> session_pre_bookings.redeemed_session_id
--
--  Money:        all amounts in INTEGER paise (1 rupee = 100 paise).
--  Time:         all timestamps TIMESTAMPTZ. IST date math performed in app/RPC.
--  IDs:          UUID for all primary keys.
--  Phone:        E.164 only, validated by trigger on families.
--  RLS:          enabled on every table. Customer-facing tables have policies;
--                staff/admin/system tables are deny-by-default and accessed
--                only via SECURITY DEFINER RPCs or the service_role key.
--
--  Rollback (manual): DROP SCHEMA public CASCADE; CREATE SCHEMA public; then
--                     drop storage buckets via dashboard or storage API.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
--  Helper functions
-- ---------------------------------------------------------------------------

-- Returns auth.uid() (the family_id of the calling user).
CREATE OR REPLACE FUNCTION auth_family_id() RETURNS UUID
LANGUAGE sql STABLE AS $$ SELECT auth.uid() $$;

-- Generic updated_at maintainer.
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- E.164 phone validator. Skipped when row is anonymised (placeholder phones
-- inserted by the anonymisation RPC may not match the strict pattern).
CREATE OR REPLACE FUNCTION validate_phone_e164() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(NEW.is_anonymised, false) THEN
    RETURN NEW;
  END IF;
  IF NEW.phone !~ '^\+91[6-9][0-9]{9}$' THEN
    RAISE EXCEPTION 'invalid_phone_format: must be E.164 +91XXXXXXXXXX';
  END IF;
  RETURN NEW;
END $$;

-- Wallet auto-create on family insert.
CREATE OR REPLACE FUNCTION create_wallet_for_family() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO wallets (family_id) VALUES (NEW.id)
  ON CONFLICT (family_id) DO NOTHING;
  RETURN NEW;
END $$;

-- ===========================================================================
--  TABLES (dependency order)
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  venues
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS venues (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  address         TEXT,
  phone           TEXT,                              -- E.164
  whatsapp        TEXT,                              -- E.164
  max_capacity    INTEGER DEFAULT 50,
  is_active       BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  families  (id == auth.users.id)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS families (
  -- families.id MUST equal auth.users.id. FK + cascade ensures referential
  -- integrity with Supabase Auth deletions.
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  phone               TEXT NOT NULL,                 -- E.164; uniqueness via partial index below
  name                TEXT NOT NULL,
  email               TEXT,                          -- optional, for GST invoices
  referral_code       TEXT UNIQUE NOT NULL DEFAULT upper(substr(md5(random()::text), 1, 8)),
  marketing_consent   BOOLEAN DEFAULT false,
  fcm_token           TEXT,
  fcm_platform        TEXT CHECK (fcm_platform IN ('ios','android','web')),
  app_version         TEXT,                          -- e.g. "1.0.0+1"
  is_cafe_only        BOOLEAN DEFAULT false,
  has_children        BOOLEAN DEFAULT false,
  -- DPDP soft-delete / anonymisation
  deleted_at          TIMESTAMPTZ,
  is_anonymised       BOOLEAN DEFAULT false,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_active_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Phone unique only for live (non-deleted) rows. Allows reuse after anonymisation.
CREATE UNIQUE INDEX IF NOT EXISTS idx_families_phone_unique
  ON families(phone) WHERE deleted_at IS NULL;
CREATE INDEX        IF NOT EXISTS idx_families_phone
  ON families(phone) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
--  children
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS children (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id               UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  name                    TEXT NOT NULL,
  date_of_birth           DATE NOT NULL,
  photo_url               TEXT,
  delivery_address        TEXT,                      -- gift mailing
  favourite_hero          TEXT NOT NULL DEFAULT 'ellie'
                          CHECK (favourite_hero IN ('rafi','ellie','gerry','zena')),
  -- per-trait XP
  xp_rafi                 INTEGER NOT NULL DEFAULT 0,
  xp_ellie                INTEGER NOT NULL DEFAULT 0,
  xp_gerry                INTEGER NOT NULL DEFAULT 0,
  xp_zena                 INTEGER NOT NULL DEFAULT 0,
  -- per-trait stage (denormalised; recomputed by xp_credit RPC)
  stage_rafi              TEXT NOT NULL DEFAULT 'seedling'
                          CHECK (stage_rafi  IN ('seedling','explorer','adventurer','champion','legend')),
  stage_ellie             TEXT NOT NULL DEFAULT 'seedling'
                          CHECK (stage_ellie IN ('seedling','explorer','adventurer','champion','legend')),
  stage_gerry             TEXT NOT NULL DEFAULT 'seedling'
                          CHECK (stage_gerry IN ('seedling','explorer','adventurer','champion','legend')),
  stage_zena              TEXT NOT NULL DEFAULT 'seedling'
                          CHECK (stage_zena  IN ('seedling','explorer','adventurer','champion','legend')),
  total_xp                INTEGER NOT NULL DEFAULT 0,
  current_level           INTEGER NOT NULL DEFAULT 1,
  current_overall_stage   TEXT NOT NULL DEFAULT 'seedling'
                          CHECK (current_overall_stage IN ('seedling','explorer','adventurer','champion','legend')),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_children_family ON children(family_id);

-- ---------------------------------------------------------------------------
--  wallets  (auto-created by trigger on families insert)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id       UUID UNIQUE NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  balance_paise   INTEGER NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
  -- Diaries Coins are bonus rupees in the same wallet. coins_lifetime is a
  -- never-reset display counter ("you've earned 1,200 coins"); spendable
  -- amount is balance_paise.
  coins_lifetime  INTEGER NOT NULL DEFAULT 0 CHECK (coins_lifetime >= 0),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  wallet_transactions  (append-only ledger)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id               UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  type                    TEXT NOT NULL CHECK (type IN (
    'topup','bonus','session_debit','extension_debit',
    'order_debit','workshop_debit','birthday_deposit_debit','birthday_balance_debit',
    'refund','coins_credit','coins_debit',
    'reactivation_credit','visit_bonus','streak_milestone',
    'manual_credit','manual_debit'
  )),
  amount_paise            INTEGER NOT NULL,           -- signed: +credit, -debit
  balance_after_paise     INTEGER NOT NULL,
  coins_amount            INTEGER NOT NULL DEFAULT 0,
  payment_method          TEXT CHECK (payment_method IN ('wallet','cash','razorpay','system')),
  razorpay_payment_id     TEXT,
  reference_id            UUID,
  reference_type          TEXT,
  idempotency_key         TEXT UNIQUE,
  metadata                JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_family
  ON wallet_transactions(family_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_idempotency
  ON wallet_transactions(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_wallet_tx_razorpay
  ON wallet_transactions(razorpay_payment_id) WHERE razorpay_payment_id IS NOT NULL;

-- ---------------------------------------------------------------------------
--  staff  (shared tablet login + per-staff PIN)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  name                TEXT NOT NULL,
  phone               TEXT,                          -- E.164
  pin_hash            TEXT NOT NULL,                 -- bcrypt of 4-digit PIN
  role                TEXT NOT NULL DEFAULT 'staff'
                      CHECK (role IN ('staff','venue_manager','hq_admin')),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  last_pin_used_at    TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_staff_venue ON staff(venue_id) WHERE is_active = true;

-- ---------------------------------------------------------------------------
--  venue_config  (admin-tunable economy / toggles / contact info)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS venue_config (
  id                                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                                    UUID UNIQUE NOT NULL REFERENCES venues(id) ON DELETE CASCADE,

  -- ─── PRICING ───────────────────────────────────────────────────────────
  session_1hr_price_paise                     INTEGER      NOT NULL DEFAULT 80000,
  session_2hr_price_paise                     INTEGER      NOT NULL DEFAULT 110000,
  session_extension_per_hour_paise            INTEGER      NOT NULL DEFAULT 30000,
  overtime_per_min_paise                      INTEGER      NOT NULL DEFAULT 500,
  gst_percent                                 NUMERIC(5,2) NOT NULL DEFAULT 5.00,

  -- ─── WALLET & REWARDS ─────────────────────────────────────────────────
  cashback_percent                            NUMERIC(5,2) NOT NULL DEFAULT 7.00,
  topup_offers                                JSONB        NOT NULL DEFAULT '[
    {"amount_paise":50000,  "bonus_paise":0,      "label":"",            "badge":""},
    {"amount_paise":100000, "bonus_paise":0,      "label":"",            "badge":""},
    {"amount_paise":300000, "bonus_paise":50000,  "label":"Most Popular","badge":"🔥"},
    {"amount_paise":400000, "bonus_paise":100000, "label":"Best Value",  "badge":"⭐"}
  ]'::jsonb,
  reactivation_credit_paise                   INTEGER      NOT NULL DEFAULT 20000,
  reactivation_expiry_days                    INTEGER      NOT NULL DEFAULT 90,
  low_balance_threshold_paise                 INTEGER      NOT NULL DEFAULT 30000,
  referral_gifter_credit_paise                INTEGER      NOT NULL DEFAULT 20000,
  referral_new_family_credit_paise            INTEGER      NOT NULL DEFAULT 10000,
  referral_monthly_cap_paise                  INTEGER      NOT NULL DEFAULT 100000,
  visit_milestones                            JSONB        NOT NULL DEFAULT '[
    {"visits":5,  "reward_paise":10000,  "reward_xp":50},
    {"visits":10, "reward_paise":20000,  "reward_xp":100},
    {"visits":25, "reward_paise":50000,  "reward_xp":250},
    {"visits":50, "reward_paise":100000, "reward_xp":500},
    {"visits":100,"reward_paise":200000, "reward_xp":1000}
  ]'::jsonb,

  -- ─── TIME WINDOWS ─────────────────────────────────────────────────────
  session_grace_period_minutes                INTEGER      NOT NULL DEFAULT 5,
  session_grace_max_minutes                   INTEGER      NOT NULL DEFAULT 30,
  session_extend_nudge_after_minutes          INTEGER      NOT NULL DEFAULT 10,
  qr_validity_minutes                         INTEGER      NOT NULL DEFAULT 15,
  otp_validity_minutes                        INTEGER      NOT NULL DEFAULT 10,
  reflection_window_hours                     INTEGER      NOT NULL DEFAULT 24,
  pre_booking_hold_percent                    NUMERIC(5,2) NOT NULL DEFAULT 50.00,
  pre_booking_grace_minutes                   INTEGER      NOT NULL DEFAULT 30,

  -- ─── XP RULES (DANGER ZONE — super_admin only in admin web) ──────────
  xp_per_session_minute                       INTEGER      NOT NULL DEFAULT 1,
  xp_reflection_participation                 INTEGER      NOT NULL DEFAULT 25,
  xp_healthy_bite                             INTEGER      NOT NULL DEFAULT 20,
  xp_workshop_attendance                      INTEGER      NOT NULL DEFAULT 100,
  xp_birthday_hosted                          INTEGER      NOT NULL DEFAULT 1000,  -- split equally across 4 traits
  xp_birthday_guest                           INTEGER      NOT NULL DEFAULT 50,
  xp_first_session                            INTEGER      NOT NULL DEFAULT 50,
  xp_streak_bonus                             INTEGER      NOT NULL DEFAULT 25,
  xp_referral_bonus_rafi                      INTEGER      NOT NULL DEFAULT 200,   -- "Brave Boost"
  xp_birthday_bonus                           INTEGER      NOT NULL DEFAULT 100,
  stage_thresholds_per_trait                  JSONB        NOT NULL DEFAULT
    '[0,50,150,350,700]'::jsonb,
  level_thresholds                            JSONB        NOT NULL DEFAULT
    '[0,100,250,450,700,1000,1400,1900,2500,3200,4000,4900,5900,7000,8200,9500,10900,12400,14000,15700,17500]'::jsonb,

  -- ─── BIRTHDAY (mirrors birthday_packages defaults; admin can edit either) ─
  birthday_basics_price_paise                 INTEGER      NOT NULL DEFAULT 1500000,
  birthday_basics_deposit_paise               INTEGER      NOT NULL DEFAULT 500000,
  birthday_hero_adventure_price_paise         INTEGER      NOT NULL DEFAULT 2500000,
  birthday_hero_adventure_deposit_paise       INTEGER      NOT NULL DEFAULT 800000,
  birthday_legendary_price_paise              INTEGER      NOT NULL DEFAULT 4500000,
  birthday_legendary_deposit_paise            INTEGER      NOT NULL DEFAULT 1500000,
  birthday_reservation_autocancel_hours       INTEGER      NOT NULL DEFAULT 72,

  -- ─── OPERATIONS ───────────────────────────────────────────────────────
  staff_refund_cap_paise                      INTEGER      NOT NULL DEFAULT 50000,
  cash_discrepancy_alert_threshold_paise      INTEGER      NOT NULL DEFAULT 10000,
  max_sessions_per_family_per_day             INTEGER      NOT NULL DEFAULT 3,
  session_force_close_after_grace_minutes     INTEGER      NOT NULL DEFAULT 30,

  -- ─── TOGGLES ──────────────────────────────────────────────────────────
  wall_of_legends_enabled                     BOOLEAN      NOT NULL DEFAULT true,
  wall_of_legends_anonymise                   BOOLEAN      NOT NULL DEFAULT true,
  marketing_opt_in_default                    BOOLEAN      NOT NULL DEFAULT false,
  require_two_person_for_debit                BOOLEAN      NOT NULL DEFAULT false,
  healthy_bite_enabled                        BOOLEAN      NOT NULL DEFAULT true,
  workshops_enabled                           BOOLEAN      NOT NULL DEFAULT true,
  birthday_booking_enabled                    BOOLEAN      NOT NULL DEFAULT true,

  -- ─── APP VERSION CONTROL ──────────────────────────────────────────────
  ios_min_supported_version                   TEXT         NOT NULL DEFAULT '1.0.0',
  ios_latest_version                          TEXT         NOT NULL DEFAULT '1.0.0',
  android_min_supported_version               TEXT         NOT NULL DEFAULT '1.0.0',
  android_latest_version                      TEXT         NOT NULL DEFAULT '1.0.0',
  force_update_message                        TEXT         NOT NULL DEFAULT 'Please update Diaries Club to continue.',

  -- ─── CONTACT INFO ─────────────────────────────────────────────────────
  whatsapp_support_phone                      TEXT         NOT NULL DEFAULT '+919876543210',
  venue_phone                                 TEXT         NOT NULL DEFAULT '+919876543210',
  venue_address                               TEXT         NOT NULL DEFAULT 'Kondapur, Hyderabad, Telangana',
  venue_email                                 TEXT         NOT NULL DEFAULT 'hello@diariesclub.com',
  venue_maps_url                              TEXT         NOT NULL DEFAULT '',

  -- ─── CONTENT URLS ─────────────────────────────────────────────────────
  privacy_policy_url                          TEXT         NOT NULL DEFAULT 'https://diariesclub.com/privacy',
  terms_of_service_url                        TEXT         NOT NULL DEFAULT 'https://diariesclub.com/terms',
  refund_policy_url                           TEXT         NOT NULL DEFAULT 'https://diariesclub.com/refund',
  marketing_site_url                          TEXT         NOT NULL DEFAULT 'https://diariesclub.com',

  updated_at                                  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  menus + menu_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS menus (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id    UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  brand       TEXT NOT NULL CHECK (brand IN ('coffee','fit')),
  name        TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS menu_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id       UUID NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  price_paise   INTEGER NOT NULL CHECK (price_paise > 0),
  image_url     TEXT,
  category      TEXT,
  allergens     TEXT[],
  is_available  BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_menu_items_menu ON menu_items(menu_id, sort_order);

-- ---------------------------------------------------------------------------
--  combos
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS combos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id          UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  cover_image_url   TEXT,
  price_paise       INTEGER NOT NULL CHECK (price_paise > 0),
  inclusions        JSONB NOT NULL,                 -- {"session_minutes":60,"menu_item_ids":[...]}
  is_active         BOOLEAN NOT NULL DEFAULT true,
  sort_order        INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  workshops + registrations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS workshops (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  title               TEXT NOT NULL,
  description         TEXT,
  cover_image_url     TEXT,
  scheduled_at        TIMESTAMPTZ NOT NULL,
  duration_minutes    INTEGER NOT NULL,
  age_group_min       INTEGER,
  age_group_max       INTEGER,
  capacity            INTEGER NOT NULL CHECK (capacity > 0),
  spots_remaining     INTEGER NOT NULL CHECK (spots_remaining >= 0),
  price_paise         INTEGER NOT NULL CHECK (price_paise >= 0),
  primary_trait       TEXT CHECK (primary_trait IN ('rafi','ellie','gerry','zena')),
  xp_award            INTEGER NOT NULL DEFAULT 100,
  status              TEXT NOT NULL DEFAULT 'upcoming'
                      CHECK (status IN ('upcoming','completed','cancelled')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT spots_remaining_lock CHECK (spots_remaining <= capacity)
);

CREATE TABLE IF NOT EXISTS workshop_registrations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id           UUID NOT NULL REFERENCES workshops(id) ON DELETE RESTRICT,
  family_id             UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  child_id              UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
  payment_method        TEXT NOT NULL,
  amount_paise          INTEGER NOT NULL,
  attended              BOOLEAN NOT NULL DEFAULT false,
  xp_credited           BOOLEAN NOT NULL DEFAULT false,
  cancelled_at          TIMESTAMPTZ,
  cancellation_reason   TEXT,
  idempotency_key       TEXT UNIQUE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wshop_reg_workshop
  ON workshop_registrations(workshop_id) WHERE cancelled_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_wshop_reg_family
  ON workshop_registrations(family_id, created_at DESC);

-- ---------------------------------------------------------------------------
--  session_pre_bookings  (FK to sessions added later)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_pre_bookings (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id              UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  family_id             UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  child_id              UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  scheduled_start       TIMESTAMPTZ NOT NULL,
  duration_minutes      INTEGER NOT NULL CHECK (duration_minutes IN (60, 120)),
  amount_paise          INTEGER NOT NULL,
  hold_amount_paise     INTEGER NOT NULL,
  status                TEXT NOT NULL DEFAULT 'reserved'
                        CHECK (status IN ('reserved','redeemed','expired','cancelled')),
  redeemed_session_id   UUID,                         -- FK added after sessions exists
  expires_at            TIMESTAMPTZ NOT NULL,
  cancellation_reason   TEXT,
  idempotency_key       TEXT UNIQUE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pre_bookings_venue_upcoming
  ON session_pre_bookings(venue_id, scheduled_start) WHERE status = 'reserved';
CREATE INDEX IF NOT EXISTS idx_pre_bookings_family
  ON session_pre_bookings(family_id, scheduled_start DESC);

-- ---------------------------------------------------------------------------
--  sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                    UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  family_id                   UUID REFERENCES families(id) ON DELETE SET NULL,
  child_id                    UUID REFERENCES children(id) ON DELETE SET NULL,
  staff_pin_id                UUID REFERENCES staff(id),
  duration_minutes            INTEGER NOT NULL CHECK (duration_minutes IN (60, 120)),
  amount_paise                INTEGER NOT NULL,
  payment_method              TEXT NOT NULL CHECK (payment_method IN ('wallet','cash','razorpay')),
  status                      TEXT NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active','grace','completed','void','auto_closed')),
  started_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at                  TIMESTAMPTZ NOT NULL,
  grace_started_at            TIMESTAMPTZ,
  grace_force_close_at        TIMESTAMPTZ,           -- expires_at + grace_max_minutes
  completed_at                TIMESTAMPTZ,
  healthy_bite_earned         BOOLEAN NOT NULL DEFAULT false,
  healthy_bite_distributed    BOOLEAN NOT NULL DEFAULT false,
  total_xp_earned             INTEGER NOT NULL DEFAULT 0,
  reflection_status           TEXT NOT NULL DEFAULT 'pending'
                              CHECK (reflection_status IN ('pending','reflected','auto_split')),
  reflection_deadline         TIMESTAMPTZ,
  is_guest                    BOOLEAN NOT NULL DEFAULT false,
  guest_phone                 TEXT,                  -- E.164
  pre_booking_id              UUID REFERENCES session_pre_bookings(id) ON DELETE SET NULL,
  notes                       TEXT,
  idempotency_key             TEXT UNIQUE,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_venue_active
  ON sessions(venue_id, status) WHERE status IN ('active','grace');
CREATE INDEX IF NOT EXISTS idx_sessions_family
  ON sessions(family_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_child
  ON sessions(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_reflection_pending
  ON sessions(reflection_deadline) WHERE reflection_status = 'pending';

-- Now wire the back-reference from session_pre_bookings -> sessions.
DO $$ BEGIN
  ALTER TABLE session_pre_bookings
    ADD CONSTRAINT fk_pre_bookings_redeemed_session
    FOREIGN KEY (redeemed_session_id) REFERENCES sessions(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
--  session_extensions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_extensions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id         UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  duration_minutes   INTEGER NOT NULL,
  amount_paise       INTEGER NOT NULL,
  payment_method     TEXT NOT NULL,
  new_expires_at     TIMESTAMPTZ NOT NULL,
  staff_pin_id       UUID REFERENCES staff(id),
  initiated_by       TEXT CHECK (initiated_by IN ('parent','staff_on_behalf')),
  idempotency_key    TEXT UNIQUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  qr_nonces
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS qr_nonces (
  nonce        UUID PRIMARY KEY,
  expires_at   TIMESTAMPTZ NOT NULL,
  used_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_qr_nonces_unused
  ON qr_nonces(expires_at) WHERE used_at IS NULL;

-- ---------------------------------------------------------------------------
--  orders + order_items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS orders (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                 UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  family_id                UUID REFERENCES families(id) ON DELETE SET NULL,
  staff_pin_id             UUID REFERENCES staff(id),
  fulfillment_mode         TEXT NOT NULL CHECK (fulfillment_mode IN ('dine_in','takeaway','table_service')),
  payment_method           TEXT NOT NULL CHECK (payment_method IN ('wallet','cash','razorpay')),
  subtotal_paise           INTEGER NOT NULL,         -- pre-GST, server-calculated
  gst_paise                INTEGER NOT NULL,
  combo_discount_paise     INTEGER NOT NULL DEFAULT 0,
  total_paise              INTEGER NOT NULL,
  coins_earned             INTEGER NOT NULL DEFAULT 0,
  status                   TEXT NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending','preparing','ready','served','cancelled')),
  combo_id                 UUID REFERENCES combos(id),
  invoice_pdf_url          TEXT,
  idempotency_key          TEXT UNIQUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_venue
  ON orders(venue_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_family
  ON orders(family_id, created_at DESC);

CREATE TABLE IF NOT EXISTS order_items (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id       UUID NOT NULL REFERENCES menu_items(id),
  brand              TEXT NOT NULL CHECK (brand IN ('coffee','fit')),
  name_snapshot      TEXT NOT NULL,
  quantity           INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price_paise   INTEGER NOT NULL,
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Gamification: xp_events, streak_records, brand_badges, visit_milestones
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS xp_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id        UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  family_id       UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  venue_id        UUID REFERENCES venues(id),
  event_type      TEXT NOT NULL CHECK (event_type IN (
    'play_session','reflection_split','auto_split',
    'healthy_bite','workshop',
    'birthday_hosted','birthday_guest','first_session',
    'streak_bonus','referral_bonus','birthday_bonus',
    'visit_milestone','manual_admin'
  )),
  xp_rafi         INTEGER NOT NULL DEFAULT 0,
  xp_ellie        INTEGER NOT NULL DEFAULT 0,
  xp_gerry        INTEGER NOT NULL DEFAULT 0,
  xp_zena         INTEGER NOT NULL DEFAULT 0,
  reference_id    UUID,
  metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_xp_child         ON xp_events(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_xp_session_ref   ON xp_events(reference_id);

CREATE TABLE IF NOT EXISTS streak_records (
  id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id                        UUID UNIQUE NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  current_streak_weeks            INTEGER NOT NULL DEFAULT 0,
  longest_streak_weeks            INTEGER NOT NULL DEFAULT 0,
  total_visit_stars               INTEGER NOT NULL DEFAULT 0,
  last_visit_date_ist             DATE,
  last_streak_week_ist            DATE,
  milestone_3_achieved            BOOLEAN NOT NULL DEFAULT false,
  milestone_5_achieved            BOOLEAN NOT NULL DEFAULT false,
  milestone_10_achieved           BOOLEAN NOT NULL DEFAULT false,
  milestone_10_badge_mailed       BOOLEAN NOT NULL DEFAULT false,
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS brand_badges (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id    UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  brand        TEXT NOT NULL CHECK (brand IN ('play','coffee','fit','triple_threat')),
  tier         TEXT NOT NULL CHECK (tier IN ('regular','champion','legend')),
  earned_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(family_id, brand, tier)
);
CREATE INDEX IF NOT EXISTS idx_brand_badges_family ON brand_badges(family_id);

CREATE TABLE IF NOT EXISTS visit_milestones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id           UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  visit_count         INTEGER NOT NULL,
  reward_paise        INTEGER,
  reward_xp_bonus     INTEGER,
  awarded_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(family_id, visit_count)
);

-- ---------------------------------------------------------------------------
--  Hero cards + birthday tables (mutual references, ordered carefully)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hero_card_definitions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    TEXT NOT NULL,
  hero                    TEXT NOT NULL CHECK (hero IN ('rafi','ellie','gerry','zena')),
  is_rare                 BOOLEAN NOT NULL DEFAULT false,
  is_birthday_exclusive   BOOLEAN NOT NULL DEFAULT false,
  image_url               TEXT NOT NULL,
  description             TEXT,
  is_active               BOOLEAN NOT NULL DEFAULT true,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS birthday_packages (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  name                TEXT NOT NULL,
  tier                TEXT NOT NULL CHECK (tier IN ('basic','hero_adventure','legendary','custom')),
  description         TEXT,
  cover_image_url     TEXT,
  gallery_image_urls  TEXT[],
  price_paise         INTEGER NOT NULL CHECK (price_paise > 0),
  duration_hours      INTEGER NOT NULL DEFAULT 2,
  max_kids            INTEGER NOT NULL,
  max_adults          INTEGER NOT NULL,
  inclusions          JSONB NOT NULL,
  hero_theme          TEXT CHECK (hero_theme IN ('rafi','ellie','gerry','zena','mixed')),
  deposit_paise       INTEGER NOT NULL,
  is_active           BOOLEAN NOT NULL DEFAULT true,
  sort_order          INTEGER NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT deposit_le_price CHECK (deposit_paise <= price_paise)
);

CREATE TABLE IF NOT EXISTS birthday_availability (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id          UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  slot_date         DATE NOT NULL,                   -- IST date
  slot_start_time   TIME NOT NULL,
  slot_end_time     TIME NOT NULL,
  is_blocked        BOOLEAN NOT NULL DEFAULT false,
  block_reason      TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(venue_id, slot_date, slot_start_time)
);
CREATE INDEX IF NOT EXISTS idx_bd_avail_lookup
  ON birthday_availability(venue_id, slot_date);

CREATE TABLE IF NOT EXISTS birthday_reservations (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                    UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  family_id                   UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  child_id                    UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
  package_id                  UUID NOT NULL REFERENCES birthday_packages(id),
  slot_date                   DATE NOT NULL,
  slot_start_time             TIME NOT NULL,
  slot_end_time               TIME NOT NULL,
  num_kids                    INTEGER NOT NULL,
  num_adults                  INTEGER NOT NULL,
  package_price_paise         INTEGER NOT NULL,
  deposit_paid_paise          INTEGER NOT NULL DEFAULT 0,
  balance_paise               INTEGER NOT NULL,
  total_paid_paise            INTEGER NOT NULL DEFAULT 0,
  status                      TEXT NOT NULL DEFAULT 'reserved'
                              CHECK (status IN (
                                'reserved','deposit_paid','confirmed',
                                'completed','cancelled','no_show'
                              )),
  assigned_admin              UUID,
  admin_contacted_at          TIMESTAMPTZ,
  admin_confirmed_at          TIMESTAMPTZ,
  admin_notes                 TEXT,
  triggered_by                TEXT CHECK (triggered_by IN (
                                'home_card','day_minus_90','day_minus_60','day_minus_30',
                                'day_minus_14','day_minus_7','day_minus_3',
                                'hero_progression','manual_admin'
                              )),
  reservation_expires_at      TIMESTAMPTZ,
  cancelled_reason            TEXT,
  cancelled_at                TIMESTAMPTZ,
  birthday_hero_card_id       UUID REFERENCES hero_card_definitions(id),
  album_ready_at              TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bd_res_venue_date
  ON birthday_reservations(venue_id, slot_date);
CREATE INDEX IF NOT EXISTS idx_bd_res_family
  ON birthday_reservations(family_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bd_res_status
  ON birthday_reservations(status);

CREATE TABLE IF NOT EXISTS hero_card_collection (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id               UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  card_id                UUID NOT NULL REFERENCES hero_card_definitions(id),
  earned_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  session_id             UUID REFERENCES sessions(id) ON DELETE SET NULL,
  birthday_booking_id    UUID REFERENCES birthday_reservations(id) ON DELETE SET NULL,
  UNIQUE(child_id, card_id)
);

CREATE TABLE IF NOT EXISTS birthday_party_photos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id    UUID NOT NULL REFERENCES birthday_reservations(id) ON DELETE CASCADE,
  photo_url         TEXT NOT NULL,
  uploaded_by_pin   UUID REFERENCES staff(id),
  is_in_album       BOOLEAN NOT NULL DEFAULT true,
  caption           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bd_photos_res
  ON birthday_party_photos(reservation_id, created_at);

CREATE TABLE IF NOT EXISTS birthday_journey_state (
  id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id                            UUID UNIQUE NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  reservation_id                      UUID REFERENCES birthday_reservations(id) ON DELETE SET NULL,
  birthday_year                       INTEGER NOT NULL,
  arc_type                            TEXT NOT NULL DEFAULT 'discovery'
                                      CHECK (arc_type IN ('discovery','reserved','hosted','adventure','paused')),
  comms_paused                        BOOLEAN NOT NULL DEFAULT false,
  d_minus_90_sent                     BOOLEAN NOT NULL DEFAULT false,
  d_minus_60_sent                     BOOLEAN NOT NULL DEFAULT false,
  d_minus_30_sent                     BOOLEAN NOT NULL DEFAULT false,
  d_minus_14_sent                     BOOLEAN NOT NULL DEFAULT false,
  d_minus_7_sent                      BOOLEAN NOT NULL DEFAULT false,
  d_minus_3_sent                      BOOLEAN NOT NULL DEFAULT false,
  d_minus_1_sent                      BOOLEAN NOT NULL DEFAULT false,
  d_zero_sent                         BOOLEAN NOT NULL DEFAULT false,
  d_plus_1_sent                       BOOLEAN NOT NULL DEFAULT false,
  d_plus_7_sent                       BOOLEAN NOT NULL DEFAULT false,
  hero_progression_trigger_sent       BOOLEAN NOT NULL DEFAULT false,
  birthday_bonus_credited             BOOLEAN NOT NULL DEFAULT false,
  updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Gifts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gift_ladder (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  level_required      INTEGER NOT NULL,
  gift_name           TEXT NOT NULL,
  gift_description    TEXT,
  delivery_method     TEXT CHECK (delivery_method IN ('venue','mail')),
  is_active           BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS gift_redemptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id        UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  gift_id         UUID NOT NULL REFERENCES gift_ladder(id),
  venue_id        UUID NOT NULL REFERENCES venues(id),
  staff_pin_id    UUID REFERENCES staff(id),
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(child_id, gift_id)
);

-- ---------------------------------------------------------------------------
--  Referrals, refunds, notifications, hero recaps, reflection moments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS referral_conversions (
  id                                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_family_id                  UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  new_family_id                       UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  triggering_session_id               UUID REFERENCES sessions(id) ON DELETE SET NULL,
  conversion_month                    DATE NOT NULL,            -- IST first-of-month
  gifter_wallet_credit_paise          INTEGER NOT NULL,
  gifter_xp_bonus_rafi                INTEGER NOT NULL,
  new_family_wallet_credit_paise      INTEGER NOT NULL,
  is_first_referral                   BOOLEAN NOT NULL DEFAULT false,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referral_gifter_month
  ON referral_conversions(referrer_family_id, conversion_month);
CREATE INDEX IF NOT EXISTS idx_referral_new
  ON referral_conversions(new_family_id);

CREATE TABLE IF NOT EXISTS refunds (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id               UUID NOT NULL REFERENCES families(id) ON DELETE RESTRICT,
  reference_id            UUID NOT NULL,
  reference_type          TEXT NOT NULL CHECK (reference_type IN ('session','order','workshop','birthday','manual')),
  amount_paise            INTEGER NOT NULL CHECK (amount_paise > 0),
  destination             TEXT CHECK (destination IN ('wallet','razorpay')),
  initiated_by            TEXT CHECK (initiated_by IN ('staff','admin','auto')),
  staff_pin_id            UUID REFERENCES staff(id),
  status                  TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','approved','rejected','processing','completed')),
  reason                  TEXT NOT NULL,
  approved_by             UUID,
  approved_at             TIMESTAMPTZ,
  razorpay_refund_id      TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_refunds_status ON refunds(status, created_at);

CREATE TABLE IF NOT EXISTS notifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id       UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN (
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
  title           TEXT NOT NULL,
  body            TEXT NOT NULL,
  deep_link       TEXT,
  is_read         BOOLEAN NOT NULL DEFAULT false,
  reference_id    UUID,
  push_sent_at    TIMESTAMPTZ,
  push_status     TEXT CHECK (push_status IN ('queued','dispatched','failed','skipped')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_family
  ON notifications(family_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON notifications(family_id, is_read) WHERE is_read = false;

CREATE TABLE IF NOT EXISTS hero_recaps (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id              UUID UNIQUE NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  child_id                UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  image_url               TEXT,
  total_xp_pool           INTEGER NOT NULL,
  reflection_status       TEXT NOT NULL DEFAULT 'pending'
                          CHECK (reflection_status IN ('pending','reflected','auto_split')),
  reflection_at           TIMESTAMPTZ,
  reflection_deadline     TIMESTAMPTZ,
  moment_tags             TEXT[],
  rare_card_earned        BOOLEAN NOT NULL DEFAULT false,
  rare_card_id            UUID REFERENCES hero_card_definitions(id),
  generated_at            TIMESTAMPTZ,
  notification_sent       BOOLEAN NOT NULL DEFAULT false,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_hero_recaps_pending
  ON hero_recaps(reflection_deadline) WHERE reflection_status = 'pending';

CREATE TABLE IF NOT EXISTS reflection_moments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tag             TEXT UNIQUE NOT NULL,
  display_text    TEXT NOT NULL,
  icon            TEXT,                              -- phosphor icon name
  primary_trait   TEXT NOT NULL CHECK (primary_trait IN ('rafi','ellie','gerry','zena')),
  xp_weight       NUMERIC(3,2) NOT NULL DEFAULT 1.0,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  sort_order      INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
--  Operations: shifts, audit log, reactivation, wall of legends, monitoring
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shift_logs (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,
  shift_start             TIMESTAMPTZ NOT NULL DEFAULT now(),
  shift_end               TIMESTAMPTZ,
  expected_cash_paise     INTEGER,
  counted_cash_paise      INTEGER,
  discrepancy_paise       INTEGER GENERATED ALWAYS AS
                          (COALESCE(counted_cash_paise, 0) - COALESCE(expected_cash_paise, 0)) STORED,
  notes                   TEXT,
  closed_by_pin           UUID REFERENCES staff(id),
  status                  TEXT NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open','closed','disputed')),
  summary                 JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_shift_open ON shift_logs(venue_id) WHERE status = 'open';

CREATE TABLE IF NOT EXISTS audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id        UUID,
  actor_type      TEXT NOT NULL CHECK (actor_type IN ('staff','admin','system','customer')),
  action          TEXT NOT NULL,
  entity_type     TEXT NOT NULL,
  entity_id       UUID,
  old_value       JSONB,
  new_value       JSONB,
  venue_id        UUID,
  ip_address      TEXT,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_actor   ON audit_log(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity  ON audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);

CREATE TABLE IF NOT EXISTS reactivation_contacts (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone                   TEXT UNIQUE NOT NULL,         -- E.164
  name                    TEXT,
  last_visit_date         DATE,
  visit_count             INTEGER,
  credit_paise            INTEGER NOT NULL DEFAULT 20000,
  credit_expires_at       TIMESTAMPTZ NOT NULL,
  sms_status              TEXT NOT NULL DEFAULT 'pending'
                          CHECK (sms_status IN ('pending','queued','dispatched','failed','skipped')),
  sms_msg91_id            TEXT,
  sms_dispatched_at       TIMESTAMPTZ,
  sms_failure_reason      TEXT,
  redeemed_at             TIMESTAMPTZ,
  redeemed_family_id      UUID REFERENCES families(id) ON DELETE SET NULL,
  imported_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  imported_batch_id       UUID,
  is_paused               BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_reactivation_phone
  ON reactivation_contacts(phone);
CREATE INDEX IF NOT EXISTS idx_reactivation_pending_sms
  ON reactivation_contacts(sms_status) WHERE sms_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_reactivation_unredeemed
  ON reactivation_contacts(redeemed_at) WHERE redeemed_at IS NULL;

CREATE TABLE IF NOT EXISTS wall_of_legends_daily (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                 UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  ist_date                 DATE NOT NULL,
  total_families           INTEGER NOT NULL DEFAULT 0,
  total_sessions           INTEGER NOT NULL DEFAULT 0,
  stage_transitions        INTEGER NOT NULL DEFAULT 0,
  birthdays_celebrated     INTEGER NOT NULL DEFAULT 0,
  workshops_attended       INTEGER NOT NULL DEFAULT 0,
  hero_cards_earned        INTEGER NOT NULL DEFAULT 0,
  highlights               JSONB NOT NULL DEFAULT '[]'::jsonb,
  computed_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(venue_id, ist_date)
);
CREATE INDEX IF NOT EXISTS idx_wol_venue_date
  ON wall_of_legends_daily(venue_id, ist_date DESC);

CREATE TABLE IF NOT EXISTS reconciliation_log (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type                     TEXT NOT NULL CHECK (type IN ('razorpay','manual')),
  ran_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  payments_checked         INTEGER NOT NULL DEFAULT 0,
  discrepancies_found      INTEGER NOT NULL DEFAULT 0,
  total_corrected_paise    INTEGER NOT NULL DEFAULT 0,
  details                  JSONB NOT NULL DEFAULT '{}'::jsonb,
  status                   TEXT CHECK (status IN ('success','partial','failed'))
);

CREATE TABLE IF NOT EXISTS system_health_snapshots (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  api_p95_ms                    INTEGER,
  edge_function_failure_rate    NUMERIC(5,2),
  push_delivery_rate            NUMERIC(5,2),
  active_sessions               INTEGER,
  reconciliation_health         TEXT CHECK (reconciliation_health IN ('green','yellow','red')),
  notes                         TEXT
);

-- ===========================================================================
--  TRIGGERS
-- ===========================================================================

-- families: phone validator
DROP TRIGGER IF EXISTS families_validate_phone ON families;
CREATE TRIGGER families_validate_phone
  BEFORE INSERT OR UPDATE OF phone ON families
  FOR EACH ROW EXECUTE FUNCTION validate_phone_e164();

-- families: wallet auto-create
DROP TRIGGER IF EXISTS families_create_wallet ON families;
CREATE TRIGGER families_create_wallet
  AFTER INSERT ON families
  FOR EACH ROW EXECUTE FUNCTION create_wallet_for_family();

-- updated_at maintainers
DROP TRIGGER IF EXISTS wallets_set_updated_at ON wallets;
CREATE TRIGGER wallets_set_updated_at
  BEFORE UPDATE ON wallets
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS menu_items_set_updated_at ON menu_items;
CREATE TRIGGER menu_items_set_updated_at
  BEFORE UPDATE ON menu_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS streak_records_set_updated_at ON streak_records;
CREATE TRIGGER streak_records_set_updated_at
  BEFORE UPDATE ON streak_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS venue_config_set_updated_at ON venue_config;
CREATE TRIGGER venue_config_set_updated_at
  BEFORE UPDATE ON venue_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS birthday_journey_state_set_updated_at ON birthday_journey_state;
CREATE TRIGGER birthday_journey_state_set_updated_at
  BEFORE UPDATE ON birthday_journey_state
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================================================
--  RLS — enable on every table; add customer-facing policies; deny-by-default
--        on staff/admin/system tables (only SECURITY DEFINER RPCs / service_role).
-- ===========================================================================

-- Customer-facing tables (own data only)
ALTER TABLE families                ENABLE ROW LEVEL SECURITY;
ALTER TABLE children                ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions                ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_extensions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_pre_bookings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications           ENABLE ROW LEVEL SECURITY;
ALTER TABLE xp_events               ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_records          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_card_collection    ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_reservations   ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_party_photos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_journey_state  ENABLE ROW LEVEL SECURITY;
ALTER TABLE workshop_registrations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_recaps             ENABLE ROW LEVEL SECURITY;
ALTER TABLE brand_badges            ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_milestones        ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_redemptions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_conversions    ENABLE ROW LEVEL SECURITY;

-- Public-read tables (catalog / configuration the app needs unauthenticated)
ALTER TABLE venues                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE venue_config            ENABLE ROW LEVEL SECURITY;
ALTER TABLE menus                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items              ENABLE ROW LEVEL SECURITY;
ALTER TABLE workshops               ENABLE ROW LEVEL SECURITY;
ALTER TABLE combos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_packages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE birthday_availability   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hero_card_definitions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE reflection_moments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_ladder             ENABLE ROW LEVEL SECURITY;
ALTER TABLE wall_of_legends_daily   ENABLE ROW LEVEL SECURITY;

-- Staff / admin / system tables — deny by default (no policies = no access).
-- Reachable only via SECURITY DEFINER RPCs or the service_role key.
ALTER TABLE staff                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_logs                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE reactivation_contacts       ENABLE ROW LEVEL SECURITY;
ALTER TABLE qr_nonces                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE reconciliation_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_health_snapshots     ENABLE ROW LEVEL SECURITY;

-- ─── Customer policies (own family) ───────────────────────────────────────
DROP POLICY IF EXISTS families_self ON families;
CREATE POLICY families_self ON families
  FOR ALL USING (id = auth_family_id()) WITH CHECK (id = auth_family_id());

DROP POLICY IF EXISTS children_family ON children;
CREATE POLICY children_family ON children
  FOR ALL USING (family_id = auth_family_id()) WITH CHECK (family_id = auth_family_id());

DROP POLICY IF EXISTS wallets_family ON wallets;
CREATE POLICY wallets_family ON wallets
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS wallet_tx_family ON wallet_transactions;
CREATE POLICY wallet_tx_family ON wallet_transactions
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS sessions_family ON sessions;
CREATE POLICY sessions_family ON sessions
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS session_extensions_family ON session_extensions;
CREATE POLICY session_extensions_family ON session_extensions
  FOR SELECT USING (
    session_id IN (SELECT id FROM sessions WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS pre_bookings_family ON session_pre_bookings;
CREATE POLICY pre_bookings_family ON session_pre_bookings
  FOR ALL USING (family_id = auth_family_id()) WITH CHECK (family_id = auth_family_id());

DROP POLICY IF EXISTS orders_family ON orders;
CREATE POLICY orders_family ON orders
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS order_items_family ON order_items;
CREATE POLICY order_items_family ON order_items
  FOR SELECT USING (
    order_id IN (SELECT id FROM orders WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS notifications_family ON notifications;
CREATE POLICY notifications_family ON notifications
  FOR ALL USING (family_id = auth_family_id()) WITH CHECK (family_id = auth_family_id());

DROP POLICY IF EXISTS xp_events_family ON xp_events;
CREATE POLICY xp_events_family ON xp_events
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS streak_family ON streak_records;
CREATE POLICY streak_family ON streak_records
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS hero_cards_family ON hero_card_collection;
CREATE POLICY hero_cards_family ON hero_card_collection
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS bd_res_family ON birthday_reservations;
CREATE POLICY bd_res_family ON birthday_reservations
  FOR ALL USING (family_id = auth_family_id()) WITH CHECK (family_id = auth_family_id());

-- birthday_party_photos: parents can read photos for THEIR reservations.
-- Writes happen via SECURITY DEFINER RPC (staff PIN authorised) — no client write policy.
DROP POLICY IF EXISTS bd_photos_family_read ON birthday_party_photos;
CREATE POLICY bd_photos_family_read ON birthday_party_photos
  FOR SELECT USING (
    reservation_id IN (
      SELECT id FROM birthday_reservations WHERE family_id = auth_family_id()
    )
  );

DROP POLICY IF EXISTS bd_journey_family ON birthday_journey_state;
CREATE POLICY bd_journey_family ON birthday_journey_state
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS wshop_reg_family ON workshop_registrations;
CREATE POLICY wshop_reg_family ON workshop_registrations
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS hero_recaps_family ON hero_recaps;
CREATE POLICY hero_recaps_family ON hero_recaps
  FOR ALL USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS brand_badges_family ON brand_badges;
CREATE POLICY brand_badges_family ON brand_badges
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS visit_milestones_family ON visit_milestones;
CREATE POLICY visit_milestones_family ON visit_milestones
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS refunds_family ON refunds;
CREATE POLICY refunds_family ON refunds
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS gift_redemptions_family ON gift_redemptions;
CREATE POLICY gift_redemptions_family ON gift_redemptions
  FOR SELECT USING (
    child_id IN (SELECT id FROM children WHERE family_id = auth_family_id())
  );

DROP POLICY IF EXISTS referral_conv_family ON referral_conversions;
CREATE POLICY referral_conv_family ON referral_conversions
  FOR SELECT USING (
    referrer_family_id = auth_family_id() OR new_family_id = auth_family_id()
  );

-- ─── Public-read policies (catalog / config) ─────────────────────────────
DROP POLICY IF EXISTS venues_public_read ON venues;
CREATE POLICY venues_public_read ON venues
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS venue_config_public_read ON venue_config;
CREATE POLICY venue_config_public_read ON venue_config
  FOR SELECT USING (true);

DROP POLICY IF EXISTS menus_public_read ON menus;
CREATE POLICY menus_public_read ON menus
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS menu_items_public_read ON menu_items;
CREATE POLICY menu_items_public_read ON menu_items
  FOR SELECT USING (is_available = true);

DROP POLICY IF EXISTS workshops_public_read ON workshops;
CREATE POLICY workshops_public_read ON workshops
  FOR SELECT USING (status = 'upcoming');

DROP POLICY IF EXISTS combos_public_read ON combos;
CREATE POLICY combos_public_read ON combos
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS birthday_packages_public_read ON birthday_packages;
CREATE POLICY birthday_packages_public_read ON birthday_packages
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS birthday_availability_public_read ON birthday_availability;
CREATE POLICY birthday_availability_public_read ON birthday_availability
  FOR SELECT USING (true);

DROP POLICY IF EXISTS hero_card_defs_public_read ON hero_card_definitions;
CREATE POLICY hero_card_defs_public_read ON hero_card_definitions
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS reflection_moments_public_read ON reflection_moments;
CREATE POLICY reflection_moments_public_read ON reflection_moments
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS gift_ladder_public_read ON gift_ladder;
CREATE POLICY gift_ladder_public_read ON gift_ladder
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS wol_public_read ON wall_of_legends_daily;
CREATE POLICY wol_public_read ON wall_of_legends_daily
  FOR SELECT USING (true);

-- staff, shift_logs, audit_log, reactivation_contacts, qr_nonces,
-- reconciliation_log, system_health_snapshots: NO policies → deny all.
-- Service role bypasses RLS; SECURITY DEFINER RPCs bypass via owner privilege.

-- ===========================================================================
--  get_venue_config — returns all admin-tunable values as JSONB
-- ===========================================================================
CREATE OR REPLACE FUNCTION get_venue_config(p_venue_id UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config JSONB;
BEGIN
  SELECT to_jsonb(vc.*) - 'id' - 'venue_id' - 'updated_at'
    INTO v_config
    FROM venue_config vc
    WHERE vc.venue_id = p_venue_id;

  IF v_config IS NULL THEN
    RAISE EXCEPTION 'venue_config_not_found';
  END IF;

  RETURN v_config;
END $$;

REVOKE ALL ON FUNCTION get_venue_config(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_venue_config(UUID) TO anon, authenticated, service_role;

-- ===========================================================================
--  STORAGE BUCKETS  (idempotent via ON CONFLICT)
-- ===========================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('child-photos',     'child-photos',     false),
  ('birthday-photos',  'birthday-photos',  false),
  ('hero-recaps',      'hero-recaps',      true),
  ('hero-cards',       'hero-cards',       true),
  ('invoices',         'invoices',         false)
ON CONFLICT (id) DO NOTHING;

-- ─── Storage policies ────────────────────────────────────────────────────
-- Path conventions:
--   child-photos:    {family_id}/{child_id}/{filename}
--   birthday-photos: {reservation_id}/{filename}
--   invoices:        {family_id}/{invoice_id}.pdf
--   hero-recaps:     anything (public read)
--   hero-cards:      anything (public read)

-- child-photos: parents read/write/delete files in their own folder
DROP POLICY IF EXISTS "child_photos_owner_all" ON storage.objects;
CREATE POLICY "child_photos_owner_all" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'child-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'child-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- birthday-photos: parents read photos for their own reservations only.
-- Writes performed by Edge Function with service_role.
DROP POLICY IF EXISTS "birthday_photos_owner_read" ON storage.objects;
CREATE POLICY "birthday_photos_owner_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'birthday-photos'
    AND (storage.foldername(name))[1] IN (
      SELECT id::text FROM birthday_reservations
      WHERE family_id = auth.uid()
    )
  );

-- invoices: parents read own invoices; writes by Edge Function only
DROP POLICY IF EXISTS "invoices_owner_read" ON storage.objects;
CREATE POLICY "invoices_owner_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'invoices'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- hero-recaps and hero-cards are public buckets; the bucket flag handles read.
-- Block writes from clients (Edge Functions only):
DROP POLICY IF EXISTS "hero_recaps_block_client_write" ON storage.objects;
DROP POLICY IF EXISTS "hero_cards_block_client_write"  ON storage.objects;
-- (no INSERT/UPDATE/DELETE policy = no client writes)

-- ===========================================================================
--  SEED DATA
-- ===========================================================================

-- One venue (Play Diaries Kondapur)
INSERT INTO venues (id, name, address, phone, whatsapp, max_capacity)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Play Diaries Kondapur',
  'Kondapur, Hyderabad, Telangana',
  '+919876543210',
  '+919876543210',
  50
) ON CONFLICT (id) DO NOTHING;

-- venue_config row with all defaults
INSERT INTO venue_config (venue_id)
VALUES ('00000000-0000-0000-0000-000000000001')
ON CONFLICT (venue_id) DO NOTHING;

-- ─── reflection_moments — STUB ───────────────────────────────────────────
-- TODO(founder): provide 24 cards (6 per trait: rafi/ellie/gerry/zena).
-- This stub is intentionally empty — the founder will deliver the 24 cards
-- in a follow-up migration. The recap UI must guard against 0 rows in dev
-- until that data lands.
--
-- Example shape (do NOT uncomment):
--   INSERT INTO reflection_moments (tag, display_text, primary_trait, sort_order) VALUES
--     ('tried_something_new', 'Tried something new', 'rafi', 10),
--     ...
--   ON CONFLICT (tag) DO NOTHING;

-- 3 birthday packages (placeholder pricing — founder confirms before launch)
INSERT INTO birthday_packages
  (venue_id, name, tier, description, price_paise, max_kids, max_adults, deposit_paise, hero_theme, inclusions, sort_order)
VALUES
  ('00000000-0000-0000-0000-000000000001',
   'Birthday Basics',  'basic',
   'A simple celebration: 2hr exclusive play time, themed decor, kids meal.',
   1500000, 15, 10, 500000, 'mixed',
   '{"play_session":"2hr","decor":"basic","food_kids":"FIT meal","cake":"add-on"}'::jsonb, 10),

  ('00000000-0000-0000-0000-000000000001',
   'Hero Adventure',   'hero_adventure',
   'Full Hero theme experience: 2hr play, themed decor, FIT party platter, Coffee Diaries adult spread, themed cake, 1 host.',
   2500000, 20, 15, 800000, 'rafi',
   '{"play_session":"2hr","decor":"hero_themed","food_kids":"FIT party platter","food_adults":"Coffee Diaries spread","cake":"themed 1kg","host":"1"}'::jsonb, 20),

  ('00000000-0000-0000-0000-000000000001',
   'Legendary Birthday', 'legendary',
   'The full experience: 3hr exclusive venue, full theme execution, premium food, themed cake, 2 hosts, photo album.',
   4500000, 25, 20, 1500000, 'mixed',
   '{"play_session":"3hr exclusive","decor":"premium themed","food_kids":"FIT premium platter","food_adults":"Coffee Diaries premium","cake":"themed 2kg","host":"2","extras":"photo album"}'::jsonb, 30)
ON CONFLICT DO NOTHING;

-- ===========================================================================
--  END
-- ===========================================================================
