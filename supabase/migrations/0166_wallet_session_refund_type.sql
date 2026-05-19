-- 0166 — Add 'session_refund' to wallet_transactions.type CHECK.
--
-- session_cancel_pending RPC inserts a wallet_transactions row with
-- type='session_refund' when refunding a customer's held wallet balance
-- after they (or the auto-cancel cron) cancel a pre-scan pending session.
-- The value was never in the CHECK constraint, so every cancel attempt
-- failed with "violates check constraint wallet_transactions_type_check"
-- (surfaced on the QR screen as 'Couldn't cancel: ...' after we improved
-- error reporting in session_qr_screen.dart this morning).
--
-- Fix: widen the constraint. Behaviour of the RPC is unchanged.

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check CHECK (
    type = ANY (ARRAY[
      'topup','bonus',
      'session_debit','extension_debit','order_debit','workshop_debit',
      'birthday_deposit_debit','birthday_balance_debit',
      'refund','session_refund',
      'coins_credit','coins_debit',
      'reactivation_credit','visit_bonus','streak_milestone',
      'manual_credit','manual_debit'
    ])
  );
