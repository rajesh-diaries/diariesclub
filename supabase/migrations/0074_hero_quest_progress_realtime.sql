-- Add hero quest tables to supabase_realtime so the home + adventure
-- quest cards reflect server-side trigger writes (auto quest complete
-- on session_complete, healthy_bite, workshop_attend, etc.) without
-- the customer needing to refresh.

ALTER PUBLICATION supabase_realtime ADD TABLE hero_quest_progress;
ALTER PUBLICATION supabase_realtime ADD TABLE hero_quest_definitions;
ALTER PUBLICATION supabase_realtime ADD TABLE hero_quest_weeks;
