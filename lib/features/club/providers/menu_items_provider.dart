import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime list of menu items for one brand. Reads from the
/// `menu_items_with_brand` view (added in 0012) so a single `.stream()`
/// gets us brand + price + availability without joins.
///
/// `menu_items` is in the supabase_realtime publication (added in 0011)
/// — sold-out flips propagate within ~2s.
final menuItemsByBrandProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, brand) async* {
  final stream = Supabase.instance.client
      .from('menu_items')
      .stream(primaryKey: ['id'])
      .order('sort_order', ascending: true);

  // We can't filter by brand on the stream directly (brand lives on the
  // joined `menus` table). Pull the menu_id → brand mapping once at
  // subscription time and filter client-side. Brand changes are rare —
  // a missed update on rebrand is fine.
  final brandMap = await _menuIdToBrand();

  await for (final rows in stream) {
    yield rows
        .where((r) => brandMap[r['menu_id']] == brand)
        .toList();
  }
});

Future<Map<String, String>> _menuIdToBrand() async {
  final rows = await Supabase.instance.client.from('menus').select('id, brand');
  final out = <String, String>{};
  for (final r in rows as List) {
    final m = r as Map;
    out[m['id'] as String] = m['brand'] as String;
  }
  return out;
}

/// Filter pill state for the brand menu tab. Local UI state, reset per
/// tab open (ergonomic — opening Coffee shouldn't keep "bites" filter
/// from the previous visit).
class MenuCategoryFilter {
  final String brand;
  final String? category; // null = "All"
  const MenuCategoryFilter({required this.brand, this.category});
}

final menuCategoryFilterProvider =
    StateProvider.family<String?, String>((_, __) => null);
