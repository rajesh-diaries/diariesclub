-- 0106 — admin needs to read all birthday_reservations for the CRM
-- kanban. Previously only `bd_res_family` (family_id = auth.uid()) was
-- defined, so admin queries via PostgREST returned 0 rows even though
-- SECURITY DEFINER RPCs (which power the KPI tiles) saw everything.
-- That mismatch let the dashboard show "Inquiries: 3" while the
-- pipeline columns rendered empty.

CREATE POLICY birthday_reservations_admin_read
  ON birthday_reservations FOR SELECT
  USING (is_active_admin());
