-- 0114 — FIT subscription has its own separate app. New venue_config
-- field for the FIT app URL (Play Store / App Store / web) so the
-- customer's FIT tab can surface a small "Already use the FIT app?"
-- footer link beneath the WhatsApp banner.
--
-- Leave NULL by default so the footer link hides until admin fills it
-- in. Banner stays WhatsApp-first either way.

ALTER TABLE venue_config
  ADD COLUMN IF NOT EXISTS fit_app_url TEXT;
