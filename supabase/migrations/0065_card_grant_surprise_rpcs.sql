-- 0065_card_grant_surprise_rpcs.sql
--
-- Manual surprise-card grants. Two paths:
--   * admin_card_grant_surprise — admin web only. Admin grants any
--     surprise card to any kid from the customer detail screen.
--   * card_grant_surprise — staff app at counter. Validates the staff
--     PIN is active before granting.
--
-- Shared body: _card_grant_surprise_inner. Both refuse non-surprise
-- cards (stage / birthday / random_drop are earned through their own
-- paths). Idempotent thanks to hero_card_collection.UNIQUE(child, card).
--
-- Notifications + audit log fire only when the card is NEWLY granted
-- — repeat calls (idempotent re-grants) are silent.

CREATE OR REPLACE FUNCTION _card_grant_surprise_inner(
  p_child_id UUID,
  p_card_id  UUID,
  p_actor_id UUID,
  p_actor_type TEXT,
  p_note TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_card hero_card_definitions%ROWTYPE;
  v_child children%ROWTYPE;
  v_already_owned BOOLEAN;
  v_inserted BOOLEAN;
BEGIN
  SELECT * INTO v_card FROM hero_card_definitions WHERE id = p_card_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'card_not_found'; END IF;
  IF NOT v_card.is_active THEN RAISE EXCEPTION 'card_inactive'; END IF;
  IF v_card.unlock_method <> 'surprise' THEN
    RAISE EXCEPTION 'not_a_surprise_card'
      USING DETAIL = format('unlock_method=%s', v_card.unlock_method);
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM hero_card_collection
     WHERE child_id = p_child_id AND card_id = p_card_id
  ) INTO v_already_owned;

  INSERT INTO hero_card_collection(child_id, card_id)
  VALUES (p_child_id, p_card_id)
  ON CONFLICT (child_id, card_id) DO NOTHING;

  v_inserted := NOT v_already_owned;

  IF v_inserted THEN
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (
      v_child.family_id, 'hero_card_received',
      'A surprise card!',
      v_child.name || ' just received ' || v_card.name || '.',
      '/adventure', p_child_id
    );

    INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
    VALUES (
      p_actor_id, p_actor_type, 'hero_card.grant_surprise', 'child', p_child_id,
      jsonb_build_object(
        'card_id', p_card_id,
        'card_name', v_card.name,
        'hero', v_card.hero,
        'note', p_note
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'newly_granted', v_inserted,
    'card_id', p_card_id,
    'card_name', v_card.name,
    'hero', v_card.hero
  );
END $$;

REVOKE EXECUTE ON FUNCTION _card_grant_surprise_inner(UUID, UUID, UUID, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _card_grant_surprise_inner(UUID, UUID, UUID, TEXT, TEXT)
  TO service_role;

CREATE OR REPLACE FUNCTION admin_card_grant_surprise(
  p_child_id UUID,
  p_card_id  UUID,
  p_note     TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  RETURN _card_grant_surprise_inner(
    p_child_id, p_card_id, auth.uid(), 'admin', p_note
  );
END $$;

REVOKE EXECUTE ON FUNCTION admin_card_grant_surprise(UUID, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_card_grant_surprise(UUID, UUID, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION card_grant_surprise(
  p_child_id     UUID,
  p_card_id      UUID,
  p_staff_pin_id UUID,
  p_note         TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM staff WHERE id = p_staff_pin_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'staff_not_authorised';
  END IF;

  RETURN _card_grant_surprise_inner(
    p_child_id, p_card_id, p_staff_pin_id, 'staff', p_note
  );
END $$;

REVOKE EXECUTE ON FUNCTION card_grant_surprise(UUID, UUID, UUID, TEXT)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION card_grant_surprise(UUID, UUID, UUID, TEXT)
  TO authenticated;
