-- 0084 — per-package experience inclusions (venue benefits)
--
-- Separate from menu inclusions (food). 'Experience' bullets cover
-- the venue stuff — play time, hall booking, buffet, decorations,
-- whatever the founder wants to surface alongside the menu. Each
-- package owns its own list so 'Magical' can advertise extras
-- (like 'Healthy gift box for birthday child') while 'Little Joy'
-- shows just the basics.

ALTER TABLE birthday_packages
  ADD COLUMN IF NOT EXISTS experience_inclusions JSONB DEFAULT '[]'::jsonb;

-- Seed all 4 with the same starting set; admin can customise each.
UPDATE birthday_packages
   SET experience_inclusions =
     '["2.5 hours play time", "3 hours hall booking", "Food buffet"]'::jsonb
 WHERE tier IN ('little_joy','happy_tales','grand','magical');
