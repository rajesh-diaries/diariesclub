-- 0100 — GST + invoice infrastructure
--
-- Splits venue tax into:
--   * Sessions / play passes: 18% GST (HSN 9996), INCLUSIVE in
--     the displayed ₹800/₹1100 price. Back-calculated at billing.
--   * Food (Coffee, FIT, Combo food portion, walk-in): 5% GST
--     (HSN 9963), ADDED on top of the displayed pre-GST price.
-- Combos already encode their session portion in
-- combo.inclusions.session_minutes (60 / 120 / null), so order_place
-- can back-out session_value from session_Xhr_price_paise.
--
-- Adds invoice numbering scheme INV-YYYY-NNNNN reset yearly via an
-- atomic counter table.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS gstin TEXT,
  ADD COLUMN IF NOT EXISTS food_gst_percent INTEGER DEFAULT 5,
  ADD COLUMN IF NOT EXISTS business_name TEXT DEFAULT 'Diaries Club';

UPDATE venue_config SET
  gstin = '36ABGFP4029B1ZJ',
  food_gst_percent = 5,
  business_name = 'Diaries Club'
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS invoice_number TEXT,
  ADD COLUMN IF NOT EXISTS customer_gstin TEXT,
  ADD COLUMN IF NOT EXISTS food_taxable_paise INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS food_gst_paise INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS session_value_paise INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS session_taxable_paise INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS session_gst_paise INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rounding_paise INTEGER DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS orders_invoice_number_unique
  ON orders(invoice_number) WHERE invoice_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS invoice_year_counters (
  year INTEGER PRIMARY KEY,
  next_number INTEGER NOT NULL DEFAULT 1
);

CREATE OR REPLACE FUNCTION _next_invoice_number()
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_year INTEGER := EXTRACT(YEAR FROM now() AT TIME ZONE 'Asia/Kolkata')::INTEGER;
  v_n INTEGER;
BEGIN
  INSERT INTO invoice_year_counters(year, next_number) VALUES (v_year, 1)
    ON CONFLICT (year) DO UPDATE
      SET next_number = invoice_year_counters.next_number + 1
    RETURNING next_number INTO v_n;
  RETURN 'INV-' || v_year::TEXT || '-' || LPAD(v_n::TEXT, 5, '0');
END $$;
