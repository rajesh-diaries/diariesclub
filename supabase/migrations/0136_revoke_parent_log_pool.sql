-- 0136 — retire the at-home parent-log feature.
--
-- Founder's call: XP only comes from real activity at the venue.
-- Customers can no longer log moments from anywhere/anytime to earn
-- XP at home. Revoke EXECUTE on both pool and legacy single-tap RPCs.
-- Function definitions stay so audit history (past parent_logged_moments
-- rows + Diary panel in admin) keeps reading cleanly; no future inserts.

REVOKE EXECUTE ON FUNCTION public.log_parent_moments_pool(UUID, JSONB)
  FROM authenticated, anon;

REVOKE EXECUTE ON FUNCTION public.log_parent_moment(UUID, TEXT, TEXT, TEXT)
  FROM authenticated, anon;
