import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime stream of a single order row. `orders` is in supabase_realtime
/// (added in 0008), so status flips (pending → preparing → ready → served)
/// land on the device within a couple of seconds of the staff app updating.
final orderStreamProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, orderId) async* {
  final stream = Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('id', orderId)
      .limit(1);

  await for (final rows in stream) {
    yield rows.isEmpty ? null : rows.first;
  }
});

/// One-shot fetch of order_items for an order. Used by the tracking
/// screen line items list. order_items are immutable post-insert so a
/// stream isn't needed.
final orderItemsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, String>((ref, orderId) async {
  final rows = await Supabase.instance.client
      .from('order_items')
      .select()
      .eq('order_id', orderId)
      .order('created_at', ascending: true);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});
