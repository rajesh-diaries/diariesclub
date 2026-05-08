-- 0058_order_items_brand_allow_combo.sql
--
-- order_place v2 (migration 0039) inserts combo lines into order_items
-- with brand='combo', but the original CHECK constraint only allows
-- ('coffee', 'fit'). Combo orders fail with 'order_items_brand_check'.
--
-- Widen the constraint to include 'combo'. Existing rows are unaffected;
-- they all use 'coffee' or 'fit' values that stay valid.

ALTER TABLE order_items
  DROP CONSTRAINT IF EXISTS order_items_brand_check;

ALTER TABLE order_items
  ADD CONSTRAINT order_items_brand_check
  CHECK (brand = ANY (ARRAY['coffee'::text, 'fit'::text, 'combo'::text]));
