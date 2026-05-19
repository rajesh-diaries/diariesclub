-- 0163 — Remove birthday hero cards entirely.
--
-- Founder decision 2026-05-18: birthday hosting awards XP only; no card
-- unlock. Birthday cards will instead be a surprise gift handled outside
-- this XP system. Removes the four placeholder birthday-exclusive cards
-- from circulation and strips the card-grant logic out of the two
-- completion RPCs.
--
-- What's preserved:
--   - xp_credit_with_split call (birthday XP still flows)
--   - status flip to 'completed'
--   - birthday_d_plus_1 push
--   - audit log
--
-- What's removed:
--   - hero_card_collection inserts in birthday_complete and
--     birthday_reservation_complete
--   - the 4 is_birthday_exclusive=true card definitions are flipped
--     inactive AND existing earned rows are deleted so no kid sees them

-- ── 1. Wipe earned birthday cards from kids' collections ────────────────
DELETE FROM hero_card_collection
 WHERE card_id IN (
   SELECT id FROM hero_card_definitions WHERE is_birthday_exclusive = TRUE
 );

-- ── 2. Inactivate the four definitions ──────────────────────────────────
UPDATE hero_card_definitions
   SET is_active = FALSE
 WHERE is_birthday_exclusive = TRUE;

-- ── 3. Clear birthday_hero_card_id on past reservations ─────────────────
UPDATE birthday_reservations
   SET birthday_hero_card_id = NULL
 WHERE birthday_hero_card_id IS NOT NULL;

-- ── 4. Patch birthday_complete — no card grant ──────────────────────────
CREATE OR REPLACE FUNCTION public.birthday_complete(p_reservation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_config venue_config%ROWTYPE;
  v_split RECORD;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status = 'completed' THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  IF v_res.status NOT IN ('confirmed','deposit_paid') THEN
    RAISE EXCEPTION 'invalid_reservation_state';
  END IF;

  SELECT * INTO v_config FROM venue_config WHERE venue_id = v_res.venue_id;
  SELECT * INTO v_split FROM _xp_split_for_trait(
    v_config.xp_birthday_hosted, v_config.xp_birthday_hosted_trait
  );
  PERFORM xp_credit_with_split(
    v_res.child_id, v_res.family_id, v_res.venue_id,
    'birthday_hosted',
    v_split.r_rafi, v_split.r_ellie, v_split.r_gerry, v_split.r_zena,
    p_reservation_id,
    jsonb_build_object('reservation_id', p_reservation_id, 'trait', v_config.xp_birthday_hosted_trait)
  );

  UPDATE birthday_reservations SET status = 'completed' WHERE id = p_reservation_id;

  PERFORM public._send_notification(
    v_res.family_id, 'birthday_d_plus_1',
    jsonb_build_object('reservation_id', v_res.id::text),
    NULL, v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (NULL, 'system', 'birthday.complete', 'birthday_reservation', p_reservation_id,
          v_res.venue_id,
          jsonb_build_object('xp_awarded', v_config.xp_birthday_hosted,
            'trait', v_config.xp_birthday_hosted_trait));

  RETURN jsonb_build_object('success', true,
    'xp_awarded', v_config.xp_birthday_hosted);
END $function$;

-- ── 5. Patch birthday_reservation_complete — no card grant ──────────────
CREATE OR REPLACE FUNCTION public.birthday_reservation_complete(p_reservation_id uuid, p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_res birthday_reservations%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_res.status NOT IN ('confirmed') THEN RAISE EXCEPTION 'invalid_state_for_completion'; END IF;

  PERFORM xp_credit_with_split(
    v_res.child_id, v_res.family_id, v_res.venue_id,
    'birthday_hosted', 250, 250, 250, 250,
    v_res.id, jsonb_build_object('reservation_id', v_res.id)
  );

  UPDATE birthday_reservations SET status = 'completed' WHERE id = p_reservation_id;

  PERFORM public._send_notification(
    p_family_id    => v_res.family_id,
    p_type         => 'birthday_d_plus_1',
    p_args         => jsonb_build_object('reservation_id', v_res.id::text),
    p_reference_id => v_res.id
  );

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_admin_id, 'admin', 'birthday.complete', 'birthday_reservation',
          v_res.id, v_res.venue_id, jsonb_build_object('cards', 'removed_per_founder_2026_05_18'));

  RETURN jsonb_build_object('success', true);
END $function$;
