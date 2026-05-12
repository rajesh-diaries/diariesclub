-- 0110 — admin can read birthday_party_photos rows. Was missing — only
-- bd_photos_family_read existed, so after uploading via the keepsake
-- RPC the admin drawer couldn't fetch the row back to render the
-- preview (the customer saw it fine because the family policy applies).

CREATE POLICY birthday_party_photos_admin_read
  ON birthday_party_photos FOR SELECT
  USING (is_active_admin());
