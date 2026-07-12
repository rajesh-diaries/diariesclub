-- 0234 — Staff: list a customer's recent refundable charges
--
-- Refunds need to be reachable from the customer profile (not just a live
-- kitchen ticket), so staff can reverse ANY recent order or session. This
-- SECURITY DEFINER RPC returns the family's recent orders + sessions with how
-- much is still refundable (paid − already-refunded); the staff app renders a
-- Refund button per row. DEFINER so it can read the refunds table (staff have
-- no money RLS) and is tablet-authorised like the other staff RPCs.

CREATE OR REPLACE FUNCTION public.staff_customer_refundables(p_family_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 STABLE
AS $function$
DECLARE
  v_tablet tablet_devices%ROWTYPE;
  v_result jsonb;
BEGIN
  SELECT * INTO v_tablet FROM tablet_devices
    WHERE auth_user_id = auth.uid() AND is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'tablet_not_authorised'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'created_at') DESC), '[]'::jsonb)
    INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'type', 'order',
      'id', o.id,
      'label', COALESCE(
        (SELECT string_agg(oi.name_snapshot, ', ' ORDER BY oi.name_snapshot)
           FROM order_items oi WHERE oi.order_id = o.id),
        'Order'),
      'created_at', o.created_at,
      'paid_paise', o.total_paise,
      'payment_method', o.payment_method,
      'refunded_paise', COALESCE((
        SELECT SUM(r.amount_paise) FROM refunds r
         WHERE r.reference_id = o.id AND r.reference_type = 'order'
           AND r.status IN ('pending','approved','completed')), 0)
    ) AS x
    FROM orders o
    WHERE o.family_id = p_family_id
      AND o.venue_id = v_tablet.venue_id
      AND o.created_at > now() - interval '7 days'

    UNION ALL

    SELECT jsonb_build_object(
      'type', 'session',
      'id', s.id,
      'label', COALESCE((SELECT c.name FROM children c WHERE c.id = s.child_id), 'Play session')
               || ' · ' || s.duration_minutes || 'm',
      'created_at', s.created_at,
      'paid_paise', s.amount_paise,
      'payment_method', s.payment_method,
      'refunded_paise', COALESCE((
        SELECT SUM(r.amount_paise) FROM refunds r
         WHERE r.reference_id = s.id AND r.reference_type = 'session'
           AND r.status IN ('pending','approved','completed')), 0)
    ) AS x
    FROM sessions s
    WHERE s.family_id = p_family_id
      AND s.venue_id = v_tablet.venue_id
      AND s.created_at > now() - interval '7 days'
      AND s.status IN ('active','grace','completed','auto_closed')
      AND s.amount_paise > 0
      AND s.payment_method <> 'play_pass'
  ) t;

  RETURN v_result;
END $function$;

REVOKE EXECUTE ON FUNCTION public.staff_customer_refundables(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.staff_customer_refundables(uuid) TO authenticated, service_role;
