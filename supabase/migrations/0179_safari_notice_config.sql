-- Admin-configurable Safari Club notice banner
ALTER TABLE public.venue_config
ADD COLUMN IF NOT EXISTS safari_notice_title TEXT,
ADD COLUMN IF NOT EXISTS safari_notice_body TEXT,
ADD COLUMN IF NOT EXISTS safari_notice_enabled BOOLEAN NOT NULL DEFAULT FALSE;
