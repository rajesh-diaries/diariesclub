-- 0091 — admin_birthday_dashboard RPC
--
-- Single round-trip for the new Birthday CRM dashboard:
--   * KPIs for the selected month (birthdays / inquiries / confirmed
--     / completed / revenue)
--   * Needs-attention counters (new inquiries past 4h, kids with
--     upcoming birthdays missing inquiries, confirmed-this-week)
--   * Birthdays-this-month list (kids + family + status + reservation)
-- p_month is 1..12; null defaults to current IST month.

CREATE OR REPLACE FUNCTION public.admin_birthday_dashboard(
  p_month INTEGER DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_month INTEGER;
  v_year INTEGER;
  v_today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::DATE;
  v_kpis JSONB;
  v_attention JSONB;
  v_birthdays JSONB;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  v_month := COALESCE(p_month, EXTRACT(MONTH FROM v_today)::INTEGER);
  v_year := EXTRACT(YEAR FROM v_today)::INTEGER;

  SELECT jsonb_build_object(
    'birthdays_count', (
      SELECT COUNT(*) FROM children
      WHERE date_of_birth IS NOT NULL
        AND EXTRACT(MONTH FROM date_of_birth) = v_month
        AND deleted_at IS NULL
    ),
    'inquiries_count', (
      SELECT COUNT(*) FROM birthday_reservations
      WHERE EXTRACT(MONTH FROM created_at AT TIME ZONE 'Asia/Kolkata') = v_month
        AND EXTRACT(YEAR FROM created_at AT TIME ZONE 'Asia/Kolkata') = v_year
    ),
    'confirmed_count', (
      SELECT COUNT(*) FROM birthday_reservations
      WHERE status IN ('confirmed', 'completed')
        AND slot_date IS NOT NULL
        AND EXTRACT(MONTH FROM slot_date) = v_month
        AND EXTRACT(YEAR FROM slot_date) = v_year
    ),
    'completed_count', (
      SELECT COUNT(*) FROM birthday_reservations
      WHERE status = 'completed'
        AND slot_date IS NOT NULL
        AND EXTRACT(MONTH FROM slot_date) = v_month
        AND EXTRACT(YEAR FROM slot_date) = v_year
    ),
    'revenue_paise', (
      SELECT COALESCE(SUM(package_price_paise * COALESCE(num_kids, 0)), 0)
      FROM birthday_reservations
      WHERE status IN ('confirmed', 'completed')
        AND slot_date IS NOT NULL
        AND EXTRACT(MONTH FROM slot_date) = v_month
        AND EXTRACT(YEAR FROM slot_date) = v_year
    )
  ) INTO v_kpis;

  WITH child_next_bdays AS (
    SELECT c.id,
      CASE
        WHEN make_date(v_year, EXTRACT(MONTH FROM c.date_of_birth)::INT,
                       EXTRACT(DAY FROM c.date_of_birth)::INT) >= v_today
        THEN make_date(v_year, EXTRACT(MONTH FROM c.date_of_birth)::INT,
                       EXTRACT(DAY FROM c.date_of_birth)::INT)
        ELSE make_date(v_year + 1, EXTRACT(MONTH FROM c.date_of_birth)::INT,
                       EXTRACT(DAY FROM c.date_of_birth)::INT)
      END AS next_bday
    FROM children c
    WHERE c.deleted_at IS NULL AND c.date_of_birth IS NOT NULL
  )
  SELECT jsonb_build_object(
    'new_inquiries_waiting', (
      SELECT COUNT(*) FROM birthday_reservations
      WHERE status = 'interested'
        AND admin_contacted_at IS NULL
        AND created_at < now() - interval '4 hours'
    ),
    'kids_no_inquiry_upcoming', (
      SELECT COUNT(*) FROM child_next_bdays cnb
      WHERE cnb.next_bday BETWEEN v_today AND v_today + 14
        AND NOT EXISTS (
          SELECT 1 FROM birthday_reservations r
          WHERE r.child_id = cnb.id
            AND r.created_at > now() - interval '6 months'
            AND r.status NOT IN ('cancelled')
        )
    ),
    'confirmed_this_week', (
      SELECT COUNT(*) FROM birthday_reservations
      WHERE status = 'confirmed'
        AND slot_date IS NOT NULL
        AND slot_date BETWEEN v_today AND v_today + 7
    )
  ) INTO v_attention;

  SELECT COALESCE(jsonb_agg(row_obj ORDER BY (row_obj->>'birthday_day')::INT), '[]'::jsonb)
  INTO v_birthdays
  FROM (
    SELECT jsonb_build_object(
      'child_id', c.id,
      'child_name', c.name,
      'family_id', c.family_id,
      'family_name', f.name,
      'family_phone', f.phone,
      'date_of_birth', c.date_of_birth,
      'birthday_day', EXTRACT(DAY FROM c.date_of_birth)::INT,
      'birthday_month', EXTRACT(MONTH FROM c.date_of_birth)::INT,
      'reservation_id', r.id,
      'reservation_status', r.status,
      'last_contact_at', r.admin_contacted_at
    ) AS row_obj
    FROM children c
    JOIN families f ON f.id = c.family_id
    LEFT JOIN LATERAL (
      SELECT id, status, admin_contacted_at
      FROM birthday_reservations
      WHERE child_id = c.id
        AND status NOT IN ('cancelled')
      ORDER BY created_at DESC LIMIT 1
    ) r ON true
    WHERE c.deleted_at IS NULL
      AND c.date_of_birth IS NOT NULL
      AND EXTRACT(MONTH FROM c.date_of_birth) = v_month
  ) sub;

  RETURN jsonb_build_object(
    'kpis', v_kpis,
    'attention', v_attention,
    'birthdays', v_birthdays
  );
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_birthday_dashboard(integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_birthday_dashboard(integer)
  TO authenticated;
