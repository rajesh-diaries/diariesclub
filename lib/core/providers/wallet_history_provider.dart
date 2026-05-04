import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Filter pills shown above the wallet history list.
enum WalletHistoryFilter { all, topUps, sessions, orders, refunds, bonuses }

extension WalletHistoryFilterX on WalletHistoryFilter {
  /// `wallet_transactions.type` values that belong in this filter bucket.
  /// The "All" bucket returns null — caller skips the `.in_` clause.
  List<String>? get types => switch (this) {
        WalletHistoryFilter.all => null,
        WalletHistoryFilter.topUps => const ['topup'],
        WalletHistoryFilter.sessions => const [
            'session_debit',
            'extension_debit',
          ],
        WalletHistoryFilter.orders => const [
            'order_debit',
            'workshop_debit',
            'birthday_deposit_debit',
            'birthday_balance_debit',
          ],
        WalletHistoryFilter.refunds => const ['refund'],
        WalletHistoryFilter.bonuses => const [
            'bonus',
            'coins_credit',
            'reactivation_credit',
            'visit_bonus',
            'streak_milestone',
          ],
      };

  String get label => switch (this) {
        WalletHistoryFilter.all => 'All',
        WalletHistoryFilter.topUps => 'Top-ups',
        WalletHistoryFilter.sessions => 'Sessions',
        WalletHistoryFilter.orders => 'Orders',
        WalletHistoryFilter.refunds => 'Refunds',
        WalletHistoryFilter.bonuses => 'Bonuses',
      };
}

/// Currently-selected filter for the wallet history screen. Local UI state.
final walletHistoryFilterProvider =
    StateProvider<WalletHistoryFilter>((ref) => WalletHistoryFilter.all);

/// Page size — small enough to feel instant on slow networks, big enough
/// that most users see a few groups before paginating.
const walletHistoryPageSize = 20;

/// One page of wallet transactions. Pagination lives in the screen
/// (offset-based, since wallet_transactions uses created_at ordering).
final walletHistoryPageProvider = FutureProvider.family<
    List<Map<String, dynamic>>, int>((ref, page) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];
  final filter = ref.watch(walletHistoryFilterProvider);

  var query = Supabase.instance.client
      .from('wallet_transactions')
      .select()
      .eq('family_id', familyId);

  final types = filter.types;
  if (types != null) {
    query = query.inFilter('type', types);
  }

  final from = page * walletHistoryPageSize;
  final to = from + walletHistoryPageSize - 1;

  final rows = await query
      .order('created_at', ascending: false)
      .range(from, to);

  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});
