import 'package:flutter/material.dart';
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
///
/// Implementation note: we do a one-shot read first so Home renders
/// immediately, then attach a best-effort Realtime stream for live
/// updates. If Realtime hits a transport/channel error (common on
/// flaky networks or iOS backgrounding), we keep the last known data
/// instead of crashing the Home tab with a technical error screen.
final activeSessionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final client = Supabase.instance.client;

  // One-shot read — reliable even when Realtime is having trouble.
  try {
    final initialRows = await client
        .from('sessions')
        .select()
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(20);
    yield _filterOpen(
      (initialRows as List).cast<Map<String, dynamic>>(),
    );
  } catch (e, st) {
    debugPrint('[activeSessionsProvider] initial read failed: $e\n$st');
    yield const [];
  }

  // Best-effort live updates.
  try {
    final stream = client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(20);

    await for (final rows in stream) {
      yield _filterOpen(rows);
    }
  } catch (e) {
    debugPrint('[activeSessionsProvider] realtime stream error (non-fatal): $e');
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

List<Map<String, dynamic>> _filterOpen(List<Map<String, dynamic>> rows) {
  final now = DateTime.now();
  final open = rows.where((r) {
    final status = r['status'] as String?;
    if (status != 'pending' && status != 'active' && status != 'grace') {
      return false;
    }
    // Stuck-session escape: anything more than 24h old shouldn't
    // count as live. (Real sessions auto-close in grace + 30min via cron.)
    final createdAt = DateTime.tryParse((r['created_at'] as String?) ?? '');
    if (createdAt != null && now.difference(createdAt).inHours > 24) {
      return false;
    }
    return true;
  }).toList();
  return List<Map<String, dynamic>>.from(open);
}
