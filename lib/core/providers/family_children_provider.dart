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
    yield rows.where((r) => r['deleted_at'] == null).toList();
  }
});
