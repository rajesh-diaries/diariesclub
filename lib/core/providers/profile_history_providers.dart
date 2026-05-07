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
      .select('*, children(name, photo_url)')
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(50);

  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});

/// Past café/FIT/combo orders. Empty until Session 7 introduces
/// order placement, but the query is correct so the screen lights up
/// automatically once orders start landing.
final pastOrdersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  // The orders table already exists from migration 0001 — RLS scopes by
  // family. Empty result before Session 7 ships placement.
  try {
    final rows = await Supabase.instance.client
        .from('orders')
        .select()
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

/// Workshops the family has registered for.
final pastWorkshopsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  try {
    final rows = await Supabase.instance.client
        .from('workshop_registrations')
        .select(
          '*, workshops(id, title, scheduled_at, cover_image_url, '
          'duration_minutes, primary_trait)',
        )
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
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
      .select('*, children(name, photo_url)')
      .eq('id', sessionId)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});
