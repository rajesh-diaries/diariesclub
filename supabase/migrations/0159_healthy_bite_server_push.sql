-- 0159 — Server-side Healthy Bite push.
--
-- Until now the only Healthy Bite "notification" was a local one fired
-- by HealthyBiteReminderBanner's post-frame callback — which means the
-- customer only ever saw it AFTER opening the session detail screen.
-- The eligibility cron ran every 5 min and flipped
-- healthy_bite_earned=true but inserted nothing into notifications, so
-- the FCM path was dead.
--
-- This migration rewrites _healthy_bite_eligibility_sweep in plpgsql so
-- that, for each session it newly flips to earned, it also calls
-- _send_notification(family_id, 'healthy_bite_earned', …). The trigger
-- on notifications insert dispatches via send-push → FCM, matching how
-- hydration_nudge works.
--
-- The 'healthy_bite_earned' template already exists (copy: "{{child_name}}
-- deserves a Healthy Bite! Please collect from the counter — our
-- compliments." deep_link=/home). The sweep only flips rows where
-- healthy_bite_earned was false, so each session gets exactly one push.

CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
  v_child_name TEXT;
BEGIN
  FOR r IN
    UPDATE sessions
       SET healthy_bite_earned = true
     WHERE status = 'active'
       AND child_id IS NOT NULL
       AND family_id IS NOT NULL
       AND healthy_bite_earned = false
       AND expires_at > now()
       AND expires_at <= now() + interval '10 minutes'
    RETURNING id, family_id, child_id, venue_id
  LOOP
    v_count := v_count + 1;
    SELECT name INTO v_child_name FROM children WHERE id = r.child_id;
    BEGIN
      PERFORM public._send_notification(
        p_family_id    => r.family_id,
        p_type         => 'healthy_bite_earned',
        p_args         => jsonb_build_object(
          'child_name', COALESCE(v_child_name, 'your kid'),
          'session_id', r.id::TEXT
        ),
        p_reference_id => r.id
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
      VALUES (NULL, 'system', 'healthy_bite.notify_failed',
              'session', r.id, r.venue_id,
              jsonb_build_object('error', SQLERRM));
    END;
  END LOOP;

  RETURN v_count;
END $function$;

REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM anon;
REVOKE ALL ON FUNCTION public._healthy_bite_eligibility_sweep() FROM authenticated;
