-- 0099 — veggies + salad come with every meal by default. Stop
-- showing them as a customer pick. Also add a description column on
-- fit_meal_categories so the protein category can carry the
-- '150g raw weight · cooked to order' subtitle.

ALTER TABLE fit_meal_categories
  ADD COLUMN IF NOT EXISTS description TEXT;

DELETE FROM fit_meal_template_categories
 WHERE category_id = (SELECT id FROM fit_meal_categories WHERE slug='veggies');

WITH ranked AS (
  SELECT
    tc.ctid,
    ROW_NUMBER() OVER (
      PARTITION BY tc.template_id
      ORDER BY tc.display_order
    ) AS new_order
  FROM fit_meal_template_categories tc
)
UPDATE fit_meal_template_categories tc
   SET display_order = r.new_order
  FROM ranked r
 WHERE tc.ctid = r.ctid;

UPDATE fit_meal_categories SET description = '150g raw weight · cooked to order'
 WHERE slug IN ('protein_lean','protein_balanced');
UPDATE fit_meal_categories SET description = '200g raw weight · cooked to order'
 WHERE slug = 'protein_power';
