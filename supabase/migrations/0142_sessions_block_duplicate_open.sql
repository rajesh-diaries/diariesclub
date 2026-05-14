-- 0142_sessions_block_duplicate_open.sql
-- Prevent the same child from having more than one open (pending /
-- active / grace) session at a time.
--
-- BUG (E2E testing): a parent created a session for "Gaddam" while
-- another open session already existed for the same child, leaving the
-- multi-session Home tab showing two rings for the same kid.
--
-- ROOT CAUSE: session_create (0056) only guards against duplicate
-- idempotency_keys; it doesn't check whether the child is already
-- playing. order_place (0140) is the same — its combo-session path
-- inserts straight into sessions without that check.
--
-- FIX: enforce the invariant at the table level with a BEFORE-INSERT
-- trigger. Single point of truth, covers both RPCs *and* any future
-- code path that inserts into sessions. Existing duplicate rows from
-- pre-trigger time are left alone (they'll auto-expire); the trigger
-- only blocks *new* duplicates.

CREATE OR REPLACE FUNCTION sessions_block_duplicate_open()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_existing_id UUID;
BEGIN
  IF NEW.status NOT IN ('pending', 'active', 'grace') THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_existing_id
  FROM sessions
  WHERE child_id = NEW.child_id
    AND status IN ('pending', 'active', 'grace')
    AND id <> NEW.id
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'child_already_in_session'
      USING
        HINT = 'This kid already has an open session: ' || v_existing_id::text,
        ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sessions_block_duplicate_open ON sessions;

CREATE TRIGGER sessions_block_duplicate_open
BEFORE INSERT ON sessions
FOR EACH ROW EXECUTE FUNCTION sessions_block_duplicate_open();
