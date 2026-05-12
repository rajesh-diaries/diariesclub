-- 0122 — drop NOT NULL on stage_perk_grants.expires_at.
--
-- Hotfix for a regression where unchosen perk slots (empty placeholders
-- created at stage transition, before the customer picks a reward)
-- couldn't be inserted because expires_at was still NOT NULL.
--
-- Migration 0119 declared this ALTER but it wasn't applied to the live
-- DB until later; this migration is the durable copy on disk so any
-- fresh build picks it up. Once a customer picks a reward, expires_at
-- gets populated by stage_perk_pick from the perk's validity_days.

ALTER TABLE stage_perk_grants ALTER COLUMN expires_at DROP NOT NULL;
