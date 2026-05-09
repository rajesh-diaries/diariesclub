-- 0064_admin_hero_card_upsert_with_unlock.sql
--
-- Extends admin_hero_card_upsert to accept unlock_method + unlock_stage
-- so the admin dialog can re-tag cards. Adds validation:
--   * unlock_method must be in ('stage','surprise','birthday','random_drop')
--   * unlock_stage must be in welcome..legend (when set)
--   * unlock_method='stage' requires a non-null unlock_stage
--   * Other methods clear unlock_stage to NULL automatically.

CREATE OR REPLACE FUNCTION public.admin_hero_card_upsert(
  p_id                   uuid,
  p_name                 text,
  p_hero                 text,
  p_description          text,
  p_image_url            text,
  p_is_rare              boolean,
  p_is_birthday_exclusive boolean,
  p_is_active            boolean,
  p_unlock_method        text DEFAULT NULL,
  p_unlock_stage         text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  IF p_hero NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_hero: %', p_hero;
  END IF;

  IF p_unlock_method IS NOT NULL
     AND p_unlock_method NOT IN ('stage','surprise','birthday','random_drop') THEN
    RAISE EXCEPTION 'invalid_unlock_method: %', p_unlock_method;
  END IF;

  IF p_unlock_stage IS NOT NULL
     AND p_unlock_stage NOT IN ('welcome','seedling','explorer','adventurer','champion','legend') THEN
    RAISE EXCEPTION 'invalid_unlock_stage: %', p_unlock_stage;
  END IF;

  IF p_unlock_method = 'stage' AND p_unlock_stage IS NULL THEN
    RAISE EXCEPTION 'stage_method_requires_unlock_stage';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO hero_card_definitions(
      name, hero, description, image_url,
      is_rare, is_birthday_exclusive, is_active,
      unlock_method, unlock_stage
    ) VALUES (
      p_name, p_hero, p_description, p_image_url,
      COALESCE(p_is_rare, false),
      COALESCE(p_is_birthday_exclusive, false),
      COALESCE(p_is_active, true),
      COALESCE(p_unlock_method, 'random_drop'),
      CASE WHEN p_unlock_method = 'stage' THEN p_unlock_stage ELSE NULL END
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE hero_card_definitions
       SET name                  = COALESCE(p_name, name),
           hero                  = COALESCE(p_hero, hero),
           description           = COALESCE(p_description, description),
           image_url             = COALESCE(p_image_url, image_url),
           is_rare               = COALESCE(p_is_rare, is_rare),
           is_birthday_exclusive = COALESCE(p_is_birthday_exclusive, is_birthday_exclusive),
           is_active             = COALESCE(p_is_active, is_active),
           unlock_method         = COALESCE(p_unlock_method, unlock_method),
           unlock_stage          = CASE
                                     WHEN p_unlock_method IS NULL THEN unlock_stage
                                     WHEN p_unlock_method = 'stage' THEN p_unlock_stage
                                     ELSE NULL
                                   END
     WHERE id = p_id
     RETURNING id INTO v_id;

    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(
    actor_id, actor_type, action, entity_type, entity_id, new_value
  ) VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'hero_card.create' ELSE 'hero_card.update' END,
    'hero_card', v_id,
    jsonb_build_object(
      'name', p_name, 'hero', p_hero,
      'is_rare', p_is_rare, 'is_active', p_is_active,
      'unlock_method', p_unlock_method,
      'unlock_stage', p_unlock_stage
    )
  );

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_hero_card_upsert(
  uuid, text, text, text, text, boolean, boolean, boolean, text, text
) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_hero_card_upsert(
  uuid, text, text, text, text, boolean, boolean, boolean, text, text
) TO authenticated;
