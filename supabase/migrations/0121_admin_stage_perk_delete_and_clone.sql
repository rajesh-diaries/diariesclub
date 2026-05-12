-- 0121 — admin delete + clone-to-all-traits for stage perks.
--
-- Delete: hard-delete when no grants reference the perk; otherwise
-- archive (set is_active = false) so existing redemption codes keep
-- working. Single RPC picks the right path.
--
-- Clone-to-all-traits: one-click duplicate of a non-welcome perk across
-- all four characters. Used to lift legacy trait-NULL perks into the
-- per-character world. Original row is left untouched — admin can
-- delete or reassign it themselves.

CREATE OR REPLACE FUNCTION public.admin_stage_perk_delete(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_perk   stage_perks%ROWTYPE;
  v_grants INTEGER;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_perk FROM stage_perks WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  SELECT count(*) INTO v_grants FROM stage_perk_grants WHERE perk_id = p_id;

  IF v_grants = 0 THEN
    DELETE FROM stage_perks WHERE id = p_id;
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id, new_value
    ) VALUES (
      auth.uid(), 'admin', 'stage_perk.delete', 'stage_perk', p_id,
      jsonb_build_object(
        'stage', v_perk.stage, 'trait', v_perk.trait,
        'perk_label', v_perk.perk_label
      )
    );
    RETURN jsonb_build_object('deleted', true, 'archived', false);
  ELSE
    UPDATE stage_perks SET is_active = false, updated_at = now()
      WHERE id = p_id;
    INSERT INTO audit_log(
      actor_id, actor_type, action, entity_type, entity_id, new_value
    ) VALUES (
      auth.uid(), 'admin', 'stage_perk.archive', 'stage_perk', p_id,
      jsonb_build_object(
        'stage', v_perk.stage, 'trait', v_perk.trait,
        'perk_label', v_perk.perk_label,
        'grants_count', v_grants
      )
    );
    RETURN jsonb_build_object(
      'deleted', false, 'archived', true, 'grants_count', v_grants
    );
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_delete(UUID)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_stage_perk_clone_to_all_traits(
  p_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_perk     stage_perks%ROWTYPE;
  v_trait    TEXT;
  v_new_ids  UUID[] := ARRAY[]::UUID[];
  v_new_id   UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_perk FROM stage_perks WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;

  IF v_perk.stage = 'welcome' THEN
    RAISE EXCEPTION 'welcome_stage_has_no_traits';
  END IF;

  FOREACH v_trait IN ARRAY ARRAY['rafi','ellie','gerry','zena'] LOOP
    INSERT INTO stage_perks(
      venue_id, stage, trait,
      perk_label, perk_description, validity_days, is_active
    ) VALUES (
      v_perk.venue_id, v_perk.stage, v_trait,
      v_perk.perk_label, v_perk.perk_description,
      v_perk.validity_days, v_perk.is_active
    ) RETURNING id INTO v_new_id;
    v_new_ids := array_append(v_new_ids, v_new_id);
  END LOOP;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin', 'stage_perk.clone_to_all_traits',
    'stage_perk', p_id,
    jsonb_build_object(
      'stage', v_perk.stage, 'perk_label', v_perk.perk_label,
      'created_ids', to_jsonb(v_new_ids)
    )
  );

  RETURN jsonb_build_object('cloned_count', 4, 'new_ids', to_jsonb(v_new_ids));
END $$;

GRANT EXECUTE ON FUNCTION public.admin_stage_perk_clone_to_all_traits(UUID)
  TO authenticated;
