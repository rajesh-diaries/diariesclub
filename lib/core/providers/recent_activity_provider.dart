import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Last few activity rows from the `home_recent_activity` view (defined in
/// migration 0008). The view UNIONs wallet_transactions, completed sessions,
/// and xp_events with a uniform shape; the client just renders by `kind`.
///
/// One-shot fetch — invalidate when wallet/session/xp realtime fires (the
/// HomeScreen listens to those streams and calls
/// `ref.invalidate(recentActivityProvider)`).
final recentActivityProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  final rows = await Supabase.instance.client
      .from('home_recent_activity')
      .select()
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(3);

  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});
