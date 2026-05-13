import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'staff_auth_provider.dart';

/// Active + grace sessions at this venue, with embedded kid + guardian
/// names. Polled every 15s (instead of .stream(), which doesn't support
/// embedded selects) so the staff screen can show "kid · guardian"
/// alongside time-remaining/extended/healthy-bite without N+1 fetches.
final venueActiveSessionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) {
    yield const [];
    return;
  }
  // Yield once immediately, then poll every 15s. Cancellation-safe via
  // the async generator — when the screen disposes the loop ends.
  while (true) {
    final rows = await Supabase.instance.client
        .from('sessions')
        .select(
          'id, child_id, family_id, venue_id, status, '
          'started_at, expires_at, completed_at, duration_minutes, '
          'payment_method, healthy_bite_earned, healthy_bite_distributed, '
          'healthy_bite_claimed_at, '
          'children(name), families(name)',
        )
        .eq('venue_id', venueId)
        .inFilter('status', ['active', 'grace'])
        .order('expires_at', ascending: true);
    yield List<Map<String, dynamic>>.from(rows);
    await Future<void>.delayed(const Duration(seconds: 15));
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
/// child. Started life as a derived sync Provider, then a StreamProvider
/// (BUG-045), but the stream subscription occasionally hangs in dev and
/// leaves the staff screen blank with no visible loading state. Polling
/// FutureProvider is simpler, more debuggable, and "fresh enough" for a
/// staff workflow — they manually pull-to-refresh OR tap the refresh
/// button when expecting a new bite. Auto-poll every 30s as a backstop.
///
/// Window: started_at within last 4 hours so a customer can still walk
/// to the counter post-session. Beyond 4h, treat as abandoned (admin
/// can still distribute via direct RPC if a customer follows up).
final venuePendingHealthyBitesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return const [];

  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 4))
      .toIso8601String();

  // BUG-049: list shows ANY undecided session in last 4h, not just earned
  // ones. Staff makes the explicit yes/no call after the timer ends —
  // eligibility window is no longer the gate.
  final rows = await Supabase.instance.client
      .from('sessions')
      .select(
        'id, child_id, venue_id, family_id, status, started_at, '
        'expires_at, completed_at, duration_minutes, healthy_bite_earned, '
        'healthy_bite_distributed, healthy_bite_declined_at, '
        'children(name)',
      )
      .eq('venue_id', venueId)
      .eq('healthy_bite_distributed', false)
      .isFilter('healthy_bite_declined_at', null)
      .inFilter('status', ['active', 'grace', 'completed', 'auto_closed'])
      .gte('started_at', since);
  // Client sorts each section separately in the screen — keep raw rows here.
  return List<Map<String, dynamic>>.from(rows);
});

/// Healthy Bites already distributed in the last 24 hours at this venue.
/// Drives the "Given today" tab on the staff screen so staff can see
/// their own throughput + reconcile with the queue.
final venueDistributedHealthyBitesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return const [];

  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();

  final rows = await Supabase.instance.client
      .from('sessions')
      .select(
        'id, child_id, venue_id, status, started_at, completed_at, '
        'duration_minutes, healthy_bite_distributed, '
        'healthy_bite_claimed_at, children(name)',
      )
      .eq('venue_id', venueId)
      .eq('healthy_bite_distributed', true)
      .gte('healthy_bite_claimed_at', since)
      .order('healthy_bite_claimed_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
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

/// Distinct kids served at this venue in the last 24h. "Served" =
/// session reached at least active (covers active/grace/completed/
/// auto_closed), so pending-only walk-throughs don't inflate it.
final todayDistinctKidsCountProvider = FutureProvider<int>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return 0;
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final rows = await Supabase.instance.client
      .from('sessions')
      .select('child_id')
      .eq('venue_id', venueId)
      .inFilter('status', ['active', 'grace', 'completed', 'auto_closed'])
      .gte('created_at', since);
  final ids = (rows as List)
      .map((r) => r['child_id'] as String?)
      .where((id) => id != null)
      .toSet();
  return ids.length;
});

/// Today's order count (pending+preparing+ready+delivered+cancelled =
/// every order created in the last 24h). Useful for cafe throughput.
final todayOrdersCountProvider = FutureProvider<int>((ref) async {
  final venueId = ref.watch(currentTabletVenueIdProvider);
  if (venueId == null) return 0;
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final rows = await Supabase.instance.client
      .from('orders')
      .select('id')
      .eq('venue_id', venueId)
      .gte('created_at', since);
  return (rows as List).length;
});
