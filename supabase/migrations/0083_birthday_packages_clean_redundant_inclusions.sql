-- 0083 — strip redundant entries from inclusion bullets
--
-- 'Hall: X' and 'Min N guests' duplicated info already shown in the
-- package card header ('Pearl · 20–40 guests'). Keep only the menu
-- bullets so the UI can render them as a 2-column grid without
-- noise.

UPDATE birthday_packages
   SET inclusions = '["1 Welcome Drink", "2 Starters", "2 Main Course", "1 Dessert"]'::jsonb
 WHERE tier = 'little_joy';

UPDATE birthday_packages
   SET inclusions = '["2 Welcome Drinks", "3 Starters", "3 Main Course", "1 Dessert"]'::jsonb
 WHERE tier = 'happy_tales';

UPDATE birthday_packages
   SET inclusions = '["2 Welcome Drinks", "4 Starters", "1 Salad", "1 Soup", "4 Main Course", "2 Dessert", "Accompaniments: sambar, pickle, papad, fresh set curd"]'::jsonb
 WHERE tier = 'grand';

UPDATE birthday_packages
   SET inclusions = '["2 Welcome Drinks", "5 Starters", "1 Salad", "1 Soup", "5 Main Course", "2 Dessert", "Accompaniments", "Healthy gift box for the birthday child"]'::jsonb
 WHERE tier = 'magical';
