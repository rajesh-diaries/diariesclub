-- ===========================================================================
--  Migration 0048 — Healthy Bite v3: explicit "didn't give" decision +
--                                    XP bumped to 25
--
--  Founder spec change (BUG-049):
--    The staff workflow is no longer "eligibility appears, staff
--    distributes". It's now an explicit YES/NO decision after the
--    session: did the customer actually take the Healthy Bite?
--      * YES → award card + 25 XP (was 20 — split 6/6/6/7, Zena +1
--              leftover, matching existing reflection split pattern)
--      * NO  → record the decline, no card, no XP
--
--    Staff sees the session in their pending list either way until
--    they make a decision.
--
--  Schema changes:
--    sessions.healthy_bite_declined_at TIMESTAMPTZ NULL
--      Staff explicitly declined to give the bite. Mutually exclusive
--      with healthy_bite_distributed=true (the RPC enforces).
--
--  RPC changes:
--    healthy_bite_distribute   — XP grant 5/5/5/5 → 6/6/6/7 (=25)
--    healthy_bite_decline (NEW) — sets declined_at, logs audit
--
--  Reversibility:
--    ALTER TABLE sessions DROP COLUMN healthy_bite_declined_at;
--    DROP FUNCTION healthy_bite_decline;
--    Re-deploy distribute body from 0046 to revert XP back to 20.
-- ===========================================================================

ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS healthy_bite_declined_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS sessions_healthy_bite_pending_idx
  ON sessions (venue_id, started_at DESC)
  WHERE healthy_bite_distributed = false
    AND healthy_bite_declined_at IS NULL;

-- ---------------------------------------------------------------------------
--  healthy_bite_decline — staff explicitly says "no, customer didn't take"
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.healthy_bite_decline(
  p_session_id UUID,
  p_staff_pin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_session FROM sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found'; END IF;

  IF v_session.healthy_bite_distributed THEN
    RAISE EXCEPTION 'already_distributed';
  END IF;
  IF v_session.healthy_bite_declined_at IS NOT NULL THEN
    -- Idempotent: already declined.
    RETURN jsonb_build_object(
      'success', true, 'idempotent', true,
      'session_id', p_session_id,
      'declined_at', v_session.healthy_bite_declined_at
    );
  END IF;

  UPDATE sessions
     SET healthy_bite_declined_at = now()
   WHERE id = p_session_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    p_staff_pin_id, 'staff', 'healthy_bite.decline', 'session',
    p_session_id, v_session.venue_id,
    jsonb_build_object('declined_at', now())
  );

  RETURN jsonb_build_object(
    'success', true,
    'session_id', p_session_id,
    'declined_at', now()
  );
END $$;

-- ---------------------------------------------------------------------------
--  healthy_bite_distribute — bumped XP from 20 to 25 (6/6/6/7 split)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.healthy_bite_distribute(
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
  IF v_session.healthy_bite_declined_at IS NOT NULL THEN
    RAISE EXCEPTION 'already_declined';
  END IF;

  UPDATE sessions SET
    healthy_bite_earned      = true,
    healthy_bite_distributed = true,
    healthy_bite_claimed_at  = COALESCE(healthy_bite_claimed_at, now())
  WHERE id = p_session_id;

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

  -- 25 XP total split 6/6/6/7 (Zena +1 leftover, matches reflection_submit
  -- rounding pattern). Bumped from 5/5/5/5 = 20 per founder spec.
  IF v_session.family_id IS NOT NULL THEN
    PERFORM xp_credit_with_split(
      p_child_id     => p_child_id,
      p_family_id    => v_session.family_id,
      p_venue_id     => v_session.venue_id,
      p_event_type   => 'healthy_bite',
      p_xp_rafi      => 6,
      p_xp_ellie     => 6,
      p_xp_gerry     => 6,
      p_xp_zena      => 7,
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
      'xp_credited',   25
    )
  );

  RETURN jsonb_build_object(
    'success',       true,
    'card_id',       v_card.id,
    'collection_id', v_collection_id,
    'card_name',     v_card.name,
    'is_rare',       v_card.is_rare,
    'image_url',     v_card.image_url,
    'xp_credited',   25
  );
END $$;
