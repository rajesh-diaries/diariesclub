-- 0119 — Stage perks: choose-your-reward at claim time.
--
-- Each stage transition (per trait, per kid — unchanged) grants one slot.
-- Admin can configure 2+ active perks per stage; the customer picks one
-- in-app at claim time. If only one perk is active, we auto-pick so the
-- old single-option flow keeps working. If zero are active, we skip the
-- grant entirely (no dead slots).
--
-- Admin can swap which perks are active anytime — unchosen slots
-- immediately show the new options because perk_id is still NULL. Once
-- chosen, perk_id locks and the expiry clock starts.

-- 1. Make perk_id + code nullable; add chosen_at. -----------------------

ALTER TABLE stage_perk_grants ALTER COLUMN perk_id     DROP NOT NULL;
ALTER TABLE stage_perk_grants ALTER COLUMN code        DROP NOT NULL;
ALTER TABLE stage_perk_grants ALTER COLUMN expires_at  DROP NOT NULL;
ALTER TABLE stage_perk_grants
  ADD COLUMN IF NOT EXISTS chosen_at TIMESTAMPTZ;

-- 2. Helper: grant one slot per (trait, stage) ---------------------------
--   * 0 active perks → skip (no slot inserted)
--   * 1 active perk  → auto-pick (perk_id + code + chosen_at set now)
--   * 2+ active perks → empty slot (perk_id NULL) for customer to pick

CREATE OR REPLACE FUNCTION public._grant_stage_perk_slot(
  p_child_id   UUID,
  p_family_id  UUID,
  p_venue_id   UUID,
  p_trait      TEXT,
  p_stage      TEXT,
  OUT granted  JSONB
) LANGUAGE plpgsql AS $$
DECLARE
  v_active_count INTEGER;
  v_perk         stage_perks%ROWTYPE;
  v_code         TEXT;
  v_grant_id     UUID;
BEGIN
  SELECT count(*) INTO v_active_count FROM stage_perks
   WHERE stage = p_stage AND is_active = true
     AND (venue_id IS NULL OR venue_id = p_venue_id);

  IF v_active_count = 0 THEN
    granted := jsonb_build_object('skipped', true, 'reason', 'no_active_perks');
    RETURN;
  END IF;

  IF v_active_count = 1 THEN
    SELECT * INTO v_perk FROM stage_perks
     WHERE stage = p_stage AND is_active = true
       AND (venue_id IS NULL OR venue_id = p_venue_id);
    v_code := _generate_stage_perk_code();
    INSERT INTO stage_perk_grants(
      child_id, family_id, stage, trait, perk_id, code,
      chosen_at, expires_at
    ) VALUES (
      p_child_id, p_family_id, p_stage, p_trait, v_perk.id, v_code,
      now(), now() + make_interval(days => v_perk.validity_days)
    ) RETURNING id INTO v_grant_id;
    granted := jsonb_build_object(
      'grant_id', v_grant_id, 'auto_picked', true,
      'perk_id', v_perk.id, 'label', v_perk.perk_label, 'code', v_code,
      'stage', p_stage, 'trait', p_trait
    );
    RETURN;
  END IF;

  INSERT INTO stage_perk_grants(
    child_id, family_id, stage, trait, perk_id, code, expires_at
  ) VALUES (
    p_child_id, p_family_id, p_stage, p_trait, NULL, NULL, NULL
  ) RETURNING id INTO v_grant_id;

  granted := jsonb_build_object(
    'grant_id', v_grant_id, 'auto_picked', false,
    'options_count', v_active_count,
    'stage', p_stage, 'trait', p_trait
  );
END $$;

-- 3. RPC: customer picks one of the active options for an empty slot ----

CREATE OR REPLACE FUNCTION public.stage_perk_pick(
  p_grant_id UUID,
  p_perk_id  UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_grant stage_perk_grants%ROWTYPE;
  v_perk  stage_perks%ROWTYPE;
  v_code  TEXT;
BEGIN
  SELECT * INTO v_grant FROM stage_perk_grants
   WHERE id = p_grant_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'grant_not_found'; END IF;
  IF v_grant.family_id <> auth_family_id() THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;
  IF v_grant.perk_id IS NOT NULL THEN
    RAISE EXCEPTION 'already_picked';
  END IF;

  SELECT * INTO v_perk FROM stage_perks
   WHERE id = p_perk_id AND stage = v_grant.stage AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_perk_for_stage'; END IF;

  v_code := _generate_stage_perk_code();
  UPDATE stage_perk_grants SET
    perk_id    = v_perk.id,
    code       = v_code,
    chosen_at  = now(),
    expires_at = now() + make_interval(days => v_perk.validity_days)
  WHERE id = p_grant_id;

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'label', v_perk.perk_label,
    'expires_at', now() + make_interval(days => v_perk.validity_days)
  );
END $$;

GRANT EXECUTE ON FUNCTION public.stage_perk_pick(UUID, UUID)
  TO authenticated;

-- 4. xp_credit_with_split — route stage transitions through the helper.
-- (Full updated body applied to DB; the diff vs prior is: the inline perk
-- INSERT/notification loop is replaced with a single call to
-- _grant_stage_perk_slot, plus a branched notification depending on
-- auto_picked vs needs-pick. Body in DB is authoritative.)
