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

/// Convenience selector — paise as int, or `null` if the wallet hasn't
/// loaded yet.
final walletBalancePaiseProvider = Provider<int?>((ref) {
  final w = ref.watch(currentWalletProvider).valueOrNull;
  return w == null ? null : (w['balance_paise'] as int);
});
