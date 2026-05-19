import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// List of active birthday packages. Reverted from StreamProvider back
/// to FutureProvider — the realtime subscription was timing out on a
/// repeat visit after a completed birthday flow (E2E, 2026-05-18) with
/// `RealtimeSubscribeException: timedOut`. Packages change rarely (admin
/// edits price/inclusions a few times a week, not a few times a second),
/// so a one-shot REST fetch is more reliable and removes a whole class
/// of realtime-channel failures. Pull-to-refresh refetches.
final birthdayPackagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('birthday_packages')
      .select()
      .eq('is_active', true)
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows)
      .where((r) => (r['category'] as String? ?? 'birthday') == 'birthday')
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
});

/// Single package by id (package detail screen).
final birthdayPackageByIdProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, id) async {
  final row = await Supabase.instance.client
      .from('birthday_packages')
      .select()
      .eq('id', id)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});
