-- 0135 — allow source='pool' on parent_logged_moments.
--
-- The pool RPC (log_parent_moments_pool, migration 0125) inserts
-- source='pool' for items that came from a multi-select pool
-- submission. The original table CHECK only allowed 'preset' or
-- 'custom' (from the legacy log_parent_moment RPC), so every pool
-- submission was failing with parent_logged_moments_source_check.
-- Extend the constraint to include 'pool' alongside the two existing
-- values.

ALTER TABLE parent_logged_moments
  DROP CONSTRAINT IF EXISTS parent_logged_moments_source_check;

ALTER TABLE parent_logged_moments
  ADD CONSTRAINT parent_logged_moments_source_check
  CHECK (source IN ('preset','custom','pool'));
