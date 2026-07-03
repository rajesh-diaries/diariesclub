-- 0211_reseed_venue_config_xp_thresholds.sql
-- REPO/PROD CONVERGENCE — pin the founder-tuned XP thresholds.
--
-- venue_config.stage_thresholds_per_trait and .level_thresholds were tuned live via the
-- admin console and diverge from the 0001_initial_schema column DEFAULTs:
--       stage_thresholds_per_trait  default [0,50,150,350,700]  -> live [0,300,800,1700,3000]
--       level_thresholds            default 21 values           -> live 20 values (below)
-- A from-scratch replay would otherwise revert to the old defaults and mis-stage every
-- child. This migration re-applies the LIVE values (read from prod 2026-07-03) so replay
-- reproduces prod.
--
-- The venue_config row is seeded in 0001_initial_schema.sql (INSERT INTO venue_config
-- (venue_id)), so this UPDATE always has a row to hit on a fresh replay.
--
-- IDEMPOTENT: sets the same constant values every run. On prod this is currently a no-op
-- (values already match). Scoped to the single founder venue; if more venues are added
-- later they inherit the 0001 defaults and would need their own tuning.

UPDATE public.venue_config
SET stage_thresholds_per_trait = '[0,300,800,1700,3000]'::jsonb,
    level_thresholds           = '[0,100,250,450,700,1000,1400,1900,2500,3200,4000,4900,5900,6900,7900,8900,9900,10900,11900,12500]'::jsonb
WHERE venue_id = '00000000-0000-0000-0000-000000000001';
