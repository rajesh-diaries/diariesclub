-- Add admin-configurable mapping from kid count to sibling coupon code.
-- The session start screen reads this map and shows the actual coupon code (e.g. 2KIDS).

ALTER TABLE venue_config
ADD COLUMN IF NOT EXISTS sibling_coupon_codes JSONB;

-- Backfill the current venue with the new naming convention.
UPDATE venue_config
SET sibling_coupon_codes = '{
  "2": "2KIDS",
  "3": "3KIDS",
  "4": "4KIDS",
  "5": "5KIDS"
}'::jsonb
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Rename legacy SIBLING codes to the new convention.
UPDATE coupons
SET code = '3KIDS',
    updated_at = now()
WHERE code = 'SIBLING3'
  AND NOT EXISTS (SELECT 1 FROM coupons WHERE code = '3KIDS');

UPDATE coupons
SET code = '5KIDS',
    updated_at = now()
WHERE code = 'SIBLING5'
  AND NOT EXISTS (SELECT 1 FROM coupons WHERE code = '5KIDS');

-- Ensure 2KIDS has the same family-usage limit as the other sibling coupons.
UPDATE coupons
SET max_per_family = 1,
    updated_at = now()
WHERE code = '2KIDS';
