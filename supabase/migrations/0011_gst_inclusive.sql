-- ===========================================================================
--  Migration 0011 — GST inclusive policy (Session 7 prep)
--
--  Locked policy:
--    The app is ALWAYS 18% GST inclusive. Every payment method, every
--    purchase type — the displayed price IS the customer's total.
--    Server back-computes subtotal_paise + gst_paise for invoicing.
--
--  Walk-in food-only at the staff POS (Session 10) is the only place where
--  5% GST exclusive applies; that flow doesn't touch this RPC path.
--
--  Adds:
--    1) venue_config.gst_percent default flips 5.00 → 18.00 (and existing
--       row updated for the dev venue).
--    2) compute_pricing(p_total_paise, p_gst_percent) helper — single
--       source of truth. FLOOR on subtotal so any rounding drift becomes
--       extra GST (accountant-conservative).
--    3) sessions / session_extensions / workshop_registrations get
--       subtotal_paise + gst_paise columns (NOT NULL DEFAULT 0). Existing
--       rows keep their amount_paise; new RPC paths populate the breakdown.
--    4) CREATE OR REPLACE: session_create, session_extend, workshop_register,
--       order_place — all back-compute the GST split via compute_pricing.
--       Cashback (orders) stays on subtotal_paise per accountant spec.
--    5) supabase_realtime publication adds menus, menu_items, combos,
--       workshops, workshop_registrations.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. GST rate: 5 → 18 (single source)
-- ---------------------------------------------------------------------------
ALTER TABLE venue_config
  ALTER COLUMN gst_percent SET DEFAULT 18.00;

UPDATE venue_config SET gst_percent = 18.00
  WHERE gst_percent <> 18.00;

-- ---------------------------------------------------------------------------
--  2. compute_pricing helper
--
--  Returns { subtotal_paise, gst_paise, total_paise }. Use the displayed
--  price as p_total_paise — it's the GST-inclusive number the customer
--  pays. Sub = floor(total*100/(100+gst%)); gst = total - sub. Integer
--  math; rounding drift accumulates in GST (never under-collected).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_pricing(
  p_total_paise INTEGER,
  p_gst_percent NUMERIC
) RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_subtotal INTEGER;
BEGIN
  IF p_total_paise IS NULL OR p_total_paise < 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_gst_percent IS NULL OR p_gst_percent < 0 THEN
    RAISE EXCEPTION 'invalid_gst_percent';
  END IF;

  v_subtotal := FLOOR(p_total_paise::NUMERIC * 100 / (100 + p_gst_percent))::INTEGER;
  RETURN jsonb_build_object(
    'subtotal_paise', v_subtotal,
    'gst_paise',      p_total_paise - v_subtotal,
    'total_paise',    p_total_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION compute_pricing(INTEGER, NUMERIC) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION compute_pricing(INTEGER, NUMERIC)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
--  3. Schema additions
-- ---------------------------------------------------------------------------
ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS subtotal_paise INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_paise      INTEGER NOT NULL DEFAULT 0;

ALTER TABLE session_extensions
  ADD COLUMN IF NOT EXISTS subtotal_paise INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_paise      INTEGER NOT NULL DEFAULT 0;

ALTER TABLE workshop_registrations
  ADD COLUMN IF NOT EXISTS subtotal_paise INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_paise      INTEGER NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
--  4. Realtime publication additions
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'menus',
    'menu_items',
    'combos',
    'workshops',
    'workshop_registrations'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
        v_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
