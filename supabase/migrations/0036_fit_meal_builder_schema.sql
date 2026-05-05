-- ===========================================================================
--  Migration 0036 — FIT meal builder schema (Module 2.5)
--
--  Six tables for the configurable FIT meal builder:
--
--    fit_meal_templates              — admin-defined meal cards
--    fit_meal_categories             — global option groups (Protein, Dip, Salad…)
--    fit_meal_options                — items inside a category (Chicken, Paneer…)
--    fit_meal_template_categories    — linker: which categories belong to template
--    fit_meal_orders                 — customer's selection record
--    fit_subscription_waitlist       — waitlist email capture
--
--  Pricing model: template has base_price_paise; each option may add an
--  upcharge_paise. Final price = base + Σ(selected option upcharges).
--  Compute is server-authoritative via fit_meal_compute_price (0037).
--
--  Reversibility:
--    DROP TABLE IF EXISTS
--      fit_subscription_waitlist,
--      fit_meal_orders,
--      fit_meal_template_categories,
--      fit_meal_options,
--      fit_meal_templates,
--      fit_meal_categories CASCADE;
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Categories — global option groups per venue.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_meal_categories (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id        UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  slug            TEXT NOT NULL,
  selection_type  TEXT NOT NULL CHECK (selection_type IN ('single','multi')),
  default_required BOOLEAN NOT NULL DEFAULT TRUE,
  display_order   INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (venue_id, slug)
);

