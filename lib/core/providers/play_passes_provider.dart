import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// The family's active (non-expired, non-used-up) play passes.
/// Returns a list of pass rows ordered by expiry (soonest first).
final playPassesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  final rows = await Supabase.instance.client
      .from('play_passes')
      .select()
      .eq('family_id', familyId)
      .gt('expires_at', DateTime.now().toIso8601String())
      .order('expires_at', ascending: true);

  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .where((p) => (p['used_passes'] as int?)! < (p['total_passes'] as int?)!)
      .toList();
});

/// Total remaining passes across all active passes.
final remainingPassesCountProvider = Provider<int>((ref) {
  final passes = ref.watch(playPassesProvider).valueOrNull ?? const [];
  var count = 0;
  for (final p in passes) {
    final total = (p['total_passes'] as int?) ?? 0;
    final used = (p['used_passes'] as int?) ?? 0;
    count += (total - used).clamp(0, total);
  }
  return count;
});
