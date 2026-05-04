-- ===========================================================================
--  Migration 0013 — Adventure tab Realtime additions
--
--  Adds the four tables the Adventure dashboard subscribes to so the
--  hero card collection, stage-history timeline, streak tracker, and the
--  Wall of Legends sub-screen update live.
--
--  No new tables, views, or RPCs — Adventure does its joins client-side
--  (per Session 8 plan: composition over views).
-- ===========================================================================

BEGIN;

DO $$
DECLARE
  v_table TEXT;
  v_tables TEXT[] := ARRAY[
    'hero_card_collection',
    'xp_events',
    'streak_records',
    'wall_of_legends_daily'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = v_table
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',
        v_table
      );
    END IF;
  END LOOP;
END $$;

COMMIT;
