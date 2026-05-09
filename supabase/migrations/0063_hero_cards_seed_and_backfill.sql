-- 0063_hero_cards_seed_and_backfill.sql
--
-- Be the Hero Layer 2 — apply the proposed mapping to existing cards,
-- seed placeholder cards for the missing slots (Welcome + extra
-- surprises), and backfill every existing kid's stage cards based on
-- their current XP.
--
-- The mapping is admin-configurable: this migration just sets sensible
-- starting values that the founder can rewrite anytime in admin web.
--
-- After this lands, existing customers like Gaddam (Rafi 511 XP,
-- Champion stage) instantly see the Seedling, Explorer, Adventurer,
-- and Champion cards unlock in their Hero Atlas.

-- ---------------------------------------------------------------------
-- 1. Tag the existing 7 cards per hero with stage / surprise / birthday
-- ---------------------------------------------------------------------

-- Rafi (Brave) — first step → led → stood firm → kept trying → legend
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='seedling'   WHERE hero='rafi'  AND name='Brave Beginner';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='explorer'   WHERE hero='rafi'  AND name='First Charge';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='adventurer' WHERE hero='rafi'  AND name='Trusty Shield';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='champion'   WHERE hero='rafi'  AND name='Steady Stand';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='legend'     WHERE hero='rafi'  AND name='Lionheart';
UPDATE hero_card_definitions SET unlock_method='surprise', unlock_stage=NULL      WHERE hero='rafi'  AND name='Courage Crown';
-- Birthday Brave already migrated to unlock_method='birthday' in 0062.

-- Ellie (Kind) — sharing → helping → welcoming → thanking → heart of gold
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='seedling'   WHERE hero='ellie' AND name='Sharing Spirit';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='explorer'   WHERE hero='ellie' AND name='Helping Hand';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='adventurer' WHERE hero='ellie' AND name='Warm Welcome';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='champion'   WHERE hero='ellie' AND name='Kind Echo';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='legend'     WHERE hero='ellie' AND name='Heart of Gold';
UPDATE hero_card_definitions SET unlock_method='surprise', unlock_stage=NULL      WHERE hero='ellie' AND name='Gentle Giant';

-- Gerry (Curious) — wonder → question → tinker → detective → beacon
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='seedling'   WHERE hero='gerry' AND name='Wonder Walker';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='explorer'   WHERE hero='gerry' AND name='Question Spark';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='adventurer' WHERE hero='gerry' AND name='Tinkerer';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='champion'   WHERE hero='gerry' AND name='Tiny Detective';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='legend'     WHERE hero='gerry' AND name='Discovery Beacon';
UPDATE hero_card_definitions SET unlock_method='surprise', unlock_stage=NULL      WHERE hero='gerry' AND name='Mystery Seeker';

-- Zena (Creative) — doodle → idea → reuse → story → master maker
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='seedling'   WHERE hero='zena'  AND name='Doodler';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='explorer'   WHERE hero='zena'  AND name='Idea Spark';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='adventurer' WHERE hero='zena'  AND name='Junk Genius';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='champion'   WHERE hero='zena'  AND name='Storyteller';
UPDATE hero_card_definitions SET unlock_method='stage', unlock_stage='legend'     WHERE hero='zena'  AND name='Master Maker';
UPDATE hero_card_definitions SET unlock_method='surprise', unlock_stage=NULL      WHERE hero='zena'  AND name='Imaginarium';

