import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// One reservation row, derived from the family-wide stream.
///
/// We used to open a separate `.stream().eq('id', id)` per row, but
/// the realtime subscription on a UUID-filtered stream was erroring
/// out intermittently in production (E-BSTAT on the status screen).
/// The family-wide stream already loads up to 20 reservations and
/// stays subscribed for the session — pulling one row out of it is
/// free and removes a flaky network channel.
final reservationByIdProvider =
    Provider.family<AsyncValue<Map<String, dynamic>?>, String>((ref, id) {
  final async = ref.watch(familyReservationsProvider);
  return async.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (rows) {
      final match = rows.firstWhere(
        (r) => r['id'] == id,
        orElse: () => const <String, dynamic>{},
      );
      return AsyncValue.data(match.isEmpty ? null : match);
    },
  );
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
