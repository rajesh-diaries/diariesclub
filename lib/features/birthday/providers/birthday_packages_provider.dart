import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime list of active birthday packages. Switched from FutureProvider
/// to StreamProvider in migration 0051 — admin can now edit packages
/// (price, inclusions, photos) via the admin web's package_edit_screen,
/// and customers in active sessions should see those edits within ~2s
/// rather than only after an app refresh. The previous one-shot fetch
/// pre-dated the admin CRUD landing.
///
/// `birthday_packages` was added to the supabase_realtime publication in
/// migration 0051 to make this stream possible.
final birthdayPackagesProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('birthday_packages')
      .stream(primaryKey: ['id'])
      .eq('is_active', true)
      .order('sort_order', ascending: true);
  await for (final rows in stream) {
    yield rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
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
