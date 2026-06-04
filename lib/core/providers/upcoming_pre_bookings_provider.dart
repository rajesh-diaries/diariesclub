import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Reserved pre-bookings for the current family, joined with child name
/// and favourite_hero so the launchpad can show a personalised face.
///
/// Only returns rows where:
///   * status = 'reserved'
///   * scheduled_start is in the future (or within the last 15 min — grace
///     for "I'm here!" taps that happen slightly after the slot start)
///   * expires_at hasn't passed
///
/// Ordered by scheduled_start ascending (nearest booking first).
final upcomingPreBookingsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final client = Supabase.instance.client;
  final now = DateTime.now().toUtc();
  final graceCutoff = now.subtract(const Duration(minutes: 15));

  // One-shot initial read.
  final initialRows = await client
      .from('session_pre_bookings')
      .select('*, children(name, favourite_hero)')
      .eq('family_id', familyId)
      .eq('status', 'reserved')
      .gte('scheduled_start', graceCutoff.toIso8601String())
      .gte('expires_at', now.toIso8601String())
      .order('scheduled_start', ascending: true);

  yield _flatten((initialRows as List).cast<Map<String, dynamic>>());

  // Best-effort realtime for when a pre-booking is redeemed / cancelled.
  try {
    final stream = client
        .from('session_pre_bookings')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('scheduled_start', ascending: true);

    await for (final rows in stream) {
      final filtered = rows.where((r) {
        final status = (r['status'] as String?) ?? '';
        if (status != 'reserved') return false;
        final scheduledStart = _parseTime(r['scheduled_start']);
        final expiresAt = _parseTime(r['expires_at']);
        if (scheduledStart == null || expiresAt == null) return false;
        return scheduledStart.isAfter(graceCutoff) && expiresAt.isAfter(now);
      }).toList();

      yield _flatten(filtered.cast<Map<String, dynamic>>());
    }
  } catch (e) {
    // ignore: avoid_print
    print('[upcoming_pre_bookings_provider] realtime error (non-fatal): $e');
  }
});

DateTime? _parseTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Flatten the nested `children` object into top-level keys so the widget
/// doesn't need to know Supabase's join shape.
List<Map<String, dynamic>> _flatten(List<Map<String, dynamic>> rows) {
  return rows.map((r) {
    final child = r['children'] as Map<String, dynamic>?;
    return {
      ...r,
      'child_name': child?['name'] as String?,
      'favourite_hero': child?['favourite_hero'] as String?,
    };
  }).toList();
}
