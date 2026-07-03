-- 0214_drop_functions_removed_from_prod.sql
-- FULL-CONVERGENCE (DRAFT — not applied). Mirror image of 0213: these 4 functions exist
-- in the repo (created by earlier migrations) but were DROPPED from prod as part of the
-- keepsake/photo-feature removal (prod ledger: remove_all_photo_features), whose file was
-- never committed. A from-scratch replay would recreate them and diverge from prod, so we
-- drop them here to match prod.
--
--   admin_birthday_keepsake_delete   (0108_admin_birthday_keepsake_photo_upload.sql)
--   admin_birthday_keepsake_upload   (0108_admin_birthday_keepsake_photo_upload.sql)
--   birthday_album_publish           (0108_admin_birthday_keepsake_photo_upload.sql)
--   birthday_reservation_create      (0014_birthday_funnel.sql)  [superseded by a newer path in prod]
--
-- Signature-agnostic + idempotent: drops every overload found by name, no-op on prod (none
-- exist there). NOTE: birthday_reservation_create is birthday-flow adjacent — confirm the
-- current reservation path before applying (this only removes the legacy overload prod
-- already removed).

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_birthday_keepsake_delete',
        'admin_birthday_keepsake_upload',
        'birthday_album_publish',
        'birthday_reservation_create'
      )
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig::text;
  END LOOP;
END $$;
