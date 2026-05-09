-- Layer 5: The Hero Within
--
-- The end-game synthesis. When a kid reaches Legend in all 4 traits
-- (Rafi/Ellie/Gerry/Zena), this is the rarest unlock in the system —
-- their custom illustration combining all four heroes, plus a lifetime
-- free birthday upgrade flag the venue honors.
--
-- Detection runs as an AFTER UPDATE trigger on children, so we don't
-- need to rewrite xp_credit_with_split. The trigger checks the new
-- stage_* values; if all four are 'legend' AND no existing unlock row
-- exists, it inserts and emits a notification.

CREATE TABLE IF NOT EXISTS hero_within_unlocks (
  child_id UUID PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE,
  family_id UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  unlocked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  unlocked_at_total_xp INTEGER NOT NULL,
  illustration_url TEXT,
  -- Set to true once the venue has logged the lifetime free birthday
  -- upgrade redemption / commitment for the family. Operational flag,
  -- toggled by admin from the customer detail screen.
  granted_birthday_upgrade BOOLEAN NOT NULL DEFAULT FALSE,
  granted_birthday_upgrade_at TIMESTAMPTZ,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_hero_within_unlocks_family
  ON hero_within_unlocks(family_id);
CREATE INDEX IF NOT EXISTS idx_hero_within_unlocks_unlocked_at
  ON hero_within_unlocks(unlocked_at DESC);

ALTER TABLE hero_within_unlocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hero_within_family_read ON hero_within_unlocks;
CREATE POLICY hero_within_family_read ON hero_within_unlocks
  FOR SELECT USING (family_id = auth_family_id());

DROP POLICY IF EXISTS hero_within_admin_all ON hero_within_unlocks;
CREATE POLICY hero_within_admin_all ON hero_within_unlocks
  FOR ALL USING (is_active_admin()) WITH CHECK (is_active_admin());

ALTER PUBLICATION supabase_realtime ADD TABLE hero_within_unlocks;

-- ─── trigger: auto-detect on children stage updates ───────────────────────

CREATE OR REPLACE FUNCTION _hero_within_check()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_existing_id UUID;
BEGIN
  -- Cheap fast-path: skip unless all four stages are now 'legend'.
  IF NEW.stage_rafi  <> 'legend'
     OR NEW.stage_ellie <> 'legend'
     OR NEW.stage_gerry <> 'legend'
     OR NEW.stage_zena  <> 'legend' THEN
    RETURN NEW;
  END IF;

  -- Idempotent — already unlocked, nothing to do.
  SELECT child_id INTO v_existing_id
    FROM hero_within_unlocks
   WHERE child_id = NEW.id;
  IF FOUND THEN RETURN NEW; END IF;

  INSERT INTO hero_within_unlocks(child_id, family_id, unlocked_at_total_xp)
  VALUES (NEW.id, NEW.family_id, NEW.total_xp)
  ON CONFLICT (child_id) DO NOTHING;

  -- Big celebration push. Deep-links to the Adventure tab so the
  -- celebration card is the first thing they see.
  INSERT INTO notifications(
    family_id, type, title, body, deep_link, reference_id
  ) VALUES (
    NEW.family_id,
    'hero_within_unlocked',
    NEW.name || ' is The Hero Within',
    'Brave, kind, curious, and creative — Legend in all four. The rarest unlock in the Diaries Club.',
    '/adventure',
    NEW.id
  );

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS hero_within_check_trigger ON children;
CREATE TRIGGER hero_within_check_trigger
AFTER UPDATE OF stage_rafi, stage_ellie, stage_gerry, stage_zena
ON children
FOR EACH ROW
WHEN (
  NEW.stage_rafi  = 'legend' AND NEW.stage_ellie = 'legend'
  AND NEW.stage_gerry = 'legend' AND NEW.stage_zena  = 'legend'
)
EXECUTE FUNCTION _hero_within_check();

-- ─── admin RPC: toggle birthday upgrade flag ──────────────────────────────

CREATE OR REPLACE FUNCTION admin_hero_within_set_birthday_upgrade(
  p_child_id UUID,
  p_granted BOOLEAN,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row hero_within_unlocks%ROWTYPE;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;

  UPDATE hero_within_unlocks
     SET granted_birthday_upgrade = p_granted,
         granted_birthday_upgrade_at =
           CASE WHEN p_granted THEN COALESCE(granted_birthday_upgrade_at, now())
                ELSE NULL END,
         notes = COALESCE(p_notes, notes)
   WHERE child_id = p_child_id
   RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'hero_within_not_unlocked' USING HINT = p_child_id::text;
  END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'hero_within.birthday_upgrade', 'children', p_child_id,
    jsonb_build_object('granted', p_granted, 'notes', p_notes)
  );

  RETURN to_jsonb(v_row);
END $$;

REVOKE EXECUTE ON FUNCTION admin_hero_within_set_birthday_upgrade(UUID, BOOLEAN, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_hero_within_set_birthday_upgrade(UUID, BOOLEAN, TEXT)
  TO authenticated;

-- ─── backfill: any existing legend-in-all-4 kids get the unlock now ───────

INSERT INTO hero_within_unlocks(child_id, family_id, unlocked_at_total_xp)
SELECT id, family_id, total_xp
  FROM children
 WHERE stage_rafi = 'legend' AND stage_ellie = 'legend'
   AND stage_gerry = 'legend' AND stage_zena  = 'legend'
ON CONFLICT (child_id) DO NOTHING;
