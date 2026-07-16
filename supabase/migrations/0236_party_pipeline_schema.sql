-- ===========================================================================
--  Migration 0236 — Party/Events pipeline: schema (Phase 0, part 1 of 2)
--
--  See docs/EVENTS_PIPELINE.md. The venue's biggest revenue stream (~53%)
--  runs on phone calls + a paper register; this adds the system around the
--  existing birthday_packages catalog and birthday_reservations bookings.
--
--  Design (locked by founder spec, 2026-07-12):
--    * party_leads — the single funnel head for ALL sources. A ≤10s phone
--      lead has no family/child/package/date, so it cannot live in
--      birthday_reservations (family_id/child_id/package_id NOT NULL).
--      One lead → (on win) one reservation, linked via reservation_id.
--    * party_lead_notes — append-only call/WhatsApp log. Never edited.
--    * party_payments — append-only party money ledger. Parties do NOT
--      route through the kids' wallet (supersedes the 0003
--      birthday_deposit_record approach). Refunds are direction = -1 rows.
--      deposit_paid_paise / total_paid_paise / balance_paise on
--      birthday_reservations become DERIVED: recomputed by trigger from
--      SUM(amount_paise × direction) — never hand-set.
--    * party_checklist_templates + party_checklist_items — day-of
--      checklist, instantiated at convert time (11 standard items,
--      dictated by founder 2026-07-12).
--    * birthday_reservations schema is NOT altered except ONE necessary
--      vocabulary extension: the triggered_by CHECK gains the lead-source
--      values so a converted booking records provenance (spec requires
--      triggered_by = lead source). Same pattern as 0019/0162.
--
--  RLS: enabled on every new table, deny-by-default. Mutations only via
--  SECURITY DEFINER RPCs (0237). Admin gets read policies for reporting.
--
--  NOT applied to prod at write time — validated on a disposable branch DB
--  first (supabase/tests/party_pipeline_test.sql), applied to prod later
--  via the one-lane migration workflow.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. party_leads — funnel head, all sources
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS party_leads (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id                 UUID NOT NULL REFERENCES venues(id) ON DELETE RESTRICT,

  -- Mandatory provenance. 'repeat_customer' is reserved for the repeat cron.
  source                   TEXT NOT NULL CHECK (source IN (
                             'phone','walkin','whatsapp','instagram',
                             'referral','app_enquiry','repeat_customer','other'
                           )),
  status                   TEXT NOT NULL DEFAULT 'new' CHECK (status IN (
                             'new','contacted','visited','quoted',
                             'won','lost','stale'
                           )),
  event_type               TEXT NOT NULL DEFAULT 'birthday' CHECK (event_type IN (
                             'birthday','school_outing','playschool_visit',
                             'corporate_family','festival_event','banquet','other'
                           )),

  -- The ≤10s capture: who called, from where. Phone is the dedupe key.
  parent_name              TEXT NOT NULL CHECK (length(trim(parent_name)) > 0),
  phone                    TEXT NOT NULL CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
  child_name               TEXT,
  child_dob                DATE,                      -- drives the repeat-lead timer
  guest_estimate           INTEGER CHECK (guest_estimate > 0),
  event_date_requested     DATE,
  slot_pref                TEXT CHECK (slot_pref IN ('morning','evening')),
  package_id               UUID REFERENCES birthday_packages(id) ON DELETE SET NULL,

  -- Links, filled as the lead matures.
  family_id                UUID REFERENCES families(id) ON DELETE SET NULL,
  child_id                 UUID REFERENCES children(id) ON DELETE SET NULL,
  reservation_id           UUID REFERENCES birthday_reservations(id) ON DELETE SET NULL,
  -- Repeat-lead dedupe: at most one auto-generated lead per completed party,
  -- ever (cron guards with NOT EXISTS on this column).
  repeat_of_reservation_id UUID REFERENCES birthday_reservations(id) ON DELETE SET NULL,

  assigned_staff_id        UUID REFERENCES staff(id) ON DELETE SET NULL,
  next_follow_up_at        TIMESTAMPTZ,
  last_contacted_at        TIMESTAMPTZ,
  follow_up_count          INTEGER NOT NULL DEFAULT 0,

  lost_reason              TEXT CHECK (lost_reason IN (
                             'price','date_unavailable','went_elsewhere',
                             'no_response','not_serious','other'
                           )),
  lost_reason_note         TEXT,

  created_by_staff_id      UUID REFERENCES staff(id) ON DELETE SET NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT party_leads_lost_requires_reason
    CHECK (status <> 'lost' OR lost_reason IS NOT NULL),
  CONSTRAINT party_leads_won_requires_reservation
    CHECK (status <> 'won' OR reservation_id IS NOT NULL)
);

