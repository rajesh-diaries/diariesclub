-- FEATURE-002 — complimentary Healthy Bite reminder.
--
-- Distinct from the existing earn-based flow (healthy_bite_earned +
-- healthy_bite_distributed, which fires after 2-hour sessions and rolls
-- a hero card). This is a hospitality reminder that appears 10 minutes
-- before any session ends, prompting the family to swing by the counter
-- for a complimentary bite. Staff marks claimed → customer banner clears.

-- ---------------------------------------------------------------------
-- 1. Schema — new column. Existing earn/distribute columns untouched.
-- ---------------------------------------------------------------------
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS healthy_bite_claimed_at TIMESTAMPTZ NULL DEFAULT NULL;

COMMENT ON COLUMN public.sessions.healthy_bite_claimed_at IS
'FEATURE-002 — set when staff marks the complimentary 10-minute-reminder bite as claimed. NULL = not yet claimed. Distinct from healthy_bite_distributed (which is the 2-hour earn flow).';

-- ---------------------------------------------------------------------
-- 2. RPC — staff-side, idempotent. Returns the claimed_at timestamp.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_healthy_bite(p_session_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_now timestamptz := now();
  v_existing timestamptz;
  v_venue_id uuid;
BEGIN
  -- Look up the session's venue first so we can authorise the caller.
  SELECT venue_id, healthy_bite_claimed_at
    INTO v_venue_id, v_existing
    FROM sessions
   WHERE id = p_session_id;

  IF v_venue_id IS NULL THEN
    RAISE EXCEPTION 'session_not_found';
  END IF;

  -- Authorise: caller must be a registered, active tablet user for this venue.
  IF NOT _is_active_tablet_for_venue(v_venue_id) THEN
    RAISE EXCEPTION 'not_authorised';
  END IF;

  -- Idempotent — keep the original claimed_at if already set.
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object(
      'claimed_at', v_existing,
      'already_claimed', true
    );
  END IF;

  UPDATE sessions
     SET healthy_bite_claimed_at = v_now
   WHERE id = p_session_id;

  -- Audit trail (non-fatal if audit_log structure mismatches).
  BEGIN
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id,
      venue_id, new_value
    ) VALUES (
      auth.uid(), 'staff', 'healthy_bite.claim', 'session', p_session_id,
      v_venue_id, jsonb_build_object('claimed_at', v_now)
    );
  EXCEPTION WHEN OTHERS THEN
    -- Don't block the action on audit failure.
    NULL;
  END;

  RETURN jsonb_build_object(
    'claimed_at', v_now,
    'already_claimed', false
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.claim_healthy_bite(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.claim_healthy_bite(uuid) TO authenticated;

COMMENT ON FUNCTION public.claim_healthy_bite IS
'FEATURE-002 — staff marks the complimentary 10-min-reminder bite as claimed. Idempotent (returns existing claimed_at + already_claimed=true on retry). Authorisation: caller must own an active tablet_devices row for the session''s venue.';
