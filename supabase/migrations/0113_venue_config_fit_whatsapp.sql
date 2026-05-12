-- 0113 — FIT subscription/delivery runs on a separate WhatsApp line
-- from the main venue support. New column with the FIT line number;
-- falls back to whatsapp_support_phone when empty.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS fit_whatsapp_phone TEXT;

-- Seed with the same number as main for now so the banner works
-- immediately. Admin can edit when they switch lines.
UPDATE venue_config
   SET fit_whatsapp_phone = COALESCE(fit_whatsapp_phone, whatsapp_support_phone)
 WHERE venue_id = '00000000-0000-0000-0000-000000000001';
