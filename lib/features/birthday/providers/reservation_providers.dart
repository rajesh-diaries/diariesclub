import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// Realtime stream of one reservation row. Used by the status screen +
/// the album screen. `birthday_reservations` is in supabase_realtime
/// (added in 0014), so admin status flips land within seconds.
final reservationByIdProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, id) async* {
  final stream = Supabase.instance.client
      .from('birthday_reservations')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .limit(1);
  await for (final rows in stream) {
    yield rows.isEmpty ? null : rows.first;
  }
});

/// Realtime stream of all reservations for the current family. Used by
/// the Home BirthdayCard state machine to find each child's most recent
/// active reservation. Sorted newest first; capped at 20 to keep
/// payloads tight.
final familyReservationsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }
  final stream = Supabase.instance.client
      .from('birthday_reservations')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(20);
  await for (final rows in stream) {
    yield rows;
  }
});

/// Realtime stream of birthday photos for one reservation. The bucket is
/// private + family-scoped via RLS. The widgets resolve each path into a
/// signed URL via `signedBirthdayPhotoUrlProvider`.
final birthdayPhotosProvider = StreamProvider.family<
    List<Map<String, dynamic>>, String>((ref, reservationId) async* {
  final stream = Supabase.instance.client
      .from('birthday_party_photos')
      .stream(primaryKey: ['id'])
      .eq('reservation_id', reservationId)
      .order('created_at', ascending: true);
  await for (final rows in stream) {
    yield rows;
  }
});
