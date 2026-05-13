-- 0138 — staff_order_advance_status RPC for KDS Mark-preparing flow.
--
-- Bug: the KDS screen's "Mark preparing →" / "Mark ready" / "Mark served"
-- buttons silently failed because they did a direct UPDATE on the
-- orders table, but the orders RLS policies only grant SELECT to staff
-- tablets (no UPDATE / no INSERT). Adding a SECURITY DEFINER RPC that
-- validates the caller is an active tablet for the order's venue and
-- then performs the status update.

CREATE OR REPLACE FUNCTION public.staff_order_advance_status(
  p_order_id   UUID,
  p_new_status TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order  orders%ROWTYPE;
  v_old    TEXT;
BEGIN
  IF p_new_status NOT IN ('preparing','ready','served','cancelled') THEN
    RAISE EXCEPTION 'invalid_status: %', p_new_status;
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF NOT _is_active_tablet_for_venue(v_order.venue_id) THEN
    RAISE EXCEPTION 'not_authorised_for_venue';
  END IF;

  IF v_order.status = 'served' THEN
    RAISE EXCEPTION 'already_served';
  END IF;
  IF v_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  v_old := v_order.status;
  UPDATE orders SET status = p_new_status WHERE id = p_order_id;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value
  ) VALUES (
    NULL, 'staff', 'order.status_advance', 'order', p_order_id, v_order.venue_id,
    jsonb_build_object('from', v_old, 'to', p_new_status)
  );

  RETURN jsonb_build_object('success', true, 'from', v_old, 'to', p_new_status);
END $$;

GRANT EXECUTE ON FUNCTION public.staff_order_advance_status(UUID, TEXT)
  TO authenticated;
