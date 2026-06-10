-- Create Safari Club waitlist table
CREATE TABLE public.safari_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid REFERENCES public.families(id) ON DELETE SET NULL,
  parent_name text NOT NULL,
  phone text NOT NULL,
  child_name text NOT NULL,
  child_age int NOT NULL CHECK (child_age IN (2, 3, 4)),
  source text DEFAULT 'app',
  status text DEFAULT 'pending',
  admin_notes text,
  created_at timestamptz DEFAULT now(),
  contacted_at timestamptz
);

-- Enable RLS
ALTER TABLE public.safari_waitlist ENABLE ROW LEVEL SECURITY;

-- Indexes for common lookups
CREATE INDEX idx_safari_waitlist_family_id ON public.safari_waitlist(family_id);
CREATE INDEX idx_safari_waitlist_status ON public.safari_waitlist(status);
CREATE INDEX idx_safari_waitlist_created_at ON public.safari_waitlist(created_at DESC);

-- RLS: anyone can insert
CREATE POLICY "Allow anonymous insert on safari_waitlist"
  ON public.safari_waitlist
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- RLS: only admins can select
CREATE POLICY "Allow admin select on safari_waitlist"
  ON public.safari_waitlist
  FOR SELECT
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.admin_users WHERE auth_user_id = auth.uid() AND is_active = true
  ));

-- RLS: only admins can update
CREATE POLICY "Allow admin update on safari_waitlist"
  ON public.safari_waitlist
  FOR UPDATE
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.admin_users WHERE auth_user_id = auth.uid() AND is_active = true
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.admin_users WHERE auth_user_id = auth.uid() AND is_active = true
  ));
