-- 0107 — enriched reservation detail for the CRM detail drawer.
-- Returns reservation + family contact + kid + wallet stats so the
-- drawer can show context (customer name, phone, kid name, DOB,
-- lifetime spend, current credit balance) without 4 separate fetches.

CREATE OR REPLACE FUNCTION public.admin_birthday_reservation_detail(
  p_reservation_id UUID
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res    birthday_reservations%ROWTYPE;
  v_fam    families%ROWTYPE;
  v_child  children%ROWTYPE;
  v_pkg    birthday_packages%ROWTYPE;
  v_wallet wallets%ROWTYPE;
  v_lifetime_spend_paise BIGINT;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;

  SELECT * INTO v_fam   FROM families  WHERE id = v_res.family_id;
  SELECT * INTO v_child FROM children  WHERE id = v_res.child_id;
  SELECT * INTO v_pkg   FROM birthday_packages WHERE id = v_res.package_id;
  SELECT * INTO v_wallet FROM wallets WHERE family_id = v_res.family_id;

  SELECT COALESCE(SUM(-amount_paise), 0) INTO v_lifetime_spend_paise
    FROM wallet_transactions
   WHERE family_id = v_res.family_id
     AND type IN ('order_debit','session_debit','session_charge',
                  'session_overtime','workshop_charge','birthday_charge');

  RETURN jsonb_build_object(
    'reservation', to_jsonb(v_res),
    'family', jsonb_build_object(
      'id',      v_fam.id,
      'name',    v_fam.name,
      'phone',   v_fam.phone,
      'is_cafe_only', v_fam.is_cafe_only
    ),
    'child', jsonb_build_object(
      'id',            v_child.id,
      'name',          v_child.name,
      'date_of_birth', v_child.date_of_birth
    ),
    'package', jsonb_build_object(
      'id',         v_pkg.id,
      'name',       v_pkg.name,
      'hall_name',  v_pkg.hall_name
    ),
    'wallet', jsonb_build_object(
      'balance_paise',  COALESCE(v_wallet.balance_paise, 0),
      'coins_balance',  COALESCE(v_wallet.coins_balance, 0),
      'coins_lifetime', COALESCE(v_wallet.coins_lifetime, 0)
    ),
    'lifetime_spend_paise', v_lifetime_spend_paise
  );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_birthday_reservation_detail(UUID) TO authenticated;
