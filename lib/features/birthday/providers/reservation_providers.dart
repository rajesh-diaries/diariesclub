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

/// REST list of all reservations for the current family. Used by the
/// Home BirthdayCard state machine to find each child's most recent
/// active reservation. Sorted newest first; capped at 20.
///
/// Was a StreamProvider with .stream() realtime, but the subscription
/// was hitting RealtimeSubscribeStatus.channelError on iOS 26 (E-BSTAT
/// on the status screen 2026-05-18). Reservation status transitions
/// happen within hours, not seconds, so polling/refresh-on-demand is
/// the right model. Customers pull-to-refresh; the Home BirthdayCard
/// invalidates this provider when relevant actions complete.
final familyReservationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];
  final rows = await Supabase.instance.client
      .from('birthday_reservations')
      .select()
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(20);
  return List<Map<String, dynamic>>.from(rows);
});

/// REST list of birthday photos for one reservation. Same realtime →
/// REST migration as familyReservationsProvider — photos are uploaded
/// in batches by admin, customer doesn't need second-by-second updates.
final birthdayPhotosProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, reservationId) async {
  final rows = await Supabase.instance.client
      .from('birthday_party_photos')
      .select()
      .eq('reservation_id', reservationId)
      .order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
