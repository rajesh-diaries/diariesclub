import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin-configurable Play Pass plans, read from the `play_pass_plans` table.
/// RLS returns only active plans to customers. Replaces the previously hardcoded
/// list in play_pass_purchase_sheet.dart — the `play_pass_purchase` RPC reads the
/// same table server-side, so display and charge stay in sync.
///
/// Shape returned matches what the purchase sheet expects:
/// { 'type', 'total', 'price_paise', 'days', 'label', 'tag' }.
final playPassPlansProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('play_pass_plans')
      .select('pass_type,total_passes,validity_days,price_paise,label,tag,sort_order')
      .eq('is_active', true)
      .order('sort_order');

  return List<Map<String, dynamic>>.from(rows)
      .map((r) => <String, dynamic>{
            'type': r['pass_type'],
            'total': r['total_passes'],
            'price_paise': r['price_paise'],
            'days': r['validity_days'],
            'label': r['label'],
            'tag': (r['tag'] as String?) ?? '',
          })
      .toList();
});
