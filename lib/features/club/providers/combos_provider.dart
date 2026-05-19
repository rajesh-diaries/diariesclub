import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime list of active combos for the venue. `combos` is in the
/// supabase_realtime publication (added in 0011) so admin-toggled combos
/// surface within seconds.
final combosProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final client = Supabase.instance.client;

  // One-shot initial read so the Combos tab renders even if Realtime
  // later errors (iOS post-login channelError 1002).
  final initialRows = await client
      .from('combos')
      .select()
      .order('sort_order', ascending: true);
  yield (initialRows as List)
      .where((r) => (r as Map)['is_active'] == true)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  // Best-effort Realtime — swallow errors to keep the initial data visible.
  try {
    final stream = client
        .from('combos')
        .stream(primaryKey: ['id'])
        .order('sort_order', ascending: true);

    await for (final rows in stream) {
      yield rows.where((r) => r['is_active'] == true).toList();
    }
  } catch (e) {
    // ignore: avoid_print
    print('[combos_provider] realtime error (non-fatal): $e');
  }
});

/// One-shot lookup for a combo's referenced menu items. Used by the cart
/// sheet to show the included items when a combo is in the bag.
final comboMenuItemsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, List<String>>((ref, ids) async {
  if (ids.isEmpty) return const [];
  final rows = await Supabase.instance.client
      .from('menu_items_with_brand')
      .select()
      .inFilter('id', ids);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});
