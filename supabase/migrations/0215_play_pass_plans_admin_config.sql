-- 0215_play_pass_plans_admin_config.sql
-- Make Play Pass plans (price / visits / validity / labels) admin-configurable
-- instead of hardcoded in both the app and the play_pass_purchase RPC.
--
-- MONEY-PATH: play_pass_purchase is rewritten to read price/visits/validity from
-- the new table. Behaviour is IDENTICAL for the seeded values (5/10/15), so nothing
-- changes for customers until an admin edits a plan. Server remains the source of
-- truth for price (client only sends p_pass_type) — no tamper surface added.
--
-- SHIPS WITH THE CUSTOMER APP RELEASE that reads plans from this table. Applying this
-- alone is safe (identical behaviour), but do NOT let admins change values until the
-- app release is live, or the app would display an old price while the RPC charges the
-- new one.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.play_pass_plans (
  id            uuid        NOT NULL DEFAULT gen_random_uuid(),
  venue_id      uuid        NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  pass_type     text        NOT NULL,              -- stable key the app/RPC uses ('5','10','15')
  total_passes  integer     NOT NULL CHECK (total_passes > 0),
  validity_days integer     NOT NULL CHECK (validity_days > 0),
  price_paise   integer     NOT NULL CHECK (price_paise > 0),
  label         text        NOT NULL,              -- e.g. 'Starter Pack'
  tag           text,                              -- e.g. 'Most popular' (nullable)
  sort_order    integer     NOT NULL DEFAULT 0,
  is_active     boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT play_pass_plans_pkey PRIMARY KEY (id),
  CONSTRAINT play_pass_plans_venue_type_key UNIQUE (venue_id, pass_type)
);

ALTER TABLE public.play_pass_plans ENABLE ROW LEVEL SECURITY;

-- Customers read active plans; admins see/manage all.
DROP POLICY IF EXISTS play_pass_plans_public_read ON public.play_pass_plans;
CREATE POLICY play_pass_plans_public_read
  ON public.play_pass_plans FOR SELECT
  USING (is_active = true);

DROP POLICY IF EXISTS play_pass_plans_admin_all ON public.play_pass_plans;
CREATE POLICY play_pass_plans_admin_all
  ON public.play_pass_plans FOR ALL
  USING (is_active_admin())
  WITH CHECK (is_active_admin());

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Seed the current 3 plans (exact current values → no customer-visible change)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.play_pass_plans
  (venue_id, pass_type, total_passes, validity_days, price_paise, label, tag, sort_order)
VALUES
  ('00000000-0000-0000-0000-000000000001','5', 5, 30, 350000,'Starter Pack','Most popular',   10),
  ('00000000-0000-0000-0000-000000000001','10',10,45, 650000,'Value Pack',  'Best value',     20),
  ('00000000-0000-0000-0000-000000000001','15',15,60, 900000,'Family Pack', 'Biggest savings',30)
