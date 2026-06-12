-- ===========================================================================
-- Enhance home_banners: scheduling, types, deep-linking, analytics.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Extend home_banners table
-- ---------------------------------------------------------------------------
ALTER TABLE public.home_banners
  ADD COLUMN IF NOT EXISTS target_route text,
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'promo'
    CHECK (type IN ('promo', 'info', 'urgent')),
  ADD COLUMN IF NOT EXISTS visible_from timestamptz,
  ADD COLUMN IF NOT EXISTS visible_until timestamptz,
  ADD COLUMN IF NOT EXISTS alt_text text;

COMMENT ON COLUMN public.home_banners.target_route IS
  'Optional deep-link route (e.g. /club/fit). Null/empty = non-clickable banner.';
COMMENT ON COLUMN public.home_banners.type IS
  'promo = clickable offer, info = static greeting, urgent = high-attention alert.';
COMMENT ON COLUMN public.home_banners.visible_from IS
  'Show banner at or after this time. Null means show immediately.';
COMMENT ON COLUMN public.home_banners.visible_until IS
  'Stop showing banner after this time. Null means show indefinitely.';
COMMENT ON COLUMN public.home_banners.alt_text IS
  'Accessibility label for the image, not rendered visually.';

-- ---------------------------------------------------------------------------
-- 2. Banner tap analytics
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.home_banner_taps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  banner_id uuid NOT NULL REFERENCES public.home_banners(id) ON DELETE CASCADE,
  family_id uuid REFERENCES public.families(id) ON DELETE SET NULL,
  tapped_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.home_banner_taps IS
  'Analytics: one row per customer tap on a home banner.';

ALTER TABLE public.home_banner_taps ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'home_banner_taps'
      AND policyname = 'home_banner_taps_insert_authenticated'
  ) THEN
    CREATE POLICY "home_banner_taps_insert_authenticated"
      ON public.home_banner_taps FOR INSERT TO authenticated
      WITH CHECK (
        family_id = auth_family_id()
        OR family_id IS NULL
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'home_banner_taps'
      AND policyname = 'home_banner_taps_admin_read'
  ) THEN
    CREATE POLICY "home_banner_taps_admin_read"
      ON public.home_banner_taps FOR SELECT TO authenticated
      USING (is_admin());
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Helper: count taps per banner (admin analytics)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_home_banner_tap_count(p_banner_id uuid)
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*) FROM public.home_banner_taps
   WHERE banner_id = p_banner_id;
$$;
