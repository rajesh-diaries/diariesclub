-- 0070_quest_hooks_session_and_healthy_bite.sql
--
-- Wires _quest_progress_check into the two most common events:
-- session_complete + healthy_bite_distribute. workshop / fit_meal /
-- reflection follow in 0071.
--
-- Strategy: AFTER UPDATE triggers on sessions, NOT inline calls in
-- the RPC bodies. Triggers are decoupled, idempotent, and don't bloat
-- the main RPC migrations. Quest detection MUST NEVER break the
-- parent RPC — the wrapper catches any error and logs to audit_log.
--
-- New helpers:
--   _quest_progress_check_all_heroes(...)
--     Loops over the 4 heroes, calls _quest_progress_check per hero,
--     swallows any per-hero error so one bad quest can't break the
--     whole detection.
--   _quest_emit_on_session_complete()  trigger
--     Fires on sessions UPDATE when status flips to 'completed'.
--   _quest_emit_on_healthy_bite()  trigger
--     Fires on sessions UPDATE when healthy_bite_distributed flips
--     to true.

CREATE OR REPLACE FUNCTION _quest_progress_check_all_heroes(
  p_child_id UUID,
  p_family_id UUID,
  p_venue_id UUID,
  p_event_type TEXT,
  p_event_data JSONB,
  p_reference_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hero TEXT;
  v_results JSONB := '[]'::JSONB;
  v_one JSONB;
BEGIN
  FOREACH v_hero IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    BEGIN
      v_one := _quest_progress_check(
        p_child_id, p_family_id, p_venue_id,
        v_hero, p_event_type, p_event_data, p_reference_id
      );
      IF (v_one->>'matched')::BOOLEAN THEN
        v_results := v_results || jsonb_build_array(v_one);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'quest_check.error', 'child', p_child_id,
              jsonb_build_object('hero', v_hero, 'event_type', p_event_type,
                                 'error', SQLERRM));
    END;
  END LOOP;
  RETURN jsonb_build_object('quests_completed', v_results);
END $$;

REVOKE EXECUTE ON FUNCTION _quest_progress_check_all_heroes(UUID, UUID, UUID, TEXT, JSONB, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _quest_progress_check_all_heroes(UUID, UUID, UUID, TEXT, JSONB, UUID)
  TO service_role;

CREATE OR REPLACE FUNCTION _quest_emit_on_session_complete()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'completed' AND
     (OLD.status IS DISTINCT FROM 'completed') AND
     NEW.child_id IS NOT NULL THEN
    PERFORM _quest_progress_check_all_heroes(
      NEW.child_id, NEW.family_id, NEW.venue_id,
      'session_complete',
      jsonb_build_object(
        'duration_minutes', NEW.duration_minutes,
        'payment_method', NEW.payment_method,
        'is_guest', NEW.is_guest
      ),
      NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_quest_emit_session_complete ON sessions;
CREATE TRIGGER trg_quest_emit_session_complete
AFTER UPDATE ON sessions
FOR EACH ROW
EXECUTE FUNCTION _quest_emit_on_session_complete();

CREATE OR REPLACE FUNCTION _quest_emit_on_healthy_bite()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.healthy_bite_distributed = true AND
     (OLD.healthy_bite_distributed IS DISTINCT FROM true) AND
     NEW.child_id IS NOT NULL THEN
    PERFORM _quest_progress_check_all_heroes(
      NEW.child_id, NEW.family_id, NEW.venue_id,
      'healthy_bite',
      jsonb_build_object('session_id', NEW.id),
      NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_quest_emit_healthy_bite ON sessions;
CREATE TRIGGER trg_quest_emit_healthy_bite
AFTER UPDATE ON sessions
FOR EACH ROW
EXECUTE FUNCTION _quest_emit_on_healthy_bite();
