import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// All currently-open sessions for the family — one row per child that's
/// either in `pending` (wallet hold placed, waiting for QR scan) or
/// `active` / `grace` (playing). Multiple kids can have parallel
/// sessions; this is the source of truth for the home view's session
/// stack.
///
/// Ignores rows older than 24h to dodge stuck-session leftovers
/// (BUG-038 escape).
final activeSessionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final stream = Supabase.instance.client
      .from('sessions')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(20);

  await for (final rows in stream) {
    final now = DateTime.now();
    final open = rows.where((r) {
      final status = r['status'] as String?;
      if (status != 'pending' && status != 'active' && status != 'grace') {
        return false;
      }
      // Stuck-session escape: anything more than 24h old shouldn't
      // count as live. (Real sessions auto-close in grace + 30min via cron.)
      final createdAt =
          DateTime.tryParse((r['created_at'] as String?) ?? '');
      if (createdAt != null && now.difference(createdAt).inHours > 24) {
        return false;
      }
      return true;
    }).toList();
    yield List<Map<String, dynamic>>.from(open);
  }
});

/// Convenience: child IDs that already have an open session. Used by
/// Start a session to disable already-playing children in the picker.
final childrenWithActiveSessionProvider = Provider<Set<String>>((ref) {
  final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];
  return sessions
      .map((s) => s['child_id'] as String?)
      .whereType<String>()
      .toSet();
});
