-- 0096 — seed FIT Diaries meal-builder data
-- Three meal templates (Lean ₹345, Balanced ₹385, Power ₹435) wired
-- to shared + per-meal categories with all the options + upcharges
-- from the founder's printed menu.

DELETE FROM fit_meal_template_categories;
DELETE FROM fit_meal_options;
DELETE FROM fit_meal_categories;
DELETE FROM fit_meal_templates;

INSERT INTO fit_meal_templates(
  venue_id, name, description, base_price_paise,
  is_published, is_available, sort_order
) VALUES
('00000000-0000-0000-0000-000000000001', 'Lean Meal',
 'A clean, light meal. Pick your protein, signature flavour, and optional veggies.',
 34500, true, true, 1),
('00000000-0000-0000-0000-000000000001', 'Balanced Meal',
 'Protein + smart carbs + flavour, with optional veggies.',
 38500, true, true, 2),
('00000000-0000-0000-0000-000000000001', 'Power Meal',
 '200g protein, smart carbs, flavour, veggies, and a Power Pick add-on.',
 43500, true, true, 3);

INSERT INTO fit_meal_categories(
  venue_id, name, slug, selection_type, default_required, display_order
) VALUES
('00000000-0000-0000-0000-000000000001', 'Choice Of Signature Flavour',
 'signature_flavour', 'single', true, 1),
('00000000-0000-0000-0000-000000000001', 'Veggies',
 'veggies', 'single', false, 2),
('00000000-0000-0000-0000-000000000001', 'Choice Of Smart Carbs',
 'smart_carbs', 'single', true, 3),
('00000000-0000-0000-0000-000000000001', 'Choice Of Protein - 150gms (Lean)',
 'protein_lean', 'single', true, 4),
('00000000-0000-0000-0000-000000000001', 'Choice Of Protein - 150gms (Balanced)',
 'protein_balanced', 'single', true, 5),
('00000000-0000-0000-0000-000000000001', 'Choice Of Protein - 200g',
 'protein_power', 'single', true, 6),
('00000000-0000-0000-0000-000000000001', 'Power Pick',
 'power_addon', 'single', false, 7);

WITH cat AS (SELECT id, slug FROM fit_meal_categories)
INSERT INTO fit_meal_options(
  venue_id, category_id, name, upcharge_paise,
  is_available, is_published, display_order
)
SELECT '00000000-0000-0000-0000-000000000001',
       (SELECT id FROM cat WHERE slug = s.slug),
       s.name, s.upcharge, true, true, s.ord
FROM (VALUES
  ('signature_flavour', 'Rosemary Herb',     0,    1),
  ('signature_flavour', 'Sun Dried Tomato',  0,    2),
  ('signature_flavour', 'Korean Cashew',     0,    3),
  ('signature_flavour', 'Red Thai',          0,    4),
  ('signature_flavour', 'Butter Masala',     0,    5),
  ('signature_flavour', 'Palak Cream',       0,    6),
  ('signature_flavour', 'Chilli Coconut',    0,    7),
  ('signature_flavour', 'Green Thai',        0,    8),

  ('veggies', 'Sauteed Veggies', 0, 1),
  ('veggies', 'Boiled Veggies',  0, 2),

  ('smart_carbs', 'Herb Brown Rice',   0,    1),
  ('smart_carbs', 'Herb Basmati Rice', 0,    2),
  ('smart_carbs', 'Sourdough Bread',   2000, 3),
  ('smart_carbs', 'Herb Red Rice',     2000, 4),
  ('smart_carbs', 'Herb Quinoa Rice',  2000, 5),
  ('smart_carbs', 'Herb Jasmine Rice', 5000, 6),
  ('smart_carbs', 'Herb Black Rice',   5000, 7),

  ('protein_lean', 'Classic Herb Chicken', 0,    1),
  ('protein_lean', 'Classic Herb Tofu',    0,    2),
  ('protein_lean', 'Mushrooms',            0,    3),
  ('protein_lean', 'Classic Herb Paneer',  0,    4),
  ('protein_lean', 'Veg Protein Patties',  0,    5),
  ('protein_lean', 'Lemon Herb Fish',      3500, 6),

  ('protein_balanced', 'Classic Herb Chicken', 0,    1),
  ('protein_balanced', 'Classic Herb Tofu',    0,    2),
  ('protein_balanced', 'Mushrooms',            0,    3),
  ('protein_balanced', 'Veg Protein Patties',  0,    4),
  ('protein_balanced', 'Classic Herb Paneer',  0,    5),
  ('protein_balanced', 'High Protein Paneer',  3500, 6),
  ('protein_balanced', 'Lemon Herb Fish',      3500, 7),

  ('protein_power', 'Classic Herb Paneer',  0,    1),
  ('protein_power', 'Veg Protein Patties',  0,    2),
  ('protein_power', 'Mushrooms',            0,    3),
  ('protein_power', 'Classic Herb Tofu',    0,    4),
  ('protein_power', 'Classic Herb Chicken', 0,    5),
  ('protein_power', 'High Protein Paneer',  5000, 6),
  ('protein_power', 'Lemon Herb Fish',      5000, 7),

  ('power_addon', 'Beetroot Hummus', 0, 1),
  ('power_addon', 'Omlette',         0, 2),
  ('power_addon', 'Sunnyside Egg',   0, 3),
  ('power_addon', 'Mashed Potato',   0, 4),
  ('power_addon', 'Hummus',          0, 5),
  ('power_addon', 'Boiled Egg',      0, 6),
  ('power_addon', 'Fried Egg',       0, 7),
  ('power_addon', 'Scrambled Egg',   0, 8)
) AS s(slug, name, upcharge, ord);

WITH cat AS (SELECT id, slug FROM fit_meal_categories),
     tpl AS (SELECT id, name FROM fit_meal_templates)
INSERT INTO fit_meal_template_categories(
  template_id, category_id, is_required, display_order
)
SELECT (SELECT id FROM tpl WHERE name = m.tpl),
       (SELECT id FROM cat WHERE slug = m.slug),
       m.required, m.ord
FROM (VALUES
  ('Lean Meal',      'protein_lean',       true,  1),
  ('Lean Meal',      'signature_flavour',  true,  2),
  ('Lean Meal',      'veggies',            false, 3),
  ('Balanced Meal',  'protein_balanced',   true,  1),
  ('Balanced Meal',  'smart_carbs',        true,  2),
  ('Balanced Meal',  'signature_flavour',  true,  3),
  ('Balanced Meal',  'veggies',            false, 4),
  ('Power Meal',     'protein_power',      true,  1),
  ('Power Meal',     'smart_carbs',        true,  2),
  ('Power Meal',     'signature_flavour',  true,  3),
  ('Power Meal',     'veggies',            false, 4),
  ('Power Meal',     'power_addon',        false, 5)
) AS m(tpl, slug, required, ord);
