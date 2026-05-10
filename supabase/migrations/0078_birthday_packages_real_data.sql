-- 0078 — birthday packages: real seed data + schema for hall/min-guests/per-pax pricing
--
-- Replaces the 3 placeholder packages (Birthday Basics, Hero Adventure,
-- Legendary Birthday) with the actual 4 packages from the printed
-- poster: Little Joy, Happy Tales, Grand, Magical.
--
-- Adds columns to birthday_packages so the discover screen can show
-- per-pax veg/non-veg pricing, hall name, and min/max guest range.
-- Adds a 'slot' column to birthday_reservations so the inquiry form
-- captures Morning vs Evening preference.

-- ── birthday_packages columns ────────────────────────────────────────────
ALTER TABLE birthday_packages
  ADD COLUMN IF NOT EXISTS hall_name TEXT,
  ADD COLUMN IF NOT EXISTS min_guests INTEGER,
  ADD COLUMN IF NOT EXISTS max_guests INTEGER,
  ADD COLUMN IF NOT EXISTS price_per_pax_veg_paise INTEGER,
  ADD COLUMN IF NOT EXISTS price_per_pax_non_veg_paise INTEGER;

-- price_paise was NOT NULL with placeholder values. Going forward we
-- use price_per_pax_*. Make it nullable so future packages can omit it.
ALTER TABLE birthday_packages
  ALTER COLUMN price_paise DROP NOT NULL;
ALTER TABLE birthday_packages
  ALTER COLUMN deposit_paise DROP NOT NULL;
ALTER TABLE birthday_packages
  ALTER COLUMN max_kids DROP NOT NULL;
ALTER TABLE birthday_packages
  ALTER COLUMN max_adults DROP NOT NULL;

-- ── birthday_reservations slot column ───────────────────────────────────
ALTER TABLE birthday_reservations
  ADD COLUMN IF NOT EXISTS slot TEXT
    CHECK (slot IS NULL OR slot IN ('morning','evening'));

-- num_adults was NOT NULL — relax so the simplified inquiry form (one
-- guest-count input) can submit without forcing a kids/adults split.
ALTER TABLE birthday_reservations
  ALTER COLUMN num_adults DROP NOT NULL;
ALTER TABLE birthday_reservations
  ALTER COLUMN balance_paise DROP NOT NULL;
ALTER TABLE birthday_reservations
  ALTER COLUMN package_price_paise DROP NOT NULL;

-- ── wipe placeholder packages ────────────────────────────────────────────
-- Safe to delete: no real reservations have referenced these placeholder
-- ids in production yet.
DELETE FROM birthday_packages
 WHERE tier IN ('basic','hero_adventure','legendary')
   AND name IN ('Birthday Basics','Hero Adventure','Legendary Birthday');

-- ── seed real packages ──────────────────────────────────────────────────
INSERT INTO birthday_packages (
  venue_id, name, tier, hall_name,
  min_guests, max_guests,
  price_per_pax_veg_paise, price_per_pax_non_veg_paise,
  duration_hours,
  inclusions, menu_options, non_food_offerings,
  hero_theme, sort_order, is_active
) VALUES
-- Little Joy ─────────────────────────────────────────────────────────────
(
  '00000000-0000-0000-0000-000000000001',
  'Little Joy', 'little_joy', 'Pearl',
  20, 40,
  99900, 114900,
  3,
  '["Hall: Pearl", "Min 20 guests", "1 Welcome Drink", "2 Starters", "2 Main Course", "1 Dessert"]'::jsonb,
  '{"welcome_drinks": 1, "starters": 2, "mains": 2, "dessert": 1, "salad": 0, "soup": 0, "accompaniments": false, "gift_box": false}'::jsonb,
  '[]'::jsonb,
  'mixed', 1, true
),
-- Happy Tales ───────────────────────────────────────────────────────────
(
  '00000000-0000-0000-0000-000000000001',
  'Happy Tales', 'happy_tales', 'Pearl',
  20, 40,
  119900, 134900,
  3,
  '["Hall: Pearl", "Min 20 guests", "2 Welcome Drinks", "3 Starters", "3 Main Course", "1 Dessert"]'::jsonb,
  '{"welcome_drinks": 2, "starters": 3, "mains": 3, "dessert": 1, "salad": 0, "soup": 0, "accompaniments": false, "gift_box": false}'::jsonb,
  '[]'::jsonb,
  'mixed', 2, true
),
-- Grand ──────────────────────────────────────────────────────────────────
(
  '00000000-0000-0000-0000-000000000001',
  'Grand', 'grand', 'The Grand',
  40, 200,
  129900, 149900,
  3,
  '["Hall: The Grand", "Min 40 guests", "2 Welcome Drinks", "4 Starters", "1 Salad", "1 Soup", "4 Main Course", "2 Dessert", "Accompaniments: Sambar, pickle, papad and fresh set curd"]'::jsonb,
  '{"welcome_drinks": 2, "starters": 4, "mains": 4, "dessert": 2, "salad": 1, "soup": 1, "accompaniments": true, "gift_box": false}'::jsonb,
  '[]'::jsonb,
  'mixed', 3, true
),
-- Magical ───────────────────────────────────────────────────────────────
(
  '00000000-0000-0000-0000-000000000001',
  'Magical', 'magical', 'The Grand',
  40, 200,
  149900, 169900,
  3,
  '["Hall: The Grand", "Min 40 guests", "2 Welcome Drinks", "5 Starters", "1 Salad", "1 Soup", "5 Main Course", "2 Dessert", "Accompaniments", "Healthy gift box for Birthday Child"]'::jsonb,
  '{"welcome_drinks": 2, "starters": 5, "mains": 5, "dessert": 2, "salad": 1, "soup": 1, "accompaniments": true, "gift_box": true}'::jsonb,
  '[]'::jsonb,
  'mixed', 4, true
);
