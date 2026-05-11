-- 0088 — admin read access for /admin/customers/:id detail screen
--
-- Bug: the customer detail screen does direct PostgREST reads against
-- families / wallets / children / sessions / orders / wallet_transactions,
-- but those tables only have family-self RLS policies. Result:
-- 'Cannot coerce the result to a single JSON object' when an admin
-- opens any customer other than their own family.
--
-- Fix: add is_active_admin() SELECT policies. Admin can read every
-- row; existing family-self policies stay for the customer app.

DROP POLICY IF EXISTS families_admin_read ON families;
CREATE POLICY families_admin_read ON families
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS wallets_admin_read ON wallets;
CREATE POLICY wallets_admin_read ON wallets
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS children_admin_read ON children;
CREATE POLICY children_admin_read ON children
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS sessions_admin_read ON sessions;
CREATE POLICY sessions_admin_read ON sessions
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS orders_admin_read ON orders;
CREATE POLICY orders_admin_read ON orders
  FOR SELECT USING (is_active_admin());

DROP POLICY IF EXISTS wallet_tx_admin_read ON wallet_transactions;
CREATE POLICY wallet_tx_admin_read ON wallet_transactions
  FOR SELECT USING (is_active_admin());
