import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../bootstrap.dart' show registerChildNamesForScrub;
import 'auth_provider.dart';

/// Realtime stream of the current family's *live* (non-archived) children.
/// Filters out `deleted_at IS NOT NULL` rows client-side because Supabase
/// `.stream()` doesn't yet support `.is_('deleted_at', null)` filters —
/// streaming the unfiltered list and filtering in Dart is fine for the
/// small handful of children a family has.
///
/// Resilience: a one-shot read seeds the state so the Adventure tab
/// renders even if the Realtime subscription later fails (iOS post-login
/// channelError 1002 is the recurring symptom). Realtime errors are
/// swallowed silently so we don't surface "Couldn't load adventure"
/// (E-ADV) for what is effectively a transient WebSocket issue.
List<Map<String, dynamic>> _dedupeLive(List<dynamic> rows) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final m = r as Map;
    if (m['deleted_at'] != null) continue;
    final id = m['id'] as String?;
    if (id == null || !seen.add(id)) continue;
    out.add(Map<String, dynamic>.from(m));
  }
  return out;
}

List<Map<String, dynamic>> _registerAndReturn(List<Map<String, dynamic>> rows) {
  registerChildNamesForScrub(
    rows.map((c) => (c['name'] as String?) ?? '').where((n) => n.isNotEmpty),
  );
  return rows;
}

final familyChildrenProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    // Sign-out — clear the Sentry scrub registry.
    registerChildNamesForScrub(const []);
    yield const [];
    return;
  }

  final client = Supabase.instance.client;

  // One-shot initial read so the screen has data even if Realtime later
  // errors (iOS post-login channelError 1002).
  final initialRows = await client
      .from('children')
      .select()
      .eq('family_id', familyId)
      .order('created_at', ascending: true);
  yield _registerAndReturn(_dedupeLive(initialRows as List));

  // Best-effort Realtime subscription for live updates.
  try {
    final stream = client
        .from('children')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('created_at', ascending: true);

    await for (final rows in stream) {
      yield _registerAndReturn(_dedupeLive(rows));
    }
  } catch (e) {
    // ignore: avoid_print
    print('[family_children_provider] realtime error (non-fatal): $e');
  }
});
