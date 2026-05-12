-- 0112 — admin can upload custom PDFs to packages. Replaces the
-- auto-generated PDF flow with a "you provide the PDF" model. Admin
-- picks a file, uploads to the package-pdfs bucket (public), then
-- calls admin_package_set_pdf_url to persist the URL on the package row.

CREATE POLICY package_pdfs_admin_write
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'package-pdfs'
    AND is_active_admin()
  );

CREATE POLICY package_pdfs_admin_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'package-pdfs'
    AND is_active_admin()
  );

CREATE OR REPLACE FUNCTION public.admin_package_set_pdf_url(
  p_package_id UUID,
  p_pdf_url    TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  UPDATE birthday_packages
     SET pdf_url = NULLIF(trim(p_pdf_url), '')
   WHERE id = p_package_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;
  RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_package_set_pdf_url(UUID, TEXT)
  TO authenticated;
