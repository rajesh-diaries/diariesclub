-- ===========================================================================
-- Home promotional banners carousel
-- Admin-configurable auto-sliding banners on the customer home screen.
-- Each banner promotes a club tab (Cafe, FIT, Combos, Birthdays, Workshops).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.home_banners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  subtitle text,
  image_url text NOT NULL,
  cta_label text NOT NULL DEFAULT 'Shop here >',
  target_tab int NOT NULL DEFAULT 0 CHECK (target_tab BETWEEN 0 AND 4),
  -- 0=Cafe, 1=FIT, 2=Combos, 3=Birthdays, 4=Workshops
  display_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.home_banners IS 'Admin-managed promotional banners for the home screen carousel. target_tab maps to Club page tabs: 0=Cafe, 1=FIT, 2=Combos, 3=Birthdays, 4=Workshops.';

-- ---------------------------------------------------------------------------
-- 2. RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.home_banners ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'home_banners' AND policyname = 'home_banners_public_select'
  ) THEN
    CREATE POLICY "home_banners_public_select"
      ON public.home_banners FOR SELECT TO authenticated, anon
      USING (is_active = true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'home_banners' AND policyname = 'home_banners_admin_all'
  ) THEN
    CREATE POLICY "home_banners_admin_all"
      ON public.home_banners FOR ALL TO authenticated
      USING (is_admin())
      WITH CHECK (is_admin());
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Storage bucket for banner images
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('home-banners', 'home-banners', true)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'home_banners_storage_admin_upload'
  ) THEN
    CREATE POLICY "home_banners_storage_admin_upload"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'home-banners' AND is_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'home_banners_storage_admin_update'
  ) THEN
    CREATE POLICY "home_banners_storage_admin_update"
      ON storage.objects FOR UPDATE TO authenticated
      USING (bucket_id = 'home-banners' AND is_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'home_banners_storage_admin_delete'
  ) THEN
    CREATE POLICY "home_banners_storage_admin_delete"
      ON storage.objects FOR DELETE TO authenticated
      USING (bucket_id = 'home-banners' AND is_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'home_banners_storage_public_read'
  ) THEN
    CREATE POLICY "home_banners_storage_public_read"
      ON storage.objects FOR SELECT TO anon, authenticated
      USING (bucket_id = 'home-banners');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Updated-at trigger
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_home_banners_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS home_banners_updated_at ON public.home_banners;
CREATE TRIGGER home_banners_updated_at
  BEFORE UPDATE ON public.home_banners
  FOR EACH ROW EXECUTE FUNCTION public.trg_home_banners_updated_at();
