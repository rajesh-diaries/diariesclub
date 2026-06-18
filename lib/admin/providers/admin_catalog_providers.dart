import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime stream of managed categories for a specific menu, ordered by
/// [sort_order]. Used to populate the category dropdown in the menu item
/// edit screen.
final menuCategoriesProvider = StreamProvider.family<
    List<Map<String, dynamic>>, String>((ref, menuId) {
  return Supabase.instance.client
      .from('menu_categories')
      .stream(primaryKey: ['id'])
      .eq('menu_id', menuId)
      .order('sort_order');
});
