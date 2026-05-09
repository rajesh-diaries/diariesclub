-- 0071_quest_hooks_workshop_fitmeal_reflection.sql
--
-- Three more triggers, completing the 5-event-type quest detection.
--
--   workshop_registrations  AFTER UPDATE when attended flips true
--   fit_meal_orders         AFTER INSERT (any new fit_meal counts)
--   hero_recaps             AFTER UPDATE when reflection_status flips
--                           to 'reflected' (parent actively submitted)
--
-- Each emits via _quest_progress_check_all_heroes — same fan-out across
-- the 4 heroes, same defensive try/catch as 0070.

CREATE OR REPLACE FUNCTION _quest_emit_on_workshop_attend()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_workshop workshops%ROWTYPE;
BEGIN
  IF NEW.attended = true AND
     (OLD.attended IS DISTINCT FROM true) AND
     NEW.child_id IS NOT NULL THEN
    SELECT * INTO v_workshop FROM workshops WHERE id = NEW.workshop_id;
    PERFORM _quest_progress_check_all_heroes(
      NEW.child_id, NEW.family_id, v_workshop.venue_id,
      'workshop_attend',
      jsonb_build_object(
        'workshop_id', NEW.workshop_id,
        'workshop_template', v_workshop.template_key
      ),
      NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_quest_emit_workshop_attend ON workshop_registrations;
CREATE TRIGGER trg_quest_emit_workshop_attend
AFTER UPDATE ON workshop_registrations
FOR EACH ROW
EXECUTE FUNCTION _quest_emit_on_workshop_attend();

-- fit_meal_orders has family_id but no child_id directly; we pick the
-- kid currently in an active/grace session, falling back to the
-- family's first child. Quest credit goes to whoever's playing now.
CREATE OR REPLACE FUNCTION _quest_emit_on_fit_meal_order()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child_id UUID;
  v_venue_id UUID;
BEGIN
  SELECT s.child_id, s.venue_id INTO v_child_id, v_venue_id
    FROM sessions s
   WHERE s.family_id = NEW.family_id
     AND s.status IN ('active','grace')
   ORDER BY s.started_at DESC LIMIT 1;

  IF v_child_id IS NULL THEN
    SELECT id INTO v_child_id FROM children
     WHERE family_id = NEW.family_id AND deleted_at IS NULL
     ORDER BY created_at LIMIT 1;
  END IF;

  IF v_venue_id IS NULL THEN
    SELECT venue_id INTO v_venue_id FROM venue_config LIMIT 1;
  END IF;

  IF v_child_id IS NOT NULL AND v_venue_id IS NOT NULL THEN
    PERFORM _quest_progress_check_all_heroes(
      v_child_id, NEW.family_id, v_venue_id,
      'fit_meal_order',
      jsonb_build_object(
        'template_id', NEW.template_id,
        'final_price_paise', NEW.final_price_paise
      ),
      NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_quest_emit_fit_meal_order ON fit_meal_orders;
CREATE TRIGGER trg_quest_emit_fit_meal_order
AFTER INSERT ON fit_meal_orders
FOR EACH ROW
EXECUTE FUNCTION _quest_emit_on_fit_meal_order();

-- Reflection: parent active submission only (NOT the cron auto_split).
CREATE OR REPLACE FUNCTION _quest_emit_on_reflection_save()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session sessions%ROWTYPE;
  v_moment_count INTEGER := 0;
BEGIN
  IF NEW.reflection_status = 'reflected' AND
     (OLD.reflection_status IS DISTINCT FROM 'reflected') AND
     NEW.child_id IS NOT NULL THEN
    SELECT * INTO v_session FROM sessions WHERE id = NEW.session_id;
    v_moment_count := COALESCE(array_length(NEW.moment_tags, 1), 0);

    PERFORM _quest_progress_check_all_heroes(
      NEW.child_id, v_session.family_id, v_session.venue_id,
      'reflection_save',
      jsonb_build_object(
        'moment_count', v_moment_count,
        'session_id', NEW.session_id
      ),
      NEW.id
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_quest_emit_reflection_save ON hero_recaps;
CREATE TRIGGER trg_quest_emit_reflection_save
AFTER UPDATE ON hero_recaps
FOR EACH ROW
EXECUTE FUNCTION _quest_emit_on_reflection_save();