-- ---------------------------------------------------------------------------
-- 2. Options — items inside a category. Owned by exactly one category
--    (FK + CASCADE). Reuse across categories deferred — duplicate the row
--    if you need it in two categories.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_meal_options (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id        UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  category_id     UUID NOT NULL REFERENCES fit_meal_categories(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  upcharge_paise  INTEGER NOT NULL DEFAULT 0 CHECK (upcharge_paise >= 0),
  is_available    BOOLEAN NOT NULL DEFAULT TRUE,
  is_published    BOOLEAN NOT NULL DEFAULT TRUE,
  display_order   INTEGER NOT NULL DEFAULT 0,
  nutrition_meta  JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fit_options_category
  ON fit_meal_options(category_id, display_order);

-- ---------------------------------------------------------------------------
-- 3. Templates — admin-defined meal cards.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_meal_templates (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id          UUID NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  base_price_paise  INTEGER NOT NULL CHECK (base_price_paise >= 0),
  photo_url         TEXT,
  is_subscribable   BOOLEAN NOT NULL DEFAULT FALSE,
  subscription_meta JSONB,
  is_published      BOOLEAN NOT NULL DEFAULT TRUE,
  is_available      BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order        INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fit_templates_published_sort
  ON fit_meal_templates(venue_id, sort_order)
  WHERE is_published = TRUE AND is_available = TRUE;

-- ---------------------------------------------------------------------------
-- 4. Linker: which categories does each template offer?
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_meal_template_categories (
  template_id              UUID NOT NULL REFERENCES fit_meal_templates(id) ON DELETE CASCADE,
  category_id              UUID NOT NULL REFERENCES fit_meal_categories(id) ON DELETE CASCADE,
  is_required              BOOLEAN NOT NULL DEFAULT TRUE,
  selection_type_override  TEXT CHECK (selection_type_override IN ('single','multi')),
  display_order            INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (template_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_fit_template_categories_template
  ON fit_meal_template_categories(template_id, display_order);

-- ---------------------------------------------------------------------------
-- 5. Customer order record. Cart integration TBD (separate commit) — the
--    selections_jsonb captures the build for record-keeping regardless of
--    how it gets into the cart.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_meal_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id             UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  template_id           UUID NOT NULL REFERENCES fit_meal_templates(id) ON DELETE RESTRICT,
  base_price_paise      INTEGER NOT NULL,
  total_upcharge_paise  INTEGER NOT NULL,
  final_price_paise     INTEGER NOT NULL,
  selections_jsonb      JSONB NOT NULL,
  status                TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','in_cart','ordered','cancelled')),
  ordered_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fit_meal_orders_family
  ON fit_meal_orders(family_id, ordered_at DESC);

-- ---------------------------------------------------------------------------
-- 6. Subscription waitlist
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fit_subscription_waitlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   UUID REFERENCES families(id) ON DELETE SET NULL,
  email       TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'interested'
              CHECK (status IN ('interested','contacted','onboarded','not_interested')),
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fit_waitlist_status
  ON fit_subscription_waitlist(status, created_at DESC);

-- One signup per family (when family_id present); allow duplicate emails
-- if family_id IS NULL (anonymous waitlist sign-ups, future-proof).
CREATE UNIQUE INDEX IF NOT EXISTS uq_fit_waitlist_family
  ON fit_subscription_waitlist(family_id)
  WHERE family_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RLS — customer reads (active templates/options only); admin all.
-- ---------------------------------------------------------------------------
ALTER TABLE fit_meal_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE fit_meal_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE fit_meal_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE fit_meal_template_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE fit_meal_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE fit_subscription_waitlist ENABLE ROW LEVEL SECURITY;

-- Categories: customer read all (display_order matters — they see the
-- full list when a template uses the category).
DROP POLICY IF EXISTS "fit_categories_customer_read" ON fit_meal_categories;
CREATE POLICY "fit_categories_customer_read"
  ON fit_meal_categories FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "fit_categories_admin_all" ON fit_meal_categories;
CREATE POLICY "fit_categories_admin_all"
  ON fit_meal_categories FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Options: customer reads only published+available; admin all.
DROP POLICY IF EXISTS "fit_options_customer_read" ON fit_meal_options;
CREATE POLICY "fit_options_customer_read"
  ON fit_meal_options FOR SELECT TO authenticated
  USING (is_published = TRUE AND is_available = TRUE);

DROP POLICY IF EXISTS "fit_options_admin_all" ON fit_meal_options;
CREATE POLICY "fit_options_admin_all"
  ON fit_meal_options FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Templates: customer reads only published+available; admin all.
DROP POLICY IF EXISTS "fit_templates_customer_read" ON fit_meal_templates;
CREATE POLICY "fit_templates_customer_read"
  ON fit_meal_templates FOR SELECT TO authenticated
  USING (is_published = TRUE AND is_available = TRUE);

DROP POLICY IF EXISTS "fit_templates_admin_all" ON fit_meal_templates;
CREATE POLICY "fit_templates_admin_all"
  ON fit_meal_templates FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Linker: customer reads anything pointing at a published template.
-- Admin all.
DROP POLICY IF EXISTS "fit_template_categories_customer_read" ON fit_meal_template_categories;
CREATE POLICY "fit_template_categories_customer_read"
  ON fit_meal_template_categories FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM fit_meal_templates t
      WHERE t.id = template_id AND t.is_published AND t.is_available
    )
  );

DROP POLICY IF EXISTS "fit_template_categories_admin_all" ON fit_meal_template_categories;
CREATE POLICY "fit_template_categories_admin_all"
  ON fit_meal_template_categories FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Orders: customer reads own; admin all. Insert via RPC only (no direct).
DROP POLICY IF EXISTS "fit_orders_owner_read" ON fit_meal_orders;
CREATE POLICY "fit_orders_owner_read"
  ON fit_meal_orders FOR SELECT TO authenticated
  USING (family_id = auth.uid()
         OR EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Waitlist: family inserts own; admin reads/writes all.
DROP POLICY IF EXISTS "fit_waitlist_family_insert" ON fit_subscription_waitlist;
CREATE POLICY "fit_waitlist_family_insert"
  ON fit_subscription_waitlist FOR INSERT TO authenticated
  WITH CHECK (family_id = auth.uid() OR family_id IS NULL);

DROP POLICY IF EXISTS "fit_waitlist_owner_read" ON fit_subscription_waitlist;
CREATE POLICY "fit_waitlist_owner_read"
  ON fit_subscription_waitlist FOR SELECT TO authenticated
  USING (family_id = auth.uid()
         OR EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

DROP POLICY IF EXISTS "fit_waitlist_admin_write" ON fit_subscription_waitlist;
CREATE POLICY "fit_waitlist_admin_write"
  ON fit_subscription_waitlist FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND is_active));

-- Realtime: templates + options + linker stream so admin edits land
-- instantly on customer screens.
ALTER PUBLICATION supabase_realtime ADD TABLE fit_meal_templates;
ALTER PUBLICATION supabase_realtime ADD TABLE fit_meal_options;
ALTER PUBLICATION supabase_realtime ADD TABLE fit_meal_categories;
ALTER PUBLICATION supabase_realtime ADD TABLE fit_meal_template_categories;

COMMIT;
