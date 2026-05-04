import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Aggregated referral stats for the Referral details screen. Derived from
/// `referral_uses` (claims) and `wallet_transactions` (gifter credits).
/// Returns zeroed counts when the underlying tables don't exist yet —
/// referral funnel is finalized in a later session.
class ReferralStats {
  final int totalReferrals;
  final int thisMonthReferrals;
  final int monthlyCap;
  final int totalEarnedPaise;

  const ReferralStats({
    required this.totalReferrals,
    required this.thisMonthReferrals,
    required this.monthlyCap,
    required this.totalEarnedPaise,
  });

  static const empty = ReferralStats(
    totalReferrals: 0,
    thisMonthReferrals: 0,
    monthlyCap: 0,
    totalEarnedPaise: 0,
  );
}

final referralStatsProvider = FutureProvider<ReferralStats>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return ReferralStats.empty;

  // Best-effort across tables that may not exist yet. The whole funnel is
  // designed but only partially built; missing tables → empty stats.
  int total = 0;
  int thisMonth = 0;
  int monthlyCap = 0;
  int totalEarnedPaise = 0;

  try {
    final firstOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1)
        .toUtc()
        .toIso8601String();
    final all = await Supabase.instance.client
        .from('referral_uses')
        .select('id, created_at, status')
        .eq('referrer_family_id', familyId);
    final list = (all as List).cast<Map<String, dynamic>>();
    total = list.length;
    thisMonth = list
        .where((r) =>
            (r['created_at'] as String?) != null &&
            (r['created_at'] as String).compareTo(firstOfMonth) >= 0)
        .length;
  } catch (_) {
    // Table absent — leave zeros.
  }

  try {
    final earned = await Supabase.instance.client
        .from('wallet_transactions')
        .select('amount_paise, type')
        .eq('family_id', familyId)
        .inFilter('type', ['bonus']);
    for (final r in earned as List) {
      final amount = (r['amount_paise'] as int?) ?? 0;
      if (amount > 0) totalEarnedPaise += amount;
    }
  } catch (_) {
    // No-op.
  }

  return ReferralStats(
    totalReferrals: total,
    thisMonthReferrals: thisMonth,
    monthlyCap: monthlyCap,
    totalEarnedPaise: totalEarnedPaise,
  );
});
