import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Live snapshot of the current family's wallet row. Re-emits on every change
/// to the `wallets` table for this family (added to supabase_realtime in
/// migration 0008).
///
/// Yields `null` while waiting for the first row — UIs that show a balance
/// should render a shimmer in that case rather than a misleading "₹0".
final currentWalletProvider =
    StreamProvider<Map<String, dynamic>?>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield null;
    return;
  }

  final stream = Supabase.instance.client
      .from('wallets')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .limit(1);

  await for (final rows in stream) {
    yield rows.isEmpty ? null : rows.first;
  }
});

/// Live sum of `wallet_transactions.amount_paise` for the current family.
///
/// Several backend RPCs (e.g. `play_pass_purchase`) use the transaction ledger
/// as the source of truth, so the UI must match that ledger. A stale
/// `wallets.balance_paise` row can show money the user doesn't actually have.
final walletTransactionsBalanceProvider = StreamProvider<int?>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield null;
    return;
  }

  final stream = Supabase.instance.client
      .from('wallet_transactions')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId);

  await for (final rows in stream) {
    var sum = 0;
    for (final r in rows) {
      final amount = (r['amount_paise'] as num?)?.toInt() ?? 0;
      sum += amount;
    }
    yield sum;
  }
});

/// Convenience selector — paise as int, or `null` if the wallet hasn't
/// loaded yet. Uses the wallet row's `balance_paise` as the source of truth
/// so the UI never shows a stale transaction-sum during realtime races.
final walletBalancePaiseProvider = Provider<int?>((ref) {
  final wallet = ref.watch(currentWalletProvider).valueOrNull;
  if (wallet == null) return null;
  return (wallet['balance_paise'] as num?)?.toInt();
});


