import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Realtime stream of the current family's *live* (non-archived) children.
/// Filters out `deleted_at IS NOT NULL` rows client-side because Supabase
/// `.stream()` doesn't yet support `.is_('deleted_at', null)` filters —
/// streaming the unfiltered list and filtering in Dart is fine for the
/// small handful of children a family has.
final familyChildrenProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final stream = Supabase.instance.client
      .from('children')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: true);

  await for (final rows in stream) {
    // Defensive: dedupe by id. Supabase realtime sometimes emits the
    // same row twice (e.g. INSERT echo + ordered re-snapshot). The list
    // backs the Profile family list; duplicates show as ghost children.
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r['deleted_at'] != null) continue;
      final id = r['id'] as String?;
      if (id == null || !seen.add(id)) continue;
      out.add(r);
    }
    yield out;
  }
});