-- Dedupe repeat calls: one OPEN lead per (phone, requested date). A caller
-- with no date yet collapses onto the 1900-01-01 sentinel bucket.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_party_leads_open_phone_date
  ON party_leads (phone, COALESCE(event_date_requested, DATE '1900-01-01'))
  WHERE status IN ('new','contacted','visited','quoted');

CREATE INDEX IF NOT EXISTS idx_party_leads_venue_status
  ON party_leads(venue_id, status);
CREATE INDEX IF NOT EXISTS idx_party_leads_follow_up
  ON party_leads(next_follow_up_at)
  WHERE status IN ('new','contacted','visited','quoted');
CREATE INDEX IF NOT EXISTS idx_party_leads_repeat_of
  ON party_leads(repeat_of_reservation_id)
  WHERE repeat_of_reservation_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_party_leads_created
  ON party_leads(created_at DESC);

DROP TRIGGER IF EXISTS party_leads_set_updated_at ON party_leads;
CREATE TRIGGER party_leads_set_updated_at
  BEFORE UPDATE ON party_leads
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
--  2. party_lead_notes — append-only contact log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS party_lead_notes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id          UUID NOT NULL REFERENCES party_leads(id) ON DELETE CASCADE,
  author_staff_id  UUID REFERENCES staff(id) ON DELETE SET NULL,
  channel          TEXT NOT NULL DEFAULT 'system' CHECK (channel IN (
                     'call','whatsapp','visit','system'
                   )),
  body             TEXT NOT NULL CHECK (length(trim(body)) > 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_party_lead_notes_lead
  ON party_lead_notes(lead_id, created_at DESC);

CREATE OR REPLACE FUNCTION party_append_only_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'append_only'
    USING DETAIL = format('%s rows are immutable — corrections are new rows', TG_TABLE_NAME);
END $$;

DROP TRIGGER IF EXISTS party_lead_notes_append_only ON party_lead_notes;
CREATE TRIGGER party_lead_notes_append_only
  BEFORE UPDATE OR DELETE ON party_lead_notes
  FOR EACH ROW EXECUTE FUNCTION party_append_only_guard();

-- ---------------------------------------------------------------------------
--  3. party_payments — append-only party money ledger
--
--  NOT the kids' wallet. amount_paise is always positive; direction gives
--  the sign (+1 collect, -1 refund). Source of truth for the derived money
--  columns on birthday_reservations (trigger below).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS party_payments (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id         UUID NOT NULL REFERENCES birthday_reservations(id) ON DELETE RESTRICT,
  kind                   TEXT NOT NULL CHECK (kind IN ('advance','balance','refund')),
  direction              SMALLINT NOT NULL CHECK (direction IN (1, -1)),
  amount_paise           INTEGER NOT NULL CHECK (amount_paise > 0),
  method                 TEXT NOT NULL CHECK (method IN (
                           'cash','card','upi','razorpay','bank_transfer'
                         )),
  payment_context        TEXT NOT NULL DEFAULT 'party' CHECK (payment_context IN (
                           'party','banquet','commission'
                         )),
  razorpay_payment_id    TEXT,
  invoice_no             TEXT,                        -- via _next_invoice_number(); NULL on refunds
  collected_by_staff_id  UUID REFERENCES staff(id) ON DELETE SET NULL,
  idempotency_key        TEXT NOT NULL UNIQUE,        -- double-charge guard
  note                   TEXT,
  received_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- refund ⇔ direction -1
  CONSTRAINT party_payments_refund_direction
    CHECK ((kind = 'refund') = (direction = -1))
);
CREATE INDEX IF NOT EXISTS idx_party_payments_reservation
  ON party_payments(reservation_id, received_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_party_payments_invoice
  ON party_payments(invoice_no) WHERE invoice_no IS NOT NULL;

DROP TRIGGER IF EXISTS party_payments_append_only ON party_payments;
CREATE TRIGGER party_payments_append_only
  BEFORE UPDATE OR DELETE ON party_payments
  FOR EACH ROW EXECUTE FUNCTION party_append_only_guard();

-- ---------------------------------------------------------------------------
--  4. Derived money columns on birthday_reservations
--
--  deposit_paid_paise / total_paid_paise = net collected so far
--  balance_paise                         = package_price_paise − net
--  Recomputed on every ledger write; never hand-set by pipeline code.
--  (UPDATE/DELETE legs are unreachable while the append-only trigger
--  stands — kept for defence in depth.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION party_payments_recompute_reservation() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
  v_res_id UUID := COALESCE(NEW.reservation_id, OLD.reservation_id);
  v_net    INTEGER;
BEGIN
  SELECT COALESCE(SUM(amount_paise * direction), 0) INTO v_net
    FROM party_payments WHERE reservation_id = v_res_id;

  UPDATE birthday_reservations SET
    deposit_paid_paise = v_net,
    total_paid_paise   = v_net,
    balance_paise      = package_price_paise - v_net
  WHERE id = v_res_id;

  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS party_payments_recompute ON party_payments;
CREATE TRIGGER party_payments_recompute
  AFTER INSERT OR UPDATE OR DELETE ON party_payments
  FOR EACH ROW EXECUTE FUNCTION party_payments_recompute_reservation();

-- ---------------------------------------------------------------------------
--  5. Day-of checklist: template + per-booking items
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS party_checklist_templates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id    UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name        TEXT NOT NULL DEFAULT 'default',
  -- [{"key":"decor","label":"Decor ready","sort_order":1}, ...]
  items       JSONB NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(venue_id, name)
);

DROP TRIGGER IF EXISTS party_checklist_templates_set_updated_at ON party_checklist_templates;
CREATE TRIGGER party_checklist_templates_set_updated_at
  BEFORE UPDATE ON party_checklist_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS party_checklist_items (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id     UUID NOT NULL REFERENCES birthday_reservations(id) ON DELETE CASCADE,
  item_key           TEXT NOT NULL,
  label              TEXT NOT NULL,
  sort_order         INTEGER NOT NULL DEFAULT 0,
  is_done            BOOLEAN NOT NULL DEFAULT false,
  done_by_staff_id   UUID REFERENCES staff(id) ON DELETE SET NULL,
  done_at            TIMESTAMPTZ,
  UNIQUE(reservation_id, item_key),
  -- done ⇔ done_at set
  CONSTRAINT party_checklist_done_consistency
    CHECK (is_done = (done_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_party_checklist_reservation
  ON party_checklist_items(reservation_id, sort_order);

-- Seed the 11 standard items (founder-dictated 2026-07-12) for every
-- existing venue. New venues get a template via admin config (later phase).
INSERT INTO party_checklist_templates (venue_id, name, items)
SELECT v.id, 'default', '[
  {"key":"decor",            "label":"Decor ready",              "sort_order":1},
  {"key":"menu_confirmed",   "label":"Menu confirmed",           "sort_order":2},
  {"key":"staff_assigned",   "label":"Staff assigned",           "sort_order":3},
  {"key":"guest_count",      "label":"Guest count confirmed",    "sort_order":4},
  {"key":"kids_count",       "label":"Kids count confirmed",     "sort_order":5},
  {"key":"housekeeping",     "label":"Housekeeping done",        "sort_order":6},
  {"key":"food_labels",      "label":"Food labels placed",       "sort_order":7},
  {"key":"tissues",          "label":"Tissues stocked",          "sort_order":8},
  {"key":"host_briefed",     "label":"Host briefed",             "sort_order":9},
  {"key":"activities_ready", "label":"Activities ready",         "sort_order":10},
  {"key":"washroom_cleaned", "label":"Washroom cleaned",         "sort_order":11}
]'::jsonb
FROM venues v
ON CONFLICT (venue_id, name) DO NOTHING;

-- ---------------------------------------------------------------------------
--  6. triggered_by vocabulary: converted bookings record their lead source
--
--  The ONE touch on birthday_reservations — same CHECK-extension pattern
--  as 0019 and 0162. Columns/nullability untouched.
-- ---------------------------------------------------------------------------
ALTER TABLE birthday_reservations
  DROP CONSTRAINT IF EXISTS birthday_reservations_triggered_by_check;
ALTER TABLE birthday_reservations
  ADD CONSTRAINT birthday_reservations_triggered_by_check CHECK (
    triggered_by = ANY (ARRAY[
      'home_card',
      'day_minus_90','day_minus_60','day_minus_30','day_minus_14',
      'day_minus_7','day_minus_3',
      'hero_progression',
      'manual','manual_admin',
      'packages_sheet',
      -- party-lead sources (0236)
      'phone','walkin','whatsapp','instagram',
      'referral','app_enquiry','repeat_customer','other'
    ])
  );

-- ---------------------------------------------------------------------------
--  7. RLS — deny-by-default; admin read for reporting
-- ---------------------------------------------------------------------------
ALTER TABLE party_leads               ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_lead_notes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_payments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_checklist_items     ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS party_leads_admin_read ON party_leads;
CREATE POLICY party_leads_admin_read ON party_leads
  FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS party_lead_notes_admin_read ON party_lead_notes;
CREATE POLICY party_lead_notes_admin_read ON party_lead_notes
  FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS party_payments_admin_read ON party_payments;
CREATE POLICY party_payments_admin_read ON party_payments
  FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS party_checklist_templates_admin_read ON party_checklist_templates;
CREATE POLICY party_checklist_templates_admin_read ON party_checklist_templates
  FOR SELECT USING (is_admin());

DROP POLICY IF EXISTS party_checklist_items_admin_read ON party_checklist_items;
CREATE POLICY party_checklist_items_admin_read ON party_checklist_items
  FOR SELECT USING (is_admin());

COMMIT;