ON CONFLICT (venue_id, pass_type) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Rewrite play_pass_purchase to read the plan from the table (was a hardcoded CASE)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.play_pass_purchase(p_family_id uuid, p_pass_type text, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total int;
  v_days int;
  v_price_paise int;
  v_pass_id uuid;
  v_existing play_passes%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF p_family_id IS NULL THEN RAISE EXCEPTION 'family_id_required'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF auth.uid() <> p_family_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM play_passes
    WHERE idempotency_key = p_idempotency_key AND family_id = p_family_id;
    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true,
        'pass_id', v_existing.id,
        'total_passes', v_existing.total_passes,
        'used_passes', v_existing.used_passes,
        'expires_at', v_existing.expires_at,
        'idempotent', true
      );
    END IF;
  END IF;

  -- Source of truth: the admin-configurable plan (server-side; client only sends the type).
  SELECT total_passes, validity_days, price_paise
    INTO v_total, v_days, v_price_paise
  FROM play_pass_plans
  WHERE pass_type = p_pass_type AND is_active = true
  ORDER BY venue_id
  LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_pass_type'; END IF;

  SELECT * INTO v_wallet FROM wallets WHERE family_id = p_family_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'wallet_not_found'; END IF;

  IF (v_wallet.balance_paise - v_wallet.held_paise) < v_price_paise THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient_balance');
  END IF;

  INSERT INTO play_passes (family_id, total_passes, used_passes, expires_at, idempotency_key)
  VALUES (p_family_id, v_total, 0, now() + (v_days || ' days')::interval, p_idempotency_key)
  RETURNING id INTO v_pass_id;

  UPDATE wallets
  SET balance_paise = balance_paise - v_price_paise,
      updated_at = now()
  WHERE family_id = p_family_id
  RETURNING * INTO v_wallet;

  INSERT INTO wallet_transactions (
    family_id, type, amount_paise, balance_after_paise,
    payment_method, reference_type, reference_id, idempotency_key
  ) VALUES (
    p_family_id, 'play_pass_purchase', -v_price_paise, v_wallet.balance_paise,
    'wallet', 'play_pass', v_pass_id, p_idempotency_key
  );

  RETURN jsonb_build_object(
    'success', true,
    'pass_id', v_pass_id,
    'total_passes', v_total,
    'used_passes', 0,
    'expires_at', now() + (v_days || ' days')::interval,
    'new_balance_paise', v_wallet.balance_paise
  );
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Admin RPCs to manage plans (SECURITY DEFINER, admin-gated)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_play_pass_plan_upsert(
  p_pass_type text,
  p_total_passes integer,
  p_validity_days integer,
  p_price_paise integer,
  p_label text,
  p_tag text DEFAULT NULL,
  p_sort_order integer DEFAULT 0,
  p_is_active boolean DEFAULT true
) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id uuid;
  v_venue    uuid := '00000000-0000-0000-0000-000000000001';
  v_row      play_pass_plans%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_total_passes <= 0 OR p_validity_days <= 0 OR p_price_paise <= 0 THEN
    RAISE EXCEPTION 'invalid_values';
  END IF;

  INSERT INTO play_pass_plans
    (venue_id, pass_type, total_passes, validity_days, price_paise, label, tag, sort_order, is_active)
  VALUES
    (v_venue, p_pass_type, p_total_passes, p_validity_days, p_price_paise, p_label, p_tag, p_sort_order, p_is_active)
  ON CONFLICT (venue_id, pass_type) DO UPDATE SET
    total_passes  = EXCLUDED.total_passes,
    validity_days = EXCLUDED.validity_days,
    price_paise   = EXCLUDED.price_paise,
    label         = EXCLUDED.label,
    tag           = EXCLUDED.tag,
    sort_order    = EXCLUDED.sort_order,
    is_active     = EXCLUDED.is_active,
    updated_at    = now()
  RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'play_pass_plan.upsert', 'play_pass_plan', v_row.id,
          jsonb_build_object('pass_type', p_pass_type, 'price_paise', p_price_paise,
                             'total_passes', p_total_passes, 'validity_days', p_validity_days));

  RETURN jsonb_build_object('success', true, 'plan_id', v_row.id);
END $function$;

CREATE OR REPLACE FUNCTION public.admin_play_pass_plan_delete(p_pass_type text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id uuid;
  v_venue    uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  v_admin_id := _assert_active_admin();
  DELETE FROM play_pass_plans WHERE venue_id = v_venue AND pass_type = p_pass_type;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'play_pass_plan.delete', 'play_pass_plan', NULL,
          jsonb_build_object('pass_type', p_pass_type));

  RETURN jsonb_build_object('success', true);
END $function$;

-- Expose read to the API roles (RLS still gates rows); execute for admins via authenticated.
GRANT SELECT ON public.play_pass_plans TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_play_pass_plan_upsert(text,integer,integer,integer,text,text,integer,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_play_pass_plan_delete(text) TO authenticated;
