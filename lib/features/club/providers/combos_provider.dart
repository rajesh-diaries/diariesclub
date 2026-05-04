import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime list of active combos for the venue. `combos` is in the
/// supabase_realtime publication (added in 0011) so admin-toggled combos
/// surface within seconds.
final combosProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final stream = Supabase.instance.client
      .from('combos')
      .stream(primaryKey: ['id'])
      .order('sort_order', ascending: true);

  await for (final rows in stream) {
    yield rows.where((r) => r['is_active'] == true).toList();
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
