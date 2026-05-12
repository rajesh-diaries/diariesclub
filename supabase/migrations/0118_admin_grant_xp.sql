-- 0118 — admin grants ad-hoc XP to a specific kid.
-- For "Aarav was super helpful at the desk today, +50 to Ellie" style
-- moments that don't fit a scheduled workshop/event. Routes through
-- the standard XP splitter so stage transitions, card unlocks, level-ups,
-- and notifications all fire normally.

CREATE OR REPLACE FUNCTION public.admin_grant_xp(
  p_child_id UUID,
  p_amount   INTEGER,
  p_trait    TEXT,
  p_reason   TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_child  children%ROWTYPE;
  v_admin  admin_users%ROWTYPE;
  v_split  RECORD;
  v_result JSONB;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount > 1000 THEN
    RAISE EXCEPTION 'amount_too_large (max 1000 per grant)';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  IF p_trait NOT IN ('rafi','ellie','gerry','zena','split') THEN
    RAISE EXCEPTION 'invalid_trait: %', p_trait;
  END IF;

  SELECT * INTO v_child FROM children WHERE id = p_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'child_not_found'; END IF;

  SELECT * INTO v_admin FROM admin_users WHERE auth_user_id = auth.uid();

  SELECT * INTO v_split FROM _xp_split_for_trait(p_amount, p_trait);

  v_result := xp_credit_with_split(
    p_child_id,
    v_child.family_id,
    '00000000-0000-0000-0000-000000000001'::uuid,
    'admin_manual_grant',
    v_split.r_rafi, v_split.r_ellie, v_split.r_gerry, v_split.r_zena,
    NULL,
    jsonb_build_object(
      'reason', trim(p_reason),
      'trait',  p_trait,
      'granted_by_admin', v_admin.id
    )
  );

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    v_admin.id, 'admin', 'xp.manual_grant', 'child', p_child_id,
    jsonb_build_object(
      'amount', p_amount,
      'trait',  p_trait,
      'reason', trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'amount', p_amount,
    'trait', p_trait,
    'xp_result', v_result
  );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_grant_xp(UUID, INTEGER, TEXT, TEXT)
  TO authenticated;
