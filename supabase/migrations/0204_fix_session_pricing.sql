-- Align server-side session pricing with the app/staff hardcoded prices
-- and the business requirement (₹800/1hr, ₹1100/2hr).
UPDATE venue_config
SET session_1hr_price_paise = 80000,
    session_2hr_price_paise = 110000,
    updated_at = now()
WHERE venue_id = '00000000-0000-0000-0000-000000000001';
