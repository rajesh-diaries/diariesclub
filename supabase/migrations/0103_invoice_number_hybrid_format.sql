-- 0103 — invoice number format: DC{YY}-{NNNNN}-{XXXX}
--   DC      Diaries Club prefix
--   YY      2-digit year (calendar year for now; revisit for FY later)
--   NNNNN   sequential, resets yearly, atomic via invoice_year_counters
--   XXXX    4-char random hex suffix (uppercase) so total volume isn't
--           inferable from sequential numbers alone
-- 15 chars total → under Rule 46's 16-char cap.

CREATE OR REPLACE FUNCTION _next_invoice_number()
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_year_full INTEGER := EXTRACT(YEAR FROM now() AT TIME ZONE 'Asia/Kolkata')::INTEGER;
  v_year_2d   TEXT    := RIGHT(v_year_full::TEXT, 2);
  v_n         INTEGER;
  v_suffix    TEXT;
BEGIN
  INSERT INTO invoice_year_counters(year, next_number) VALUES (v_year_full, 1)
    ON CONFLICT (year) DO UPDATE
      SET next_number = invoice_year_counters.next_number + 1
    RETURNING next_number INTO v_n;
  v_suffix := UPPER(SUBSTR(MD5(random()::TEXT || clock_timestamp()::TEXT), 1, 4));
  RETURN 'DC' || v_year_2d || '-' || LPAD(v_n::TEXT, 5, '0') || '-' || v_suffix;
END $$;
