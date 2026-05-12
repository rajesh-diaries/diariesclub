import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime stream of all sessions in active or grace state across all
/// venues. Single-venue today; multi-venue later just needs an admin
/// venue picker that filters this list.
final adminActiveSessionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('sessions')
      .stream(primaryKey: ['id'])
      .order('started_at', ascending: true);
  await for (final rows in stream) {
    yield rows
        .where((r) => r['status'] == 'active' || r['status'] == 'grace')
        .toList();
  }
});

/// Realtime stream of pending refunds (admin must approve >₹500 ones).
final adminPendingRefundsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('refunds')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);
  await for (final rows in stream) {
    yield rows.where((r) => r['status'] == 'pending').toList();
  }
});

/// Realtime stream of all refunds (any status). Powers the Refunds tabs.
final adminAllRefundsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('refunds')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(200);
  await for (final rows in stream) {
    yield rows;
  }
});

/// Enriched detail for a single reservation — joins family, child,
/// package, wallet + lifetime spend via the admin_birthday_reservation_detail
/// RPC. Powers the right-hand drawer in the Birthday CRM so the admin
/// has all the customer context without four separate fetches.
final adminReservationDetailProvider = FutureProvider.family<
    Map<String, dynamic>, String>((ref, reservationId) async {
  final raw = await Supabase.instance.client.rpc<dynamic>(
    'admin_birthday_reservation_detail',
    params: {'p_reservation_id': reservationId},
  );
  return raw is Map ? Map<String, dynamic>.from(raw) : const {};
});

/// Birthday reservations for the CRM kanban.
///
/// Switched from .stream() to a polling .select() because the realtime
/// subscription was returning zero rows for admins (PIPELINE columns
/// stuck on 0 even though the dashboard RPC counted inquiries). The
/// kanban refreshes via ref.refresh after any RPC action (contact /
/// confirm / cancel / complete) plus a 30s polling tick for ambient
/// freshness.
final adminBirthdayReservationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  // Ambient refresh: re-poll every 30s so new inquiries surface without
  // needing a manual page reload.
  final ticker = Stream<void>.periodic(const Duration(seconds: 30));
  final sub = ticker.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);

  final rows = await Supabase.instance.client
      .from('birthday_reservations')
      .select()
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .where(
          (r) => r['status'] != 'cancelled' && r['status'] != 'no_show')
      .toList();
});

/// Today's session count (admin dashboard top stat).
final adminTodaySessionCountProvider = FutureProvider<int>((ref) async {
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final rows = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .gte('created_at', since);
  return (rows as List).length;
});

/// Selected month for the Birthday CRM dashboard. 1..12; defaults to
/// current IST month.
final adminBirthdayDashboardMonthProvider = StateProvider<int>((ref) {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return ist.month;
});

/// One-shot dashboard fetch for the Birthday CRM (KPIs + attention
/// counters + birthdays-this-month list). Re-runs when the month
/// selector changes or when reservations stream emits (so the
/// numbers stay fresh after a status flip).
final adminBirthdayDashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final month = ref.watch(adminBirthdayDashboardMonthProvider);
  // Re-fetch when the reservations stream emits — keeps KPIs in
  // lockstep with the kanban without manual invalidation.
  ref.watch(adminBirthdayReservationsProvider);
  final raw = await Supabase.instance.client.rpc<dynamic>(
    'admin_birthday_dashboard',
    params: {'p_month': month},
  );
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
});

/// Today's healthy-bite distributions (admin dashboard tile). Counts
/// sessions where staff handed out a bite in the last 24h.
final adminTodayHealthyBitesProvider = FutureProvider<int>((ref) async {
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final rows = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('healthy_bite_distributed', true)
      .gte('created_at', since);
  return (rows as List).length;
});

/// Today's cash collected across cash + cash_walkin payment methods.
final adminTodayCashProvider = FutureProvider<int>((ref) async {
  final since = DateTime.now()
      .toUtc()
      .subtract(const Duration(hours: 24))
      .toIso8601String();
  final sessions = await Supabase.instance.client
      .from('sessions')
      .select('amount_paise')
      .inFilter('payment_method', ['cash', 'cash_walkin'])
      .gte('created_at', since);
  final orders = await Supabase.instance.client
      .from('orders')
      .select('total_paise')
      .inFilter('payment_method', ['cash', 'cash_walkin'])
      .gte('created_at', since);
  final st = (sessions as List)
      .fold<int>(0, (s, r) => s + ((r['amount_paise'] as int?) ?? 0));
  final ot = (orders as List)
      .fold<int>(0, (s, r) => s + ((r['total_paise'] as int?) ?? 0));
  return st + ot;
});

/// Realtime stream of audit_log for the audit viewer. Capped at 500 so
/// the front-end stays snappy; older rows reachable via the date filter.
final adminAuditLogProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('audit_log')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500);
  await for (final rows in stream) {
    yield rows;
  }
});

/// Realtime stream of all staff. Powers the Users / Staff management table.
final adminStaffListProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('staff')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);
  await for (final rows in stream) {
    yield rows;
  }
});

/// Realtime stream of all admin_users.
final adminUsersListProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('admin_users')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);
  await for (final rows in stream) {
    yield rows;
  }
});

/// venue_config for the Config editor.
final adminVenueConfigProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, venueId) async {
  final row = await Supabase.instance.client
      .from('venue_config')
      .select()
      .eq('venue_id', venueId)
      .single();
  return Map<String, dynamic>.from(row);
});
