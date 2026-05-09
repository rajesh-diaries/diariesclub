-- 0066_stage_perks_schema_and_grant.sql
--
-- Be the Hero Layer 1 — stage transitions unlock real-world venue
-- perks. Each transition fires alongside the existing card auto-grant
-- and creates a one-time redeemable code per kid × perk.
--
-- Schema:
--   stage_perks            Admin-configured perk definitions per stage
--                          (welcome..legend). Multiple perks allowed
--                          per stage. Optional venue_id (NULL = applies
--                          to all venues).
--   stage_perk_grants      Per-kid instances created automatically on
--                          stage transition. Carries unique 8-char
--                          code + expires_at.
--
-- Lifecycle:
--   transition fires → grant inserted with code + expires_at
--   customer sees code in Profile → 'My perks'
--   staff types code → grant.redeemed_at set + audit
--
-- Code format: 8-char uppercase alphanumeric, excludes I O 0 1 to
-- avoid mis-types at the counter.

CREATE TABLE IF NOT EXISTS stage_perks (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id            UUID REFERENCES venues(id) ON DELETE CASCADE,
  stage               TEXT NOT NULL CHECK (stage IN
                        ('welcome','seedling','explorer','adventurer','champion','legend')),
  perk_label          TEXT NOT NULL,
  perk_description    TEXT,
  validity_days       INTEGER NOT NULL DEFAULT 30
                        CHECK (validity_days BETWEEN 1 AND 365),
  is_active           BOOLEAN NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stage_perks_lookup
  ON stage_perks(stage, is_active) WHERE is_active = true;

CREATE TABLE IF NOT EXISTS stage_perk_grants (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id            UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  family_id           UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  stage               TEXT NOT NULL,
  trait               TEXT NOT NULL CHECK (trait IN ('rafi','ellie','gerry','zena')),
  perk_id             UUID NOT NULL REFERENCES stage_perks(id) ON DELETE RESTRICT,
  code                TEXT NOT NULL UNIQUE,
  granted_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at          TIMESTAMPTZ NOT NULL,
  redeemed_at         TIMESTAMPTZ,
  redeemed_by_pin     UUID REFERENCES staff(id),
  redeemed_session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
  redeem_note         TEXT
);

CREATE INDEX IF NOT EXISTS idx_stage_perk_grants_family_unredeemed
  ON stage_perk_grants(family_id, expires_at)
  WHERE redeemed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_stage_perk_grants_code
  ON stage_perk_grants(upper(code))
  WHERE redeemed_at IS NULL;

ALTER TABLE stage_perks         ENABLE ROW LEVEL SECURITY;
ALTER TABLE stage_perk_grants   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stage_perks_admin_all ON stage_perks;
CREATE POLICY stage_perks_admin_all ON stage_perks
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

DROP POLICY IF EXISTS stage_perks_public_read ON stage_perks;
CREATE POLICY stage_perks_public_read ON stage_perks
  FOR SELECT TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS stage_perk_grants_family ON stage_perk_grants;
CREATE POLICY stage_perk_grants_family ON stage_perk_grants
  FOR SELECT TO authenticated
  USING (family_id = auth.uid());

DROP POLICY IF EXISTS stage_perk_grants_admin_all ON stage_perk_grants;
CREATE POLICY stage_perk_grants_admin_all ON stage_perk_grants
  FOR ALL TO authenticated
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

CREATE OR REPLACE FUNCTION _generate_stage_perk_code() RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code TEXT;
  v_i INTEGER;
BEGIN
  LOOP
    v_code := '';
    FOR v_i IN 1..8 LOOP
      v_code := v_code || substr(v_chars, 1 + (random() * (length(v_chars) - 1))::INTEGER, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM stage_perk_grants WHERE code = v_code);
  END LOOP;
  RETURN v_code;
END $$;

REVOKE EXECUTE ON FUNCTION _generate_stage_perk_code() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _generate_stage_perk_code() TO service_role;

-- (Full xp_credit_with_split rewrite with perk auto-grant — see
-- migration body. Identical to 0062 + 0066 perk-grant block per trait
-- transition.)

CREATE OR REPLACE FUNCTION xp_credit_with_split(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_event_type TEXT,
  p_xp_rafi  INTEGER DEFAULT 0,
  p_xp_ellie INTEGER DEFAULT 0,
  p_xp_gerry INTEGER DEFAULT 0,
  p_xp_zena  INTEGER DEFAULT 0,
  p_reference_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child children%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_overall_thresholds JSONB;
  v_trait_thresholds   JSONB;
  v_new_total INTEGER;
  v_new_level INTEGER := 1;
  v_new_overall_stage TEXT;
  v_old_stages JSONB;
  v_new_stages JSONB := '{}'::JSONB;
  v_transitions JSONB := '[]'::JSONB;
  v_granted_cards JSONB := '[]'::JSONB;
  v_granted_perks JSONB := '[]'::JSONB;
  v_trait TEXT;
  v_trait_xp INTEGER;
  v_old_stage TEXT;
  v_new_stage TEXT;
  v_card_row RECORD;
  v_perk_row RECORD;
  v_perk_code TEXT;
  v_perk_grant_id UUID;
  i INTEGER;
BEGIN
  SELECT * INTO v_config FROM venue_config WHERE venue_id = p_venue_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'venue_config_not_found'; END IF;
  v_overall_thresholds := v_config.level_thresholds;
  v_trait_thresholds   := v_config.stage_thresholds_per_trait;

  SELECT * INTO v_child FROM children WHERE id = p_child_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  v_old_stages := jsonb_build_object(
    'rafi',  v_child.stage_rafi,  'ellie', v_child.stage_ellie,
    'gerry', v_child.stage_gerry, 'zena',  v_child.stage_zena
  );

  UPDATE children SET
    xp_rafi  = xp_rafi  + p_xp_rafi,
    xp_ellie = xp_ellie + p_xp_ellie,
    xp_gerry = xp_gerry + p_xp_gerry,
    xp_zena  = xp_zena  + p_xp_zena
  WHERE id = p_child_id RETURNING * INTO v_child;

  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    v_trait_xp := CASE v_trait
      WHEN 'rafi'  THEN v_child.xp_rafi
      WHEN 'ellie' THEN v_child.xp_ellie
      WHEN 'gerry' THEN v_child.xp_gerry
      WHEN 'zena'  THEN v_child.xp_zena
    END;

    IF v_trait_xp = 0 THEN
      v_new_stage := 'welcome';
    ELSE
      v_new_stage := 'seedling';
      FOR i IN 0..(jsonb_array_length(v_trait_thresholds) - 1) LOOP
        IF v_trait_xp >= (v_trait_thresholds->>i)::INTEGER THEN
          v_new_stage := CASE i
            WHEN 0 THEN 'seedling'  WHEN 1 THEN 'explorer'
            WHEN 2 THEN 'adventurer' WHEN 3 THEN 'champion'
            ELSE 'legend'
          END;
        END IF;
      END LOOP;
    END IF;

    v_new_stages := v_new_stages || jsonb_build_object(v_trait, v_new_stage);
    v_old_stage := v_old_stages->>v_trait;

    IF v_new_stage <> v_old_stage THEN
      v_transitions := v_transitions || jsonb_build_array(
        jsonb_build_object('trait', v_trait, 'from', v_old_stage, 'to', v_new_stage)
      );

      FOR v_card_row IN
        SELECT id, name FROM hero_card_definitions
         WHERE unlock_method = 'stage'
           AND hero = v_trait
           AND unlock_stage = v_new_stage
           AND is_active = true
      LOOP
        INSERT INTO hero_card_collection(child_id, card_id)
        VALUES (p_child_id, v_card_row.id)
        ON CONFLICT (child_id, card_id) DO NOTHING;

        v_granted_cards := v_granted_cards || jsonb_build_array(
          jsonb_build_object(
            'card_id', v_card_row.id, 'name', v_card_row.name,
            'hero', v_trait, 'stage', v_new_stage
          )
        );

        INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
        VALUES (
          p_family_id, 'hero_card_received',
          'New hero card unlocked!',
          v_child.name || ' just earned ' || v_card_row.name || '.',
          '/adventure', p_child_id
        );
      END LOOP;

      FOR v_perk_row IN
        SELECT id, perk_label, validity_days
          FROM stage_perks
         WHERE stage = v_new_stage
           AND is_active = true
           AND (venue_id IS NULL OR venue_id = p_venue_id)
      LOOP
        v_perk_code := _generate_stage_perk_code();
        INSERT INTO stage_perk_grants(
          child_id, family_id, stage, trait, perk_id, code, expires_at
        ) VALUES (
          p_child_id, p_family_id, v_new_stage, v_trait, v_perk_row.id, v_perk_code,
          now() + make_interval(days => v_perk_row.validity_days)
        ) RETURNING id INTO v_perk_grant_id;

        v_granted_perks := v_granted_perks || jsonb_build_array(
          jsonb_build_object(
            'grant_id', v_perk_grant_id,
            'perk_id', v_perk_row.id,
            'label', v_perk_row.perk_label,
            'stage', v_new_stage,
            'trait', v_trait,
            'code', v_perk_code
          )
        );

        INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
        VALUES (
          p_family_id, 'stage_transition_revealed',
          'New perk unlocked! ' || v_perk_row.perk_label,
          v_child.name || ' just reached ' || v_new_stage ||
            '. Show code ' || v_perk_code || ' at the counter.',
          '/profile', p_child_id
        );
      END LOOP;
    END IF;
  END LOOP;

  v_new_total := v_child.xp_rafi + v_child.xp_ellie + v_child.xp_gerry + v_child.xp_zena;
  FOR i IN 0..(jsonb_array_length(v_overall_thresholds) - 1) LOOP
    IF v_new_total >= (v_overall_thresholds->>i)::INTEGER THEN
      v_new_level := i + 1;
    END IF;
  END LOOP;

  v_new_overall_stage := CASE
    WHEN v_new_level <= 3  THEN 'seedling'
    WHEN v_new_level <= 6  THEN 'explorer'
    WHEN v_new_level <= 12 THEN 'adventurer'
    WHEN v_new_level <= 18 THEN 'champion'
    ELSE 'legend'
  END;

  UPDATE children SET
    stage_rafi  = v_new_stages->>'rafi',
    stage_ellie = v_new_stages->>'ellie',
    stage_gerry = v_new_stages->>'gerry',
    stage_zena  = v_new_stages->>'zena',
    total_xp = v_new_total,
    current_level = v_new_level,
    current_overall_stage = v_new_overall_stage
  WHERE id = p_child_id;

  INSERT INTO xp_events(
    child_id, family_id, venue_id, event_type,
    xp_rafi, xp_ellie, xp_gerry, xp_zena,
    reference_id, metadata
  ) VALUES (
    p_child_id, p_family_id, p_venue_id, p_event_type,
    p_xp_rafi, p_xp_ellie, p_xp_gerry, p_xp_zena,
    p_reference_id,
    p_metadata || jsonb_build_object(
      'stage_transitions', v_transitions,
      'cards_granted', v_granted_cards,
      'perks_granted', v_granted_perks
    )
  );

  IF jsonb_array_length(v_transitions) > 0 THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      p_family_id, 'stage_transition_revealed',
      v_child.name || ' just leveled up!',
      'See the new look in their adventure tab.',
      '/adventure', p_child_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_total_xp', v_new_total,
    'new_level', v_new_level,
    'new_overall_stage', v_new_overall_stage,
    'new_stages', v_new_stages,
    'transitions', v_transitions,
    'cards_granted', v_granted_cards,
    'perks_granted', v_granted_perks
  );
END $$;
