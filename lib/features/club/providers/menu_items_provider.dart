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
  final client = Supabase.instance.client;

  // Brand mapping is needed for both the initial read and the stream;
  // pull once.
  final brandMap = await _menuIdToBrand();

  // One-shot initial read so the Club tab renders even if Realtime later
  // errors (iOS post-login channelError 1002). PostgREST is reliable;
  // Realtime is the flaky path.
  final initialRows = await client
      .from('menu_items')
      .select()
      .order('sort_order', ascending: true);
  yield (initialRows as List)
      .where((r) => brandMap[(r as Map)['menu_id']] == brand)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  // Best-effort Realtime subscription for live sold-out flips. If it
  // errors, swallow — the one-shot data above keeps the menu visible.
  try {
    final stream = client
        .from('menu_items')
        .stream(primaryKey: ['id'])
        .order('sort_order', ascending: true);

    await for (final rows in stream) {
      yield rows
          .where((r) => brandMap[r['menu_id']] == brand)
          .toList();
    }
  } catch (e) {
    // ignore: avoid_print
    print('[menu_items_provider] realtime error (non-fatal): $e');
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
