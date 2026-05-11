-- 0097 — fix infinite-recursion RLS on admin_users
--
-- The old admin_users_select policy did `EXISTS (SELECT 1 FROM
-- admin_users WHERE auth_user_id = auth.uid() AND is_active = true)`.
-- Evaluating that EXISTS triggered the same policy again, infinite
-- recursion. RLS evaluation isn't bypassed even when is_active_admin()
-- is SECURITY DEFINER, because the inline SELECT in the policy
-- expression runs as the query user.
--
-- Two replacement policies:
--   * admin_users_self_read   — admin can SELECT their OWN row
--     (auth_user_id = auth.uid()). No subquery, no recursion.
--   * admin_users_admin_read  — calls is_active_admin(), which is
--     SECURITY DEFINER and bypasses RLS inside the function body.
--     Lets active admins SELECT all admin rows (Users admin screen).

DROP POLICY IF EXISTS admin_users_select ON admin_users;

DROP POLICY IF EXISTS admin_users_self_read ON admin_users;
CREATE POLICY admin_users_self_read ON admin_users
  FOR SELECT USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS admin_users_admin_read ON admin_users;
CREATE POLICY admin_users_admin_read ON admin_users
  FOR SELECT USING (is_active_admin());
