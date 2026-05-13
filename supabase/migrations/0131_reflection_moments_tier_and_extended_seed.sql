-- 0131 — move the wider parent-log moment pool out of hardcoded Flutter
-- into admin-managed reflection_moments. Adds a tier column:
--   * 'primary'  → 6 inline chips on post-session reflection
--   * 'extended' → wider pool surfaced via "+ More moments" and the
--                  Adventure-tab "My kid did this" sheet
-- Both tiers feed the same XP-pool split when picked.

ALTER TABLE reflection_moments
  ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'primary';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reflection_moments_tier_check'
  ) THEN
    ALTER TABLE reflection_moments
      ADD CONSTRAINT reflection_moments_tier_check
      CHECK (tier IN ('primary','extended'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_reflection_moments_trait_tier_active
  ON reflection_moments(primary_trait, tier, is_active);

INSERT INTO reflection_moments
  (tag, display_text, primary_trait, xp_weight, sort_order, is_active, tier)
VALUES
  ('ext_rafi_001',  'Tried the slide they used to skip',                       'rafi',  1.0, 1010, true, 'extended'),
  ('ext_rafi_002',  'Joined a workshop on their own',                          'rafi',  1.0, 1020, true, 'extended'),
  ('ext_rafi_003',  'Asked a question to a grown-up they didn''t know',        'rafi',  1.0, 1030, true, 'extended'),
  ('ext_rafi_004',  'Went first when nobody else would',                       'rafi',  1.0, 1040, true, 'extended'),
  ('ext_rafi_005',  'Tried a food they were afraid of',                        'rafi',  1.0, 1050, true, 'extended'),
  ('ext_rafi_006',  'Spoke up when something felt unfair',                     'rafi',  1.0, 1060, true, 'extended'),
  ('ext_rafi_007',  'Climbed higher than last visit',                          'rafi',  1.0, 1070, true, 'extended'),
  ('ext_rafi_008',  'Performed on stage at an event',                          'rafi',  1.0, 1080, true, 'extended'),
  ('ext_rafi_009',  'Stayed at a workshop without their parent',               'rafi',  1.0, 1090, true, 'extended'),
  ('ext_rafi_010',  'Tried a new sport for the first time',                    'rafi',  1.0, 1100, true, 'extended'),
  ('ext_rafi_011',  'Went on the spiral slide / zipline',                      'rafi',  1.0, 1110, true, 'extended'),
  ('ext_rafi_012',  'Took a risk and it didn''t work — and tried again',       'rafi',  1.0, 1120, true, 'extended'),
  ('ext_ellie_001', 'Shared their snack with a friend',                        'ellie', 1.0, 2010, true, 'extended'),
  ('ext_ellie_002', 'Included a kid who was playing alone',                    'ellie', 1.0, 2020, true, 'extended'),
  ('ext_ellie_003', 'Cheered when a friend won',                               'ellie', 1.0, 2030, true, 'extended'),
  ('ext_ellie_004', 'Said sorry without being asked',                          'ellie', 1.0, 2040, true, 'extended'),
  ('ext_ellie_005', 'Helped a younger kid who fell',                           'ellie', 1.0, 2050, true, 'extended'),
  ('ext_ellie_006', 'Made a card or drawing for someone',                      'ellie', 1.0, 2060, true, 'extended'),
  ('ext_ellie_007', 'Said thank you to staff without a prompt',                'ellie', 1.0, 2070, true, 'extended'),
  ('ext_ellie_008', 'Let another kid go first',                                'ellie', 1.0, 2080, true, 'extended'),
  ('ext_ellie_009', 'Comforted a crying child',                                'ellie', 1.0, 2090, true, 'extended'),
  ('ext_ellie_010', 'Brought water or food for mom or dad',                    'ellie', 1.0, 2100, true, 'extended'),
  ('ext_ellie_011', 'Donated an old toy',                                      'ellie', 1.0, 2110, true, 'extended'),
  ('ext_ellie_012', 'Listened when a friend was upset',                        'ellie', 1.0, 2120, true, 'extended'),
  ('ext_gerry_001', 'Tried a workshop they''d never done',                     'gerry', 1.0, 3010, true, 'extended'),
  ('ext_gerry_002', 'Asked "why?" or "how?" three times in a day',             'gerry', 1.0, 3020, true, 'extended'),
  ('ext_gerry_003', 'Tasted a new flavor or ingredient',                       'gerry', 1.0, 3030, true, 'extended'),
  ('ext_gerry_004', 'Read a book on their own',                                'gerry', 1.0, 3040, true, 'extended'),
  ('ext_gerry_005', 'Explored a new corner of the venue',                      'gerry', 1.0, 3050, true, 'extended'),
  ('ext_gerry_006', 'Followed up on something they were curious about',       'gerry', 1.0, 3060, true, 'extended'),
  ('ext_gerry_007', 'Asked what an unfamiliar word means',                     'gerry', 1.0, 3070, true, 'extended'),
  ('ext_gerry_008', 'Watched staff prepare food and asked about it',           'gerry', 1.0, 3080, true, 'extended'),
  ('ext_gerry_009', 'Compared two foods and noticed a difference',             'gerry', 1.0, 3090, true, 'extended'),
  ('ext_gerry_010', 'Tried a food from a different culture',                   'gerry', 1.0, 3100, true, 'extended'),
  ('ext_gerry_011', 'Picked a workshop based on something they read',          'gerry', 1.0, 3110, true, 'extended'),
  ('ext_gerry_012', 'Researched something at home and told us about it',       'gerry', 1.0, 3120, true, 'extended'),
  ('ext_zena_001',  'Made art at a workshop',                                  'zena',  1.0, 4010, true, 'extended'),
  ('ext_zena_002',  'Built their own FIT meal combo',                          'zena',  1.0, 4020, true, 'extended'),
  ('ext_zena_003',  'Told a story at a reflection moment',                     'zena',  1.0, 4030, true, 'extended'),
  ('ext_zena_004',  'Invented a new game with friends',                        'zena',  1.0, 4040, true, 'extended'),
  ('ext_zena_005',  'Drew or painted something at home',                       'zena',  1.0, 4050, true, 'extended'),
  ('ext_zena_006',  'Made up a character and played them',                     'zena',  1.0, 4060, true, 'extended'),
  ('ext_zena_007',  'Decorated their birthday party themselves',               'zena',  1.0, 4070, true, 'extended'),
  ('ext_zena_008',  'Wrote or dictated a story or poem',                       'zena',  1.0, 4080, true, 'extended'),
  ('ext_zena_009',  'Mixed ingredients to invent a flavor',                    'zena',  1.0, 4090, true, 'extended'),
  ('ext_zena_010',  'Made a gift for someone',                                 'zena',  1.0, 4100, true, 'extended'),
  ('ext_zena_011',  'Photographed something they made',                        'zena',  1.0, 4110, true, 'extended'),
  ('ext_zena_012',  'Sang, danced, or acted at an event',                      'zena',  1.0, 4120, true, 'extended')
ON CONFLICT (tag) DO NOTHING;

-- recap RPC: primary-tier only (the 6 inline chips on reflection screen)
CREATE OR REPLACE FUNCTION public.reflection_moments_for_recap(p_recap_id UUID)
RETURNS TABLE(
  id UUID, tag TEXT, display_text TEXT, primary_trait TEXT,
  icon TEXT, xp_weight NUMERIC, sort_order INTEGER
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT rm.id, rm.tag, rm.display_text, rm.primary_trait,
         rm.icon, rm.xp_weight, rm.sort_order
    FROM reflection_moments rm
   WHERE rm.is_active = true
     AND rm.tier = 'primary'
   ORDER BY rm.primary_trait, rm.sort_order;
END $$;

DROP FUNCTION IF EXISTS public.admin_reflection_moment_upsert(
  uuid, text, text, text, text, numeric, integer, boolean
);

CREATE OR REPLACE FUNCTION public.admin_reflection_moment_upsert(
  p_id            UUID,
  p_tag           TEXT,
  p_display_text  TEXT,
  p_icon          TEXT,
  p_primary_trait TEXT,
  p_xp_weight     NUMERIC,
  p_sort_order    INTEGER,
  p_is_active     BOOLEAN,
  p_tier          TEXT DEFAULT 'primary'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;
  IF p_primary_trait NOT IN ('rafi','ellie','gerry','zena') THEN
    RAISE EXCEPTION 'invalid_trait: %', p_primary_trait;
  END IF;
  IF p_tier NOT IN ('primary','extended') THEN
    RAISE EXCEPTION 'invalid_tier: %', p_tier;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO reflection_moments(
      tag, display_text, icon, primary_trait, xp_weight, sort_order, is_active, tier
    ) VALUES (
      p_tag, p_display_text, p_icon, p_primary_trait,
      COALESCE(p_xp_weight, 1.0), COALESCE(p_sort_order, 0),
      COALESCE(p_is_active, true), p_tier
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE reflection_moments SET
      tag           = COALESCE(p_tag,           tag),
      display_text  = COALESCE(p_display_text,  display_text),
      icon          = p_icon,
      primary_trait = COALESCE(p_primary_trait, primary_trait),
      xp_weight     = COALESCE(p_xp_weight,     xp_weight),
      sort_order    = COALESCE(p_sort_order,    sort_order),
      is_active     = COALESCE(p_is_active,     is_active),
      tier          = COALESCE(p_tier,          tier)
    WHERE id = p_id
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  END IF;

  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (
    auth.uid(), 'admin',
    CASE WHEN p_id IS NULL THEN 'reflection_moment.create' ELSE 'reflection_moment.update' END,
    'reflection_moment', v_id,
    jsonb_build_object(
      'tag', p_tag, 'primary_trait', p_primary_trait,
      'tier', p_tier, 'is_active', p_is_active
    )
  );

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_reflection_moment_upsert(
  UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, INTEGER, BOOLEAN, TEXT
) TO authenticated;
