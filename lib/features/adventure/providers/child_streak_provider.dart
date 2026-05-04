import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime stream of the child's `streak_records` row (one per child).
/// Returns null while the row hasn't been created yet — the streak
/// tracker widget renders a "no streak yet" state in that case.
final childStreakProvider = StreamProvider.family<
    Map<String, dynamic>?, String>((ref, childId) async* {
  final stream = Supabase.instance.client
      .from('streak_records')
      .stream(primaryKey: ['id'])
      .eq('child_id', childId)
      .limit(1);
  await for (final rows in stream) {
    yield rows.isEmpty ? null : rows.first;
  }
});
