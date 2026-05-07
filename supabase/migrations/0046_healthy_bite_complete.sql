-- ===========================================================================
--  Migration 0046 — Healthy Bite v2: cron eligibility, unified
--                   distribute+claim, real +20 XP credit
--
--  Founder-locked decisions (BUG-044):
--    1. Eligibility cron every 5 min: sets healthy_bite_earned=true on
--       active sessions whose remaining time is <=10 min. Matches the
--       customer mid-session banner timing exactly.
--    2. healthy_bite_distribute now ALSO sets healthy_bite_claimed_at, so
--       one staff action covers: give card + clear customer banner +
--       audit log + XP credit.
--    3. +20 XP is now credited for real through xp_credit_with_split,
--       split equally (5/5/5/5) since the bite isn't trait-specific. No
--       longer a visual-only number on the recap image (Edge Function is
--       updated separately to drop the visual-only path).
--
--  Pre-fix gap (audit):
--    healthy_bite_earned was never set automatically — only by
--    healthy_bite_distribute itself. The staff "pending distributions"
--    list filtered on earned=true AND distributed!=true, so it was always
--    empty in production. This migration fixes that root cause.
--
--  Reversibility:
--    SELECT cron.unschedule('healthy-bite-eligibility');
--    -- And re-deploy the v1 healthy_bite_distribute body from
--    -- 0010_reflection.sql:463 if a rollback is needed.
-- ===========================================================================

-- ---------------------------------------------------------------------------
--  1. _healthy_bite_eligibility_sweep
--
--  Flips healthy_bite_earned=true on active sessions in their last 10
--  minutes. Idempotent — only updates rows that haven't been earned yet.
--  Returns the row count for cron-log visibility.
--
--  SECURITY DEFINER + service_role-only EXECUTE: pg_cron daemon runs as
--  postgres which can call SECURITY DEFINER functions; clients can't.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH bumped AS (
    UPDATE sessions
       SET healthy_bite_earned = true
     WHERE status = 'active'
       AND child_id IS NOT NULL
       AND family_id IS NOT NULL
       AND healthy_bite_earned = false
       AND expires_at > now()
       AND expires_at <= now() + interval '10 minutes'
     RETURNING id
  )
  SELECT count(*)::int FROM bumped;
$$;

REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM anon;
REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM authenticated;

-- ---------------------------------------------------------------------------
--  2. healthy_bite_distribute — unified write + real XP credit
--
--  Replaces the v1 body in 0010_reflection.sql:463. Behavioural changes:
--    * UPDATE sessions now also writes healthy_bite_claimed_at = now()
--      (COALESCE preserves any prior claim from the legacy claim RPC).
--    * Calls xp_credit_with_split (5/5/5/5 = 20 XP) — guarded against
--      walk-in sessions (family_id NULL) since the RPC requires it.
--    * audit_log + return body now include xp_credited:20 for trace.
--
--  Unchanged:
--    * Card-rarity roll (10% rare) + uniqueness fallback chain.
--    * hero_card_collection ON CONFLICT upsert.
--    * hero_card_received notification with /cards/unbox deep link.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION healthy_bite_distribute(
  p_session_id UUID,
  p_child_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_session sessions%ROWTYPE;
  v_is_rare BOOLEAN;
  v_collection_id UUID;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;
  IF v_session.healthy_bite_distributed THEN
    RAISE EXCEPTION 'already_distributed';
  END IF;

  -- One write covers all three states (earned + distributed + claimed_at).
  -- COALESCE preserves the timestamp if claim_healthy_bite ran first.
  UPDATE sessions SET
    healthy_bite_earned      = true,
    healthy_bite_distributed = true,
    healthy_bite_claimed_at  = COALESCE(healthy_bite_claimed_at, now())
  WHERE id = p_session_id;

  -- Card-rarity roll: 10% rare. Three-tier fallback for uniqueness.
  v_is_rare := random() <= 0.10;

  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare
      AND is_birthday_exclusive = false
      AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false
        AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false
        AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN RAISE EXCEPTION 'no_cards_available'; END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = EXCLUDED.earned_at
  RETURNING id INTO v_collection_id;

  -- Real +20 XP credit, equal split. Walk-ins (family_id NULL) are
  -- skipped because xp_credit_with_split's lookups need both family +
  -- venue. The cron filter already excludes them, but defensive guard
  -- here in case the RPC is called manually for a walk-in.
  IF v_session.family_id IS NOT NULL THEN
    PERFORM xp_credit_with_split(
      p_child_id     => p_child_id,
      p_family_id    => v_session.family_id,
      p_venue_id     => v_session.venue_id,
      p_event_type   => 'healthy_bite_token',
      p_xp_rafi      => 5,
      p_xp_ellie     => 5,
      p_xp_gerry     => 5,
      p_xp_zena      => 5,
      p_reference_id => v_collection_id,
      p_metadata     => jsonb_build_object(
        'card_id', v_card.id,
        'is_rare', v_card.is_rare
      )
    );
  END IF;

  INSERT INTO notifications(
    family_id, type, title, body, deep_link, reference_id, metadata
  ) VALUES (
    v_session.family_id,
    'hero_card_received',
    'New hero card!',
    CASE WHEN v_card.is_rare
         THEN 'A rare card just arrived in your collection.'
         ELSE 'Tap to add it to your collection.' END,
    '/cards/unbox/' || v_collection_id,
    p_child_id,
    jsonb_build_object(
      'card_id', v_card.id,
      'collection_id', v_collection_id,
      'is_rare', v_card.is_rare
    )
  );

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
    v_session.venue_id,
    jsonb_build_object(
      'card_id',       v_card.id,
      'is_rare',       v_card.is_rare,
      'collection_id', v_collection_id,
      'xp_credited',   20
    )
  );

  RETURN jsonb_build_object(
    'success',       true,
    'card_id',       v_card.id,
    'collection_id', v_collection_id,
    'card_name',     v_card.name,
    'is_rare',       v_card.is_rare,
    'image_url',     v_card.image_url,
    'xp_credited',   20
  );
END $$;

-- ---------------------------------------------------------------------------
--  3. pg_cron schedule — */5 * * * *
--
--  Idempotent: drops the prior schedule with this name (if any) before
--  re-adding. Pattern matches existing cron migrations (0024).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('healthy-bite-eligibility')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'healthy-bite-eligibility');
EXCEPTION WHEN undefined_function OR undefined_table THEN
  NULL; -- pg_cron not installed in this env; skip.
END $$;

SELECT cron.schedule(
  'healthy-bite-eligibility',
  '*/5 * * * *',
  $$ SELECT public._healthy_bite_eligibility_sweep() $$
);
