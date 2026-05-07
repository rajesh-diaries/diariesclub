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

/// Sessions where Healthy Bite was earned but not yet handed to the
/// child. Has its OWN stream rather than deriving from
/// venueActiveSessionsProvider — that one filters out completed/auto_closed
/// sessions, but a customer can still walk to the counter post-session
/// (within ~4 hours) and the staff app needs to see them. Without this,
/// late-distribution becomes impossible and the "pending" list shows
/// empty even when the customer screen is asking them to come collect
/// (BUG-045).
///
/// Window: started_at within last 4 hours. Beyond that, treat as
/// abandoned — admin can still distribute via direct DB tooling if a
/// customer follows up later.
final venuePendingHealthyBitesProvider =
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
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 4));
    yield rows.where((s) {
      if (s['healthy_bite_earned'] != true) return false;
      if (s['healthy_bite_distributed'] == true) return false;
      final startedRaw = s['started_at'] as String?;
      final started =
          startedRaw == null ? null : DateTime.tryParse(startedRaw);
      if (started == null || started.toUtc().isBefore(cutoff)) return false;
      // Allow active, grace, completed, auto_closed — staff can still
      // hand over the bite even if the timer has expired.
      const ok = {'active', 'grace', 'completed', 'auto_closed'};
      return ok.contains(s['status']);
    }).toList();
  }
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
