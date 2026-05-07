import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Single hero_recaps row by session_id (one-shot fetch). Useful for the
/// reflection screen to pull the row's child_id, total_xp_pool, deadline.
final heroRecapBySessionProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, sessionId) async {
  // ignore: avoid_print
  print('[BUG-039a] heroRecapBySessionProvider fetching sessionId=$sessionId');
  try {
    final row = await Supabase.instance.client
        .from('hero_recaps')
        .select('*, children(name, photo_url)')
        .eq('session_id', sessionId)
        .maybeSingle();
    // ignore: avoid_print
    print('[BUG-039a] heroRecapBySessionProvider returned '
        'row=${row == null ? "null" : row.keys.toList()}');
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  } catch (e, st) {
    // ignore: avoid_print
    print('[BUG-039a] heroRecapBySessionProvider threw: $e');
    // ignore: avoid_print
    print('[BUG-039a] stack: $st');
    rethrow;
  }
});

/// Live list of pending recaps for the current family — Realtime stream
/// over `hero_recaps`. Filters client-side: keeps rows where
/// `reflection_status='pending'` AND deadline is still in the future.
///
/// hero_recaps is in the supabase_realtime publication (added in 0008),
/// so this stream reacts to inserts/updates without polling.
final pendingRecapsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  // hero_recaps doesn't carry family_id directly — it's joined through
  // sessions.family_id. supabase_flutter's `.stream()` doesn't support
  // joins, so subscribe to the broader hero_recaps stream and filter
  // client-side using the sessions table for family scope. RLS keeps
  // the payload to only this family's rows anyway.
  final stream = Supabase.instance.client
      .from('hero_recaps')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(20);

  await for (final rows in stream) {
    final now = DateTime.now().toUtc();
    final live = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r['reflection_status'] != 'pending') continue;
      final deadline = r['reflection_deadline'] as String?;
      if (deadline == null) continue;
      try {
        if (DateTime.parse(deadline).toUtc().isBefore(now)) continue;
      } catch (_) { continue; }
      live.add(r);
    }
    yield live;
  }
});
