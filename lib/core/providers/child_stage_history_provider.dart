import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row in the per-child stage-transition timeline. Derived from
/// `xp_events.metadata->stage_transitions` (populated by the updated
/// xp_credit_with_split in migration 0010).
class StageTransitionEntry {
  final DateTime occurredAt;
  final String trait;
  final String fromStage;
  final String toStage;

  const StageTransitionEntry({
    required this.occurredAt,
    required this.trait,
    required this.fromStage,
    required this.toStage,
  });
}

/// Timeline of stage transitions for a child, oldest first. Empty list if
/// no transitions have happened yet (every brand-new child starts here).
final childStageHistoryProvider = FutureProvider.family<
    List<StageTransitionEntry>, String>((ref, childId) async {
  final rows = await Supabase.instance.client
      .from('xp_events')
      .select('created_at, metadata')
      .eq('child_id', childId)
      .order('created_at', ascending: true);

  final out = <StageTransitionEntry>[];
  for (final row in rows as List) {
    final metadata = (row as Map)['metadata'];
    if (metadata is! Map) continue;
    final transitions = metadata['stage_transitions'];
    if (transitions is! List || transitions.isEmpty) continue;
    final at = DateTime.parse(row['created_at'] as String);
    for (final t in transitions) {
      if (t is! Map) continue;
      out.add(StageTransitionEntry(
        occurredAt: at,
        trait: t['trait'] as String,
        fromStage: t['from'] as String,
        toStage: t['to'] as String,
      ));
    }
  }
  return out;
});
