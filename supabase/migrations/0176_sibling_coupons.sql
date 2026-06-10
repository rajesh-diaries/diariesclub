-- Sibling auto-coupons for multi-kid session bookings
-- Applied automatically when parent selects 2+ kids on session start

INSERT INTO public.coupons (
  code, type, value, max_discount_paise, min_order_paise,
  max_uses, max_per_family, valid_from, valid_until, is_active, description
) VALUES
  ('SIBLING2', 'flat_off', 15000, NULL, 0, NULL, 1, now(), NULL, true, '₹150 off when booking 2 kids'),
  ('SIBLING3', 'flat_off', 30000, NULL, 0, NULL, 1, now(), NULL, true, '₹300 off when booking 3 kids'),
  ('SIBLING4', 'flat_off', 50000, NULL, 0, NULL, 1, now(), NULL, true, '₹500 off when booking 4 kids'),
  ('SIBLING5', 'flat_off', 70000, NULL, 0, NULL, 1, now(), NULL, true, '₹700 off when booking 5+ kids')
ON CONFLICT (code) DO UPDATE SET
  type = EXCLUDED.type,
  value = EXCLUDED.value,
  max_discount_paise = EXCLUDED.max_discount_paise,
  min_order_paise = EXCLUDED.min_order_paise,
  max_uses = EXCLUDED.max_uses,
  max_per_family = EXCLUDED.max_per_family,
  valid_from = EXCLUDED.valid_from,
  valid_until = EXCLUDED.valid_until,
  is_active = EXCLUDED.is_active,
  description = EXCLUDED.description,
  updated_at = now();
