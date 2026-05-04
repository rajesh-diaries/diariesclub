-- ===========================================================================
--  Migration 0012 — Menu seed (Coffee + FIT + Combos) + helper view
--
--  Seeds 1 Coffee menu (15 items), 1 FIT menu (12 items), and 4 combos.
--  All prices are GST-INCLUSIVE per locked policy (the displayed value IS
--  the customer's total). Menu images use placehold.co URLs tinted to the
--  brand color — admin will swap these to real artwork pre-launch.
--
--  Combos store their item references in `inclusions.menu_item_ids`. The
--  two Play+X bundles also carry `session_minutes`; the play portion is
--  redeemed at the venue desk for v1 (cross-domain combo fulfillment is
--  Session 10+ work). The order-side RPC simply uses combo.price_paise as
--  the total override; the food line items get fulfilled via order_items.
--
--  TODO(founder): real menu items (names, descriptions, photos), final
--  pricing, allergens, real combos.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
--  1. Menus (one per brand for the dev venue)
-- ---------------------------------------------------------------------------
INSERT INTO menus (id, venue_id, brand, name)
VALUES
  ('11111111-1111-1111-1111-111111111111',
   '00000000-0000-0000-0000-000000000001', 'coffee', 'Coffee Diaries'),
  ('22222222-2222-2222-2222-222222222222',
   '00000000-0000-0000-0000-000000000001', 'fit',    'FIT Diaries')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
--  2. Coffee Diaries — 15 items
--     Categories: espresso (4), tea (3), cold (4), bites (4)
-- ---------------------------------------------------------------------------
DELETE FROM menu_items
  WHERE menu_id = '11111111-1111-1111-1111-111111111111';

INSERT INTO menu_items (menu_id, name, description, price_paise, image_url, category, sort_order) VALUES
  -- Espresso
  ('11111111-1111-1111-1111-111111111111', 'Cappuccino', 'Single-shot espresso with steamed milk and foam.',           22000, 'https://placehold.co/400x300/D4A473/FFFFFF.png?text=Cappuccino',  'espresso', 10),
  ('11111111-1111-1111-1111-111111111111', 'Latte',      'Espresso with velvety steamed milk.',                        24000, 'https://placehold.co/400x300/D4A473/FFFFFF.png?text=Latte',       'espresso', 20),
  ('11111111-1111-1111-1111-111111111111', 'Americano',  'Espresso with hot water — long and clean.',                  18000, 'https://placehold.co/400x300/D4A473/FFFFFF.png?text=Americano',   'espresso', 30),
  ('11111111-1111-1111-1111-111111111111', 'Espresso',   'Single shot of bold espresso.',                              14000, 'https://placehold.co/400x300/D4A473/FFFFFF.png?text=Espresso',    'espresso', 40),
  -- Tea
  ('11111111-1111-1111-1111-111111111111', 'Masala Chai','Spiced Indian tea, brewed strong.',                          12000, 'https://placehold.co/400x300/E8A57F/FFFFFF.png?text=Masala+Chai', 'tea',      110),
  ('11111111-1111-1111-1111-111111111111', 'Green Tea',  'Steeped with care.',                                         15000, 'https://placehold.co/400x300/7BC74D/FFFFFF.png?text=Green+Tea',   'tea',      120),
  ('11111111-1111-1111-1111-111111111111', 'Lemon Tea',  'Black tea with fresh lemon.',                                13000, 'https://placehold.co/400x300/F5C442/FFFFFF.png?text=Lemon+Tea',   'tea',      130),
  -- Cold
  ('11111111-1111-1111-1111-111111111111', 'Cold Brew',  '12-hour steeped cold brew.',                                 26000, 'https://placehold.co/400x300/4A2C2A/FFFFFF.png?text=Cold+Brew',   'cold',     210),
  ('11111111-1111-1111-1111-111111111111', 'Iced Latte', 'Espresso poured over cold milk + ice.',                      25000, 'https://placehold.co/400x300/8B5A3C/FFFFFF.png?text=Iced+Latte',  'cold',     220),
  ('11111111-1111-1111-1111-111111111111', 'Smoothie',   'Seasonal fruit smoothie.',                                   28000, 'https://placehold.co/400x300/E8524A/FFFFFF.png?text=Smoothie',    'cold',     230),
  ('11111111-1111-1111-1111-111111111111', 'Frappe',     'Blended iced coffee, sweet and frothy.',                     24000, 'https://placehold.co/400x300/6F4E37/FFFFFF.png?text=Frappe',      'cold',     240),
  -- Bites
  ('11111111-1111-1111-1111-111111111111', 'Croissant',  'Buttery, flaky.',                                            16000, 'https://placehold.co/400x300/F5C442/FFFFFF.png?text=Croissant',   'bites',    310),
  ('11111111-1111-1111-1111-111111111111', 'Sandwich',   'Grilled veggie sandwich.',                                   22000, 'https://placehold.co/400x300/E8A57F/FFFFFF.png?text=Sandwich',    'bites',    320),
  ('11111111-1111-1111-1111-111111111111', 'Brownie',    'Fudgy, with sea salt.',                                      18000, 'https://placehold.co/400x300/4A2C2A/FFFFFF.png?text=Brownie',     'bites',    330),
  ('11111111-1111-1111-1111-111111111111', 'Cookie',     'Classic chocolate chip.',                                    12000, 'https://placehold.co/400x300/8B5A3C/FFFFFF.png?text=Cookie',      'bites',    340);

-- ---------------------------------------------------------------------------
--  3. FIT Diaries — 12 items
--     Categories: smoothie (4), bowl (4), wrap (4)
-- ---------------------------------------------------------------------------
DELETE FROM menu_items
  WHERE menu_id = '22222222-2222-2222-2222-222222222222';

INSERT INTO menu_items (menu_id, name, description, price_paise, image_url, category, sort_order) VALUES
  -- Smoothies
  ('22222222-2222-2222-2222-222222222222', 'Berry Boost',   'Mixed berries, banana, almond milk.',          28000, 'https://placehold.co/400x300/E8524A/FFFFFF.png?text=Berry+Boost',   'smoothie', 10),
  ('22222222-2222-2222-2222-222222222222', 'Mango Protein', 'Mango, whey, oats, honey.',                    32000, 'https://placehold.co/400x300/F0A830/FFFFFF.png?text=Mango+Protein', 'smoothie', 20),
  ('22222222-2222-2222-2222-222222222222', 'Green Detox',   'Spinach, apple, ginger, lemon.',               26000, 'https://placehold.co/400x300/7BC74D/FFFFFF.png?text=Green+Detox',   'smoothie', 30),
  ('22222222-2222-2222-2222-222222222222', 'Banana Almond', 'Banana, almond butter, oat milk.',             24000, 'https://placehold.co/400x300/F5C442/FFFFFF.png?text=Banana+Almond', 'smoothie', 40),
  -- Bowls
  ('22222222-2222-2222-2222-222222222222', 'Acai Bowl',     'Acai, granola, fresh fruit.',                  45000, 'https://placehold.co/400x300/9B6BC8/FFFFFF.png?text=Acai+Bowl',     'bowl',     110),
  ('22222222-2222-2222-2222-222222222222', 'Quinoa Bowl',   'Quinoa, roasted veg, tahini drizzle.',         42000, 'https://placehold.co/400x300/0D4A2E/FFFFFF.png?text=Quinoa+Bowl',   'bowl',     120),
  ('22222222-2222-2222-2222-222222222222', 'Buddha Bowl',   'Brown rice, chickpeas, greens, hummus.',       38000, 'https://placehold.co/400x300/0D4A2E/FFFFFF.png?text=Buddha+Bowl',   'bowl',     130),
  ('22222222-2222-2222-2222-222222222222', 'Power Bowl',    'Chicken, sweet potato, avocado, kale.',        40000, 'https://placehold.co/400x300/E8524A/FFFFFF.png?text=Power+Bowl',    'bowl',     140),
  -- Wraps
  ('22222222-2222-2222-2222-222222222222', 'Chicken Wrap',  'Grilled chicken, slaw, herb mayo.',            35000, 'https://placehold.co/400x300/0D4A2E/FFFFFF.png?text=Chicken+Wrap',  'wrap',     210),
  ('22222222-2222-2222-2222-222222222222', 'Veggie Wrap',   'Roasted veg, hummus, mixed greens.',           32000, 'https://placehold.co/400x300/7BC74D/FFFFFF.png?text=Veggie+Wrap',   'wrap',     220),
  ('22222222-2222-2222-2222-222222222222', 'Egg Wrap',      'Scrambled egg, cheese, peppers.',              30000, 'https://placehold.co/400x300/F5C442/FFFFFF.png?text=Egg+Wrap',      'wrap',     230),
  ('22222222-2222-2222-2222-222222222222', 'Hummus Wrap',   'Hummus, cucumber, tomato, feta.',              28000, 'https://placehold.co/400x300/0D4A2E/FFFFFF.png?text=Hummus+Wrap',   'wrap',     240);

-- ---------------------------------------------------------------------------
--  4. Combos (4 bundles, prices GST-inclusive)
--
--  Play+X combos carry session_minutes in inclusions; the play side is
--  redeemed at the venue desk for v1. order_place treats combo.price_paise
--  as the cart total override; food line items still get fulfilled via
--  order_items. UI surfaces the full inclusions list on the combo card.
-- ---------------------------------------------------------------------------
DELETE FROM combos WHERE venue_id = '00000000-0000-0000-0000-000000000001';

INSERT INTO combos (venue_id, name, description, cover_image_url, price_paise, inclusions, sort_order) VALUES
  ('00000000-0000-0000-0000-000000000001',
   'Play + Coffee',
   '1hr play session paired with our signature Cappuccino.',
   'https://placehold.co/800x450/1E3A7B/F5C442.png?text=Play+%2B+Coffee',
   95000,
   jsonb_build_object(
     'session_minutes', 60,
     'menu_item_ids', jsonb_build_array(
       (SELECT id FROM menu_items WHERE name = 'Cappuccino' AND menu_id = '11111111-1111-1111-1111-111111111111')
     ),
     'description', '1hr play session + Cappuccino'
   ),
   10),

  ('00000000-0000-0000-0000-000000000001',
   'Play + FIT',
   '1hr play session paired with a Buddha Bowl.',
   'https://placehold.co/800x450/1E3A7B/7BC74D.png?text=Play+%2B+FIT',
   110000,
   jsonb_build_object(
     'session_minutes', 60,
     'menu_item_ids', jsonb_build_array(
       (SELECT id FROM menu_items WHERE name = 'Buddha Bowl' AND menu_id = '22222222-2222-2222-2222-222222222222')
     ),
     'description', '1hr play session + Buddha Bowl'
   ),
   20),

  ('00000000-0000-0000-0000-000000000001',
   'After-Play Treat',
   'Cappuccino with a fudgy brownie.',
   'https://placehold.co/800x450/D4A473/FFFFFF.png?text=After-Play+Treat',
   35000,
   jsonb_build_object(
     'menu_item_ids', jsonb_build_array(
       (SELECT id FROM menu_items WHERE name = 'Cappuccino' AND menu_id = '11111111-1111-1111-1111-111111111111'),
       (SELECT id FROM menu_items WHERE name = 'Brownie'    AND menu_id = '11111111-1111-1111-1111-111111111111')
     ),
     'description', 'Cappuccino + Brownie'
   ),
   30),

  ('00000000-0000-0000-0000-000000000001',
   'Recovery Combo',
   'Berry Boost smoothie with Banana Almond.',
   'https://placehold.co/800x450/7BC74D/FFFFFF.png?text=Recovery+Combo',
   48000,
   jsonb_build_object(
     'menu_item_ids', jsonb_build_array(
       (SELECT id FROM menu_items WHERE name = 'Berry Boost'   AND menu_id = '22222222-2222-2222-2222-222222222222'),
       (SELECT id FROM menu_items WHERE name = 'Banana Almond' AND menu_id = '22222222-2222-2222-2222-222222222222')
     ),
     'description', 'Berry Boost + Banana Almond'
   ),
   40);

-- ---------------------------------------------------------------------------
--  5. menu_items_with_brand view (Realtime-friendly)
--
--  supabase_flutter's `.stream()` doesn't join, so the client needs a flat
--  view to filter menu items by brand. RLS on menu_items + menus is open
--  for SELECT (public read of the menu), so a security_invoker view is
--  fine here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.menu_items_with_brand
WITH (security_invoker = true) AS
SELECT
  mi.id, mi.menu_id, m.brand, m.venue_id,
  mi.name, mi.description, mi.price_paise, mi.image_url,
  mi.category, mi.allergens, mi.is_available,
  mi.sort_order, mi.updated_at
FROM menu_items mi
JOIN menus m ON m.id = mi.menu_id;

GRANT SELECT ON public.menu_items_with_brand TO authenticated, anon;

COMMIT;
