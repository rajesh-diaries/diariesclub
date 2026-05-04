import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-shot fetch of all active birthday packages for the venue. Packages
/// don't change at runtime — admin tweaks would require a venue_config
/// edit + app refresh. No Realtime stream.
final birthdayPackagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('birthday_packages')
      .select()
      .eq('is_active', true)
      .order('sort_order', ascending: true);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
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