-- ---------------------------------------------------------------------
-- 2. Seed Welcome cards (1 per hero, placeholder art — admin will edit)
-- ---------------------------------------------------------------------
INSERT INTO hero_card_definitions(name, hero, image_url, description, unlock_method, unlock_stage, is_rare, is_birthday_exclusive, is_active)
VALUES
  ('Welcome to Diaries', 'rafi',  'https://placehold.co/600x800/1E3A7B/F5C442.png?text=Welcome+Brave',     'Your first step into the brave world of Rafi.',     'stage', 'welcome', false, false, true),
  ('Welcome to Diaries', 'ellie', 'https://placehold.co/600x800/1E3A7B/F5C442.png?text=Welcome+Kind',      'Your first step into the kind world of Ellie.',     'stage', 'welcome', false, false, true),
  ('Welcome to Diaries', 'gerry', 'https://placehold.co/600x800/1E3A7B/F5C442.png?text=Welcome+Curious',   'Your first step into the curious world of Gerry.',  'stage', 'welcome', false, false, true),
  ('Welcome to Diaries', 'zena',  'https://placehold.co/600x800/1E3A7B/F5C442.png?text=Welcome+Creative',  'Your first step into the creative world of Zena.',  'stage', 'welcome', false, false, true)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Seed 3 more Surprise cards per hero (4 surprise total per hero
--    once we count the existing rare card moved to surprise)
-- ---------------------------------------------------------------------
INSERT INTO hero_card_definitions(name, hero, image_url, description, unlock_method, unlock_stage, is_rare, is_birthday_exclusive, is_active)
VALUES
  -- Rafi surprise placeholders
  ('Quiet Courage',    'rafi',  'https://placehold.co/600x800/E8524A/FFFFFF.png?text=Quiet+Courage',    'For brave moments only the staff noticed.',  'surprise', NULL, false, false, true),
  ('Tiny Hero',        'rafi',  'https://placehold.co/600x800/E8524A/FFFFFF.png?text=Tiny+Hero',        'A brave deed, perfectly remembered.',         'surprise', NULL, false, false, true),
  ('First Helper',     'rafi',  'https://placehold.co/600x800/E8524A/FFFFFF.png?text=First+Helper',     'Stepped up for a friend at exactly the right time.', 'surprise', NULL, false, false, true),
  -- Ellie surprise placeholders
  ('Quiet Kindness',   'ellie', 'https://placehold.co/600x800/4A90E2/FFFFFF.png?text=Quiet+Kindness',   'A kind moment only Ellie would have noticed.', 'surprise', NULL, false, false, true),
  ('Friend Maker',     'ellie', 'https://placehold.co/600x800/4A90E2/FFFFFF.png?text=Friend+Maker',     'Welcomed someone in their own special way.', 'surprise', NULL, false, false, true),
  ('Heartful Helper',  'ellie', 'https://placehold.co/600x800/4A90E2/FFFFFF.png?text=Heartful+Helper',  'Helped without anyone asking.',              'surprise', NULL, false, false, true),
  -- Gerry surprise placeholders
  ('Curious Watcher',  'gerry', 'https://placehold.co/600x800/F39C12/FFFFFF.png?text=Curious+Watcher',  'Spotted something everyone else missed.',    'surprise', NULL, false, false, true),
  ('Whys and Hows',    'gerry', 'https://placehold.co/600x800/F39C12/FFFFFF.png?text=Whys+and+Hows',    'Asked the most thoughtful question of the day.', 'surprise', NULL, false, false, true),
  ('Pattern Finder',   'gerry', 'https://placehold.co/600x800/F39C12/FFFFFF.png?text=Pattern+Finder',   'Connected dots no one else saw.',             'surprise', NULL, false, false, true),
  -- Zena surprise placeholders
  ('Tiny Inventor',    'zena',  'https://placehold.co/600x800/27AE60/FFFFFF.png?text=Tiny+Inventor',    'Made something that didn''t exist before.',  'surprise', NULL, false, false, true),
  ('Story Spinner',    'zena',  'https://placehold.co/600x800/27AE60/FFFFFF.png?text=Story+Spinner',    'Told a story that captured a room.',         'surprise', NULL, false, false, true),
  ('Wonder Maker',     'zena',  'https://placehold.co/600x800/27AE60/FFFFFF.png?text=Wonder+Maker',     'Turned an ordinary thing into magic.',       'surprise', NULL, false, false, true)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Backfill existing kids' stage cards based on current XP
-- ---------------------------------------------------------------------
-- Stage thresholds match venue_config default [0,50,150,350,700].
-- 0 XP only earns the welcome card.
-- Welcome card is granted to EVERY existing child regardless of XP.

DO $$
DECLARE
  v_child RECORD;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_stages TEXT[];
  v_stage TEXT;
  v_card_id UUID;
BEGIN
  FOR v_child IN
    SELECT id, xp_rafi, xp_ellie, xp_gerry, xp_zena
      FROM children
     WHERE deleted_at IS NULL
  LOOP
    FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
      v_trait_xp := CASE v_trait
        WHEN 'rafi'  THEN v_child.xp_rafi
        WHEN 'ellie' THEN v_child.xp_ellie
        WHEN 'gerry' THEN v_child.xp_gerry
        WHEN 'zena'  THEN v_child.xp_zena
      END;

      -- Welcome always granted (every existing kid gets the welcome card).
      v_stages := ARRAY['welcome'];
      IF v_trait_xp >= 1   THEN v_stages := array_append(v_stages, 'seedling');   END IF;
      IF v_trait_xp >= 50  THEN v_stages := array_append(v_stages, 'explorer');   END IF;
      IF v_trait_xp >= 150 THEN v_stages := array_append(v_stages, 'adventurer'); END IF;
      IF v_trait_xp >= 350 THEN v_stages := array_append(v_stages, 'champion');   END IF;
      IF v_trait_xp >= 700 THEN v_stages := array_append(v_stages, 'legend');     END IF;

      FOREACH v_stage IN ARRAY v_stages LOOP
        FOR v_card_id IN
          SELECT id FROM hero_card_definitions
           WHERE unlock_method = 'stage'
             AND hero = v_trait
             AND unlock_stage = v_stage
             AND is_active = true
        LOOP
          INSERT INTO hero_card_collection(child_id, card_id)
          VALUES (v_child.id, v_card_id)
          ON CONFLICT (child_id, card_id) DO NOTHING;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;
