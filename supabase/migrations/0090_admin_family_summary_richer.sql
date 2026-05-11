-- 0090 — extend admin_family_children_summary with richer per-kid stats
-- (healthy bites, streak weeks, money spent) and a family-level
-- aggregates object (birthday inquiries, coupons redeemed, total
-- family spend across sessions + orders).
--
-- New return shape: { children: [...], family: {...} }

CREATE OR REPLACE FUNCTION public.admin_family_children_summary(
  p_family_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_children JSONB := '[]'::jsonb;
  v_family JSONB;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'child_id', c.id,
    'sessions_completed', sess.cnt,
    'total_play_minutes', sess.total_min,
    'last_visit_at', sess.last_at,
    'money_spent_paise', sess.spent,
    'healthy_bites_earned', sess.bites,
    'workshops_attended', w.cnt,
    'cards_collected', cards.cnt,
    'perks_redeemed', perks.cnt,
    'reflections_completed', refl.cnt,
    'streak_weeks', st.weeks
  )), '[]'::jsonb) INTO v_children
  FROM children c
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*) AS cnt,
      COALESCE(SUM(duration_minutes), 0) AS total_min,
      MAX(completed_at) AS last_at,
      COALESCE(SUM(amount_paise), 0) AS spent,
      COUNT(*) FILTER (WHERE healthy_bite_earned = true) AS bites
    FROM sessions
    WHERE child_id = c.id AND status = 'completed'
  ) sess ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM workshop_registrations
    WHERE child_id = c.id AND attended = true
  ) w ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM hero_card_collection WHERE child_id = c.id
  ) cards ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM stage_perk_grants
    WHERE child_id = c.id AND redeemed_at IS NOT NULL
  ) perks ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt FROM hero_recaps
    WHERE child_id = c.id AND reflection_status = 'completed'
  ) refl ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(current_streak_weeks, 0) AS weeks
    FROM streak_records WHERE child_id = c.id
  ) st ON true
  WHERE c.family_id = p_family_id;

  SELECT jsonb_build_object(
    'birthday_inquiries_count', (
      SELECT COUNT(*) FROM birthday_reservations WHERE family_id = p_family_id
    ),
    'coupons_redeemed_count', (
      SELECT COUNT(*) FROM coupon_redemptions WHERE family_id = p_family_id
    ),
    'family_total_spent_paise', (
      COALESCE((SELECT SUM(amount_paise) FROM sessions
                 WHERE family_id = p_family_id AND status = 'completed'), 0) +
      COALESCE((SELECT SUM(total_paise) FROM orders
                 WHERE family_id = p_family_id), 0)
    )
  ) INTO v_family;

  RETURN jsonb_build_object(
    'children', v_children,
    'family', v_family
  );
END $$;
