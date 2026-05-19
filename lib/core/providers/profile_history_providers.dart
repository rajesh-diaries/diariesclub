import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Past play sessions for the current family. Most recent first; capped
/// at 50 for v1 (no infinite scroll yet — Profile activity is glance-y).
final pastSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  final rows = await Supabase.instance.client
      .from('sessions')
      .select('*, children(name)')
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(50);

  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

/// Past café/FIT/combo orders. Joins order_items so the row can show
/// item names + classify the brand (which lives at the line-item level,
/// not on the order itself).
final pastOrdersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  try {
    final rows = await Supabase.instance.client
        .from('orders')
        .select(
          '*, order_items(name_snapshot, quantity, unit_price_paise, '
          'brand, line_type, selections_jsonb)',
        )
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  } catch (_) {
    // Table may not exist or RLS blocks us — return empty rather than
    // surface an error to the activity screen.
    return const [];
  }
});

/// All published workshops at the venue, merged with this family's
/// registration state per workshop. Two lists baked in:
///   * upcoming  — every published workshop with scheduled_at >= now
///   * past      — the 10 most recent published workshops in the past
/// Each row carries:
///   * 'workshops'    → the workshop snapshot
///   * 'registration' → the family's registration row, or null if they
///                      weren't registered. Use this on the UI to show
///                      "Registered" / "Attended" / "Cancelled" pills.
/// Founder ask 2026-05-18: show every venue workshop here (not just
/// registered ones) so families browse what they've missed + see joined
/// ones highlighted in the same list.
final pastWorkshopsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  final client = Supabase.instance.client;
  final nowIso = DateTime.now().toUtc().toIso8601String();

  try {
    // Family's registrations — small list, used to enrich each workshop.
    final regsRaw = await client
        .from('workshop_registrations')
        .select('id, workshop_id, attended, cancelled_at, created_at')
        .eq('family_id', familyId);
    final regsByWorkshop = <String, Map<String, dynamic>>{
      for (final r in regsRaw as List)
        (r['workshop_id'] as String):
            Map<String, dynamic>.from(r as Map),
    };

    // All published upcoming workshops (this week, next week, …).
    final upcoming = await client
        .from('workshops')
        .select(
          'id, title, scheduled_at, cover_image_url, duration_minutes, '
          'primary_trait, status',
        )
        .eq('is_published', true)
        .gte('scheduled_at', nowIso)
        .order('scheduled_at', ascending: true);

    // Last 10 published past workshops.
    final past = await client
        .from('workshops')
        .select(
          'id, title, scheduled_at, cover_image_url, duration_minutes, '
          'primary_trait, status',
        )
        .eq('is_published', true)
        .lt('scheduled_at', nowIso)
        .order('scheduled_at', ascending: false)
        .limit(10);

    final result = <Map<String, dynamic>>[];
    for (final w in [...(upcoming as List), ...(past as List)]) {
      final ws = Map<String, dynamic>.from(w as Map);
      final reg = regsByWorkshop[ws['id'] as String];
      result.add({
        'workshops': ws,
        'registration': reg,
        // Compat keys for the existing UI:
        'attended': reg?['attended'] ?? false,
        'cancelled_at': reg?['cancelled_at'],
        'is_registered': reg != null && reg['cancelled_at'] == null,
      });
    }
    return result;
  } catch (_) {
    return const [];
  }
});

/// Birthday reservations for this family (upcoming + past).
final pastBirthdaysProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  try {
    final rows = await Supabase.instance.client
        .from('birthday_reservations')
        .select('*, children(name)')
        .eq('family_id', familyId)
        .order('slot_date', ascending: false)
        .limit(50);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  } catch (_) {
    return const [];
  }
});

/// Single session lookup for the past-session detail screen.
final pastSessionDetailProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, sessionId) async {
  final row = await Supabase.instance.client
      .from('sessions')
      .select('*, children(name)')
      .eq('id', sessionId)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});
