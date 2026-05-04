import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'staff_auth_provider.dart';

/// Realtime stream of all sessions at this venue in active or grace state.
/// Used by the staff home dashboard count and the active sessions screen.
final venueActiveSessionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) {
    yield const [];
    return;
  }
  final stream = Supabase.instance.client
      .from('sessions')
      .stream(primaryKey: ['id'])
      .eq('venue_id', venueId)
      .order('started_at', ascending: true);
  await for (final rows in stream) {
    yield rows
        .where((r) => r['status'] == 'active' || r['status'] == 'grace')
        .toList();
  }
});

/// Realtime stream of in-flight orders (pending/preparing/ready) at this
/// venue. Powers KDS + the home pending count.
final venueOrdersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) {
    yield const [];
    return;
  }
  final stream = Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('venue_id', venueId)
      .order('created_at', ascending: true);
  await for (final rows in stream) {
    yield rows
        .where((r) =>
            r['status'] == 'pending' ||
            r['status'] == 'preparing' ||
            r['status'] == 'ready')
        .toList();
  }
});

/// Sessions where Healthy Bite was earned but not yet handed to the child.
/// Filter is client-side (the underlying stream is already venue-scoped).
final venuePendingHealthyBitesProvider =
    Provider<List<Map<String, dynamic>>>((ref) {
  final sessions =
      ref.watch(venueActiveSessionsProvider).valueOrNull ?? const [];
  return sessions
      .where((s) =>
          s['healthy_bite_earned'] == true &&
          s['healthy_bite_distributed'] != true)
      .toList();
});

/// Today's cash collected (cash + cash_walkin) — sessions + orders combined.
/// Pulled fresh each invalidation; not Realtime because it's a sum.
final todayCashCollectedProvider = FutureProvider<int>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return 0;

  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();

  final sessions = await Supabase.instance.client
      .from('sessions')
      .select('amount_paise')
      .eq('venue_id', venueId)
      .inFilter('payment_method', ['cash', 'cash_walkin'])
      .gte('created_at', since);

  final orders = await Supabase.instance.client
      .from('orders')
      .select('total_paise')
      .eq('venue_id', venueId)
      .inFilter('payment_method', ['cash', 'cash_walkin'])
      .gte('created_at', since);

  final sessionTotal = (sessions as List).fold<int>(
    0,
    (sum, r) => sum + ((r['amount_paise'] as int?) ?? 0),
  );
  final orderTotal = (orders as List).fold<int>(
    0,
    (sum, r) => sum + ((r['total_paise'] as int?) ?? 0),
  );
  return sessionTotal + orderTotal;
});

/// Today's session count — used by the home stats bar.
final todaySessionsCountProvider = FutureProvider<int>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return 0;
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final rows = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('venue_id', venueId)
      .gte('created_at', since);
  return (rows as List).length;
});
