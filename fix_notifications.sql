CREATE OR REPLACE FUNCTION public._format_name_list(p_names TEXT[])
RETURNS TEXT LANGUAGE sql IMMUTABLE
AS $f$
SELECT CASE
  WHEN array_length(p_names,1) IS NULL THEN 'your kid'
  WHEN array_length(p_names,1)=1 THEN p_names[1]
  WHEN array_length(p_names,1)=2 THEN p_names[1]||' & '||p_names[2]
  ELSE array_to_string(p_names[1:array_length(p_names,1)-1],', ')||' & '||p_names[array_length(p_names,1)]
END;
$f$;

CREATE OR REPLACE FUNCTION public._hydration_reminder_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_count INTEGER := 0;
  v_session_ids UUID[];
  v_row RECORD;
BEGIN
  FOR v_row IN
    SELECT id FROM sessions WHERE status='active' AND started_at <= v_now - INTERVAL '20 minutes' AND hydration_reminded_at IS NULL
  LOOP
    UPDATE sessions SET hydration_reminded_at = v_now WHERE id = v_row.id;
    v_session_ids := v_session_ids || v_row.id;
    v_count := v_count + 1;
  END LOOP;
  FOR v_row IN
    SELECT s.family_id, array_agg(DISTINCT COALESCE(c.name,'your kid')) AS names
    FROM sessions s
    JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
    LEFT JOIN children c ON c.id = s.child_id
    GROUP BY s.family_id
  LOOP
    INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
    VALUES (v_row.family_id, 'hydration_nudge', 'Hydration check 💧',
      CASE WHEN array_length(v_row.names,1)>1
        THEN 'Time for a sip of water — '||_format_name_list(v_row.names)||' need to stay hydrated!'
        ELSE 'Time for a sip of water — keeps the play going strong.' END,
      '/home', gen_random_uuid());
  END LOOP;
  RETURN v_count;
END $f$;

CREATE OR REPLACE FUNCTION public._healthy_bite_eligibility_sweep()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
  v_session_ids UUID[];
BEGIN
  FOR r IN
    UPDATE sessions SET healthy_bite_earned = true
    WHERE status='active' AND child_id IS NOT NULL AND family_id IS NULL
      AND healthy_bite_earned = false
      AND expires_at > now() AND expires_at <= now() + interval '10 minutes'
    RETURNING id, family_id, child_id, venue_id
  LOOP
    v_count := v_count + 1;
    v_session_ids := v_session_ids || r.id;
  END LOOP;
  FOR r IN
    SELECT s.family_id, array_agg(DISTINCT COALESCE(c.name,'your kid')) AS names
    FROM sessions s
    JOIN unnest(v_session_ids) AS sid(id) ON s.id = sid.id
    LEFT JOIN children c ON c.id = s.child_id
    GROUP BY s.family_id
  LOOP
    BEGIN
      PERFORM public._send_notification(
        p_family_id => r.family_id,
        p_type => 'healthy_bite_earned',
        p_args => jsonb_build_object('child_name', _format_name_list(r.names)),
        p_reference_id => gen_random_uuid()
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
      VALUES (NULL, 'system', 'healthy_bite.notify_failed', 'session', NULL, NULL,
              jsonb_build_object('error', SQLERRM, 'family_id', r.family_id));
    END;
  END LOOP;
  RETURN v_count;
END $f$;
