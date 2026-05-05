-- ===========================================================================
--  Migration 0037 — FIT meal builder RPCs (Module 2.5)
--
--  Server-authoritative pricing + admin CRUD. All gated on
--  _assert_active_admin() (helper from 0031). Customer-callable RPCs
--  are: fit_meal_compute_price (display-side mirror), fit_meal_order_create
--  (cart-add path — wired in customer-UI commit), fit_subscription_waitlist_join.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Helper: validate selections JSONB shape against template+linked categories
-- and compute final price. Returns (base_price, total_upcharge, final_price).
-- Used by fit_meal_compute_price (display) + fit_meal_order_create (insert).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _fit_validate_and_price(
  p_template_id    UUID,
  p_selections     JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_template     fit_meal_templates%ROWTYPE;
  v_link         RECORD;
  v_cat          fit_meal_categories%ROWTYPE;
  v_sel_type     TEXT;
  v_chosen       JSONB;
  v_chosen_arr   UUID[];
  v_option_id    UUID;
  v_opt          fit_meal_options%ROWTYPE;
  v_total_up     INTEGER := 0;
BEGIN
  SELECT * INTO v_template FROM fit_meal_templates WHERE id = p_template_id;
  IF NOT FOUND OR NOT v_template.is_published OR NOT v_template.is_available THEN
    RAISE EXCEPTION 'template_not_available';
  END IF;

  -- Walk every linked category for the template.
  FOR v_link IN
    SELECT * FROM fit_meal_template_categories
     WHERE template_id = p_template_id
     ORDER BY display_order
  LOOP
    SELECT * INTO v_cat FROM fit_meal_categories WHERE id = v_link.category_id;
    v_sel_type := COALESCE(v_link.selection_type_override, v_cat.selection_type);

    -- selections_jsonb shape: { "<category_id>": "<option_id>" } for
    -- single-select, { "<category_id>": ["<option_id>", ...] } for multi.
    v_chosen := p_selections -> v_link.category_id::TEXT;

    IF v_chosen IS NULL OR v_chosen = 'null'::JSONB THEN
      IF v_link.is_required THEN
        RAISE EXCEPTION 'category_required: %', v_cat.slug;
      END IF;
      CONTINUE;
    END IF;

    IF v_sel_type = 'single' THEN
      -- Expect a string UUID.
      v_option_id := (v_chosen #>> '{}')::UUID;
      SELECT * INTO v_opt FROM fit_meal_options
       WHERE id = v_option_id AND category_id = v_cat.id;
      IF NOT FOUND THEN RAISE EXCEPTION 'option_invalid: %', v_option_id; END IF;
      IF NOT (v_opt.is_published AND v_opt.is_available) THEN
        RAISE EXCEPTION 'option_unavailable: %', v_opt.name;
      END IF;
      v_total_up := v_total_up + v_opt.upcharge_paise;
    ELSE
      -- Expect an array of UUIDs.
      IF jsonb_typeof(v_chosen) <> 'array' THEN
        RAISE EXCEPTION 'multi_select_must_be_array: %', v_cat.slug;
      END IF;
      SELECT array_agg((value #>> '{}')::UUID) INTO v_chosen_arr
        FROM jsonb_array_elements(v_chosen);
      IF v_link.is_required AND COALESCE(array_length(v_chosen_arr, 1), 0) = 0 THEN
        RAISE EXCEPTION 'category_required: %', v_cat.slug;
      END IF;
      FOREACH v_option_id IN ARRAY v_chosen_arr LOOP
        SELECT * INTO v_opt FROM fit_meal_options
         WHERE id = v_option_id AND category_id = v_cat.id;
        IF NOT FOUND THEN RAISE EXCEPTION 'option_invalid: %', v_option_id; END IF;
        IF NOT (v_opt.is_published AND v_opt.is_available) THEN
          RAISE EXCEPTION 'option_unavailable: %', v_opt.name;
        END IF;
        v_total_up := v_total_up + v_opt.upcharge_paise;
      END LOOP;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'base_price_paise', v_template.base_price_paise,
    'total_upcharge_paise', v_total_up,
    'final_price_paise', v_template.base_price_paise + v_total_up
  );
END $$;

REVOKE EXECUTE ON FUNCTION _fit_validate_and_price(UUID, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION _fit_validate_and_price(UUID, JSONB) TO service_role;

-- ---------------------------------------------------------------------------
-- Customer-callable: compute price for live UI.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fit_meal_compute_price(
  p_template_id UUID,
  p_selections  JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN _fit_validate_and_price(p_template_id, p_selections);
END $$;

REVOKE EXECUTE ON FUNCTION fit_meal_compute_price(UUID, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION fit_meal_compute_price(UUID, JSONB) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Customer-callable: insert a fit_meal_order. Caller passes selections.
-- Returns the order row id + final price (server-authoritative). Cart
-- linkage is handled separately in the customer-UI commit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fit_meal_order_create(
  p_template_id UUID,
  p_selections  JSONB
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_priced  JSONB;
  v_row     fit_meal_orders%ROWTYPE;
BEGIN
  v_priced := _fit_validate_and_price(p_template_id, p_selections);

  INSERT INTO fit_meal_orders(
    family_id, template_id,
    base_price_paise, total_upcharge_paise, final_price_paise,
    selections_jsonb, status
  ) VALUES (
    auth.uid(), p_template_id,
    (v_priced->>'base_price_paise')::INT,
    (v_priced->>'total_upcharge_paise')::INT,
    (v_priced->>'final_price_paise')::INT,
    p_selections, 'in_cart'
  ) RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_row.id,
    'base_price_paise', v_row.base_price_paise,
    'total_upcharge_paise', v_row.total_upcharge_paise,
    'final_price_paise', v_row.final_price_paise
  );
END $$;

REVOKE EXECUTE ON FUNCTION fit_meal_order_create(UUID, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION fit_meal_order_create(UUID, JSONB) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Customer-callable: join the FIT subscription waitlist.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fit_subscription_waitlist_join(
  p_email TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row fit_subscription_waitlist%ROWTYPE;
BEGIN
  IF p_email IS NULL OR p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'invalid_email';
  END IF;

  SELECT * INTO v_row FROM fit_subscription_waitlist
   WHERE family_id = auth.uid() LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true, 'waitlist_id', v_row.id);
  END IF;

  INSERT INTO fit_subscription_waitlist(family_id, email)
  VALUES (auth.uid(), p_email) RETURNING * INTO v_row;

  RETURN jsonb_build_object('success', true, 'waitlist_id', v_row.id);
END $$;

REVOKE EXECUTE ON FUNCTION fit_subscription_waitlist_join(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION fit_subscription_waitlist_join(TEXT) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Admin: category CRUD
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_fit_category_create(
  p_venue_id        UUID,
  p_name            TEXT,
  p_slug            TEXT,
  p_selection_type  TEXT,
  p_default_required BOOLEAN,
  p_display_order   INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin_id UUID; v_row fit_meal_categories%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_selection_type NOT IN ('single','multi') THEN RAISE EXCEPTION 'invalid_selection_type'; END IF;
  INSERT INTO fit_meal_categories(
    venue_id, name, slug, selection_type, default_required, display_order
  ) VALUES (
    p_venue_id, p_name, p_slug, p_selection_type,
    COALESCE(p_default_required, TRUE), COALESCE(p_display_order, 0)
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_category.create', 'fit_meal_category', v_row.id,
          jsonb_build_object('slug', p_slug, 'name', p_name));
  RETURN jsonb_build_object('success', true, 'category_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_category_create(UUID, TEXT, TEXT, TEXT, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_category_create(UUID, TEXT, TEXT, TEXT, BOOLEAN, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_category_update(
  p_id              UUID,
  p_name            TEXT,
  p_selection_type  TEXT,
  p_default_required BOOLEAN,
  p_display_order   INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_categories%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_selection_type IS NOT NULL AND p_selection_type NOT IN ('single','multi') THEN
    RAISE EXCEPTION 'invalid_selection_type';
  END IF;
  SELECT * INTO v_row FROM fit_meal_categories WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'category_not_found'; END IF;

  UPDATE fit_meal_categories SET
    name = COALESCE(p_name, name),
    selection_type = COALESCE(p_selection_type, selection_type),
    default_required = COALESCE(p_default_required, default_required),
    display_order = COALESCE(p_display_order, display_order)
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_category.update', 'fit_meal_category', v_row.id,
          jsonb_build_object('name', v_row.name));
  RETURN jsonb_build_object('success', true, 'category_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_category_update(UUID, TEXT, TEXT, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_category_update(UUID, TEXT, TEXT, BOOLEAN, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_category_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_uses INTEGER;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT count(*) INTO v_uses FROM fit_meal_template_categories WHERE category_id = p_id;
  IF v_uses > 0 THEN RAISE EXCEPTION 'category_in_use_by_templates: %', v_uses; END IF;
  DELETE FROM fit_meal_categories WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'category_not_found'; END IF;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'fit_category.delete', 'fit_meal_category', p_id);
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_category_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_category_delete(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Admin: option CRUD
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_fit_option_create(
  p_venue_id      UUID,
  p_category_id   UUID,
  p_name          TEXT,
  p_upcharge_paise INTEGER,
  p_display_order INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_options%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_upcharge_paise IS NOT NULL AND p_upcharge_paise < 0 THEN RAISE EXCEPTION 'invalid_upcharge'; END IF;
  INSERT INTO fit_meal_options(
    venue_id, category_id, name, upcharge_paise, display_order
  ) VALUES (
    p_venue_id, p_category_id, p_name,
    COALESCE(p_upcharge_paise, 0), COALESCE(p_display_order, 0)
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_option.create', 'fit_meal_option', v_row.id,
          jsonb_build_object('name', p_name, 'upcharge_paise', v_row.upcharge_paise));
  RETURN jsonb_build_object('success', true, 'option_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_option_create(UUID, UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_create(UUID, UUID, TEXT, INTEGER, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_option_update(
  p_id            UUID,
  p_name          TEXT,
  p_upcharge_paise INTEGER,
  p_is_available  BOOLEAN,
  p_is_published  BOOLEAN,
  p_display_order INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_options%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_options WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'option_not_found'; END IF;
  IF p_upcharge_paise IS NOT NULL AND p_upcharge_paise < 0 THEN RAISE EXCEPTION 'invalid_upcharge'; END IF;

  UPDATE fit_meal_options SET
    name = COALESCE(p_name, name),
    upcharge_paise = COALESCE(p_upcharge_paise, upcharge_paise),
    is_available = COALESCE(p_is_available, is_available),
    is_published = COALESCE(p_is_published, is_published),
    display_order = COALESCE(p_display_order, display_order),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_option.update', 'fit_meal_option', v_row.id,
          jsonb_build_object('name', v_row.name, 'upcharge_paise', v_row.upcharge_paise,
                             'is_available', v_row.is_available, 'is_published', v_row.is_published));
  RETURN jsonb_build_object('success', true, 'option_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_option_update(UUID, TEXT, INTEGER, BOOLEAN, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_update(UUID, TEXT, INTEGER, BOOLEAN, BOOLEAN, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_option_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_options%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_options WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'option_not_found'; END IF;
  IF NOT v_row.is_published THEN
    RETURN jsonb_build_object('success', true, 'idempotent', true);
  END IF;
  UPDATE fit_meal_options SET is_published = FALSE, updated_at = now() WHERE id = p_id;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'fit_option.unpublish', 'fit_meal_option', p_id);
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_option_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_delete(UUID) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Admin: template CRUD + linker management.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admin_fit_template_create(
  p_venue_id         UUID,
  p_name             TEXT,
  p_description      TEXT,
  p_base_price_paise INTEGER,
  p_photo_url        TEXT,
  p_is_subscribable  BOOLEAN,
  p_subscription_meta JSONB,
  p_sort_order       INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_base_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;
  INSERT INTO fit_meal_templates(
    venue_id, name, description, base_price_paise, photo_url,
    is_subscribable, subscription_meta, sort_order
  ) VALUES (
    p_venue_id, p_name, p_description, p_base_price_paise, p_photo_url,
    COALESCE(p_is_subscribable, FALSE), p_subscription_meta,
    COALESCE(p_sort_order, 0)
  ) RETURNING * INTO v_row;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.create', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', p_name, 'base_price_paise', p_base_price_paise));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_template_create(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_template_update(
  p_id               UUID,
  p_name             TEXT,
  p_description      TEXT,
  p_base_price_paise INTEGER,
  p_photo_url        TEXT,
  p_is_subscribable  BOOLEAN,
  p_subscription_meta JSONB,
  p_is_published     BOOLEAN,
  p_is_available     BOOLEAN,
  p_sort_order       INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_templates WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'template_not_found'; END IF;
  IF p_base_price_paise IS NOT NULL AND p_base_price_paise < 0 THEN RAISE EXCEPTION 'invalid_price'; END IF;

  UPDATE fit_meal_templates SET
    name = COALESCE(p_name, name),
    description = COALESCE(p_description, description),
    base_price_paise = COALESCE(p_base_price_paise, base_price_paise),
    photo_url = COALESCE(p_photo_url, photo_url),
    is_subscribable = COALESCE(p_is_subscribable, is_subscribable),
    subscription_meta = COALESCE(p_subscription_meta, subscription_meta),
    is_published = COALESCE(p_is_published, is_published),
    is_available = COALESCE(p_is_available, is_available),
    sort_order = COALESCE(p_sort_order, sort_order),
    updated_at = now()
  WHERE id = p_id RETURNING * INTO v_row;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.update', 'fit_meal_template', v_row.id,
          jsonb_build_object('name', v_row.name, 'is_published', v_row.is_published));
  RETURN jsonb_build_object('success', true, 'template_id', v_row.id);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_template_update(UUID, TEXT, TEXT, INTEGER, TEXT, BOOLEAN, JSONB, BOOLEAN, BOOLEAN, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_template_delete(p_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID; v_row fit_meal_templates%ROWTYPE;
BEGIN
  v_admin_id := _assert_active_admin();
  SELECT * INTO v_row FROM fit_meal_templates WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'template_not_found'; END IF;
  IF NOT v_row.is_published THEN RETURN jsonb_build_object('success', true, 'idempotent', true); END IF;
  UPDATE fit_meal_templates SET is_published = FALSE, updated_at = now() WHERE id = p_id;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id)
  VALUES (v_admin_id, 'admin', 'fit_template.unpublish', 'fit_meal_template', p_id);
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_template_delete(UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_template_delete(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_template_link_category(
  p_template_id   UUID,
  p_category_id   UUID,
  p_is_required   BOOLEAN,
  p_selection_type_override TEXT,
  p_display_order INTEGER
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_selection_type_override IS NOT NULL
     AND p_selection_type_override NOT IN ('single','multi') THEN
    RAISE EXCEPTION 'invalid_selection_type_override';
  END IF;
  INSERT INTO fit_meal_template_categories(
    template_id, category_id, is_required,
    selection_type_override, display_order
  ) VALUES (
    p_template_id, p_category_id, COALESCE(p_is_required, TRUE),
    p_selection_type_override, COALESCE(p_display_order, 0)
  )
  ON CONFLICT (template_id, category_id) DO UPDATE SET
    is_required = COALESCE(EXCLUDED.is_required, fit_meal_template_categories.is_required),
    selection_type_override = EXCLUDED.selection_type_override,
    display_order = COALESCE(EXCLUDED.display_order, fit_meal_template_categories.display_order);

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.link_category', 'fit_meal_template', p_template_id,
          jsonb_build_object('category_id', p_category_id, 'is_required', p_is_required));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_template_link_category(UUID, UUID, BOOLEAN, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_template_link_category(UUID, UUID, BOOLEAN, TEXT, INTEGER) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION admin_fit_template_unlink_category(
  p_template_id UUID,
  p_category_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID;
BEGIN
  v_admin_id := _assert_active_admin();
  DELETE FROM fit_meal_template_categories
   WHERE template_id = p_template_id AND category_id = p_category_id;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_template.unlink_category', 'fit_meal_template', p_template_id,
          jsonb_build_object('category_id', p_category_id));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_template_unlink_category(UUID, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_template_unlink_category(UUID, UUID) TO authenticated, service_role;

-- Quick toggle for sold-out on options.
CREATE OR REPLACE FUNCTION admin_fit_option_toggle_available(
  p_id        UUID,
  p_available BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID;
BEGIN
  v_admin_id := _assert_active_admin();
  UPDATE fit_meal_options SET is_available = p_available, updated_at = now()
   WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'option_not_found'; END IF;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_option.toggle_available', 'fit_meal_option', p_id,
          jsonb_build_object('is_available', p_available));
  RETURN jsonb_build_object('success', true, 'is_available', p_available);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_option_toggle_available(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_option_toggle_available(UUID, BOOLEAN) TO authenticated, service_role;

-- Admin updates waitlist row status.
CREATE OR REPLACE FUNCTION admin_fit_waitlist_update_status(
  p_id     UUID,
  p_status TEXT,
  p_notes  TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin_id UUID;
BEGIN
  v_admin_id := _assert_active_admin();
  IF p_status NOT IN ('interested','contacted','onboarded','not_interested') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;
  UPDATE fit_subscription_waitlist SET
    status = p_status,
    notes = COALESCE(p_notes, notes)
  WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'waitlist_row_not_found'; END IF;
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (v_admin_id, 'admin', 'fit_waitlist.update_status', 'fit_subscription_waitlist', p_id,
          jsonb_build_object('status', p_status));
  RETURN jsonb_build_object('success', true);
END $$;
REVOKE EXECUTE ON FUNCTION admin_fit_waitlist_update_status(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION admin_fit_waitlist_update_status(UUID, TEXT, TEXT) TO authenticated, service_role;

COMMIT;
