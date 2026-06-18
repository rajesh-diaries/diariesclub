-- Fix: wallet_transactions.type check constraint must include 'play_pass_purchase'
-- Previous migrations (0180-0182) used EXCEPTION WHEN OTHERS which silently
-- swallowed errors, leaving the constraint unchanged on some deployments.
-- This migration drops and recreates the constraint cleanly.

DO $$
DECLARE
  v_constraint_exists boolean;
BEGIN
  -- Check whether the current constraint already allows play_pass_purchase
  SELECT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'wallet_transactions_type_check'
      AND check_clause LIKE '%play_pass_purchase%'
  ) INTO v_constraint_exists;

  IF v_constraint_exists THEN
    RAISE NOTICE 'wallet_transactions_type_check already includes play_pass_purchase — skipping';
    RETURN;
  END IF;

  -- Drop the old constraint (if any) and recreate with the full enum
  ALTER TABLE public.wallet_transactions
    DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

  ALTER TABLE public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_type_check
    CHECK (type IN (
      'topup','bonus','session_debit','extension_debit',
      'order_debit','workshop_debit','birthday_deposit_debit','birthday_balance_debit',
      'refund','coins_credit','coins_debit',
      'reactivation_credit','visit_bonus','streak_milestone',
      'manual_credit','manual_debit','play_pass_purchase'
    ));

  RAISE NOTICE 'wallet_transactions_type_check recreated with play_pass_purchase';
END $$;
