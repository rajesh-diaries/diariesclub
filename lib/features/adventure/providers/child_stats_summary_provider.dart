import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'child_by_id_provider.dart';

/// Four-fact stats summary for the dashboard: completed sessions count,
/// lifetime total XP, current overall level, and "days as a hero" since
/// the child's first completed session. Composed client-side from
/// existing tables — no new RPC needed.
class ChildStatsSummary {
  final int sessionsCompleted;
  final int totalXp;
  final int currentLevel;
  final int? daysAsHero;

  const ChildStatsSummary({
    required this.sessionsCompleted,
    required this.totalXp,
    required this.currentLevel,
    required this.daysAsHero,
  });
}

final childStatsSummaryProvider = FutureProvider.family<
    ChildStatsSummary, String>((ref, childId) async {
  final child = ref.watch(childByIdProvider(childId));
  final totalXp = (child?['total_xp'] as int?) ?? 0;
  final currentLevel = (child?['current_level'] as int?) ?? 1;

  // Completed sessions count (cheap — count(*) of a filtered query).
  final completed = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('child_id', childId)
      .inFilter('status', ['completed', 'auto_closed']);
  final sessionsCompleted = (completed as List).length;

  // First completed session timestamp → "days as a hero".
  int? daysAsHero;
  if (sessionsCompleted > 0) {
    final firstRow = await Supabase.instance.client
        .from('sessions')
        .select('created_at')
        .eq('child_id', childId)
        .inFilter('status', ['completed', 'auto_closed'])
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    final firstCreated = firstRow?['created_at'] as String?;
    if (firstCreated != null) {
      final since = DateTime.parse(firstCreated).toLocal();
      daysAsHero = DateTime.now().difference(since).inDays;
    }
  }

  return ChildStatsSummary(
    sessionsCompleted: sessionsCompleted,
    totalXp: totalXp,
    currentLevel: currentLevel,
    daysAsHero: daysAsHero,
  );
});
