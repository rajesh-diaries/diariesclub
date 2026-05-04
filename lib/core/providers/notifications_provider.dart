import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Live stream of the current family's notification rows. Sorted newest
/// first; capped at 50 to keep payload small (older history lives behind
/// "See all" — Session 5b/Profile).
final notificationsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final stream = Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(50);

  await for (final rows in stream) {
    yield rows;
  }
});

/// Number of unread notifications. Used for the bell badge on HomeAppBar.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => n['is_read'] == false).length;
});
