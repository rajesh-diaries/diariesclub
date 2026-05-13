-- 0137 — healthy_bite_distribute now stamps healthy_bite_claimed_at.
--
-- The Given-today tab on the staff Healthy Bite screen filters and
-- orders rows by healthy_bite_claimed_at. The previous RPC only set
-- healthy_bite_distributed = true, leaving claimed_at NULL — so the
-- tab was always empty even when bites had been given.
-- Stamp claimed_at = now() going forward + backfill existing
-- distributed rows using completed_at (or started_at as fallback).

CREATE OR REPLACE FUNCTION public.healthy_bite_distribute(
  p_session_id   UUID,
  p_child_id     UUID,
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
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  UPDATE sessions SET
    healthy_bite_earned       = true,
    healthy_bite_distributed  = true,
    healthy_bite_claimed_at   = now()
  WHERE id = p_session_id;

  v_is_rare := random() <= 0.10;

  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_rare = v_is_rare AND is_birthday_exclusive = false AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = p_child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = false AND is_active = true
      ORDER BY random() LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_cards_available';
  END IF;

  INSERT INTO hero_card_collection(child_id, card_id, session_id)
  VALUES (p_child_id, v_card.id, p_session_id)
  ON CONFLICT (child_id, card_id) DO UPDATE
    SET earned_at = hero_card_collection.earned_at
  RETURNING id INTO v_collection_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_session.family_id, 'hero_card_received',
    'New hero card!',
    CASE WHEN v_card.is_rare THEN 'A rare card just arrived in your collection.'
         ELSE 'Tap to add it to your collection.' END,
    '/cards/unbox/' || v_collection_id, p_child_id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_staff_pin_id, 'staff', 'healthy_bite.distribute', 'session', p_session_id,
          v_session.venue_id,
          jsonb_build_object('card_id', v_card.id, 'is_rare', v_card.is_rare,
                             'collection_id', v_collection_id));

  RETURN jsonb_build_object(
    'success', true,
    'card_id', v_card.id,
    'card_name', v_card.name,
    'is_rare', v_card.is_rare,
    'collection_id', v_collection_id
  );
END $$;

UPDATE sessions
SET healthy_bite_claimed_at = COALESCE(completed_at, started_at)
WHERE healthy_bite_distributed = true
  AND healthy_bite_claimed_at IS NULL;
