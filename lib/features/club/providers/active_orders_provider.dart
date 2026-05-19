import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// Realtime stream of orders that are still "in flight" for the current
/// family. Powers the live-orders card on home, mirroring the same
/// pipeline the kitchen team sees: placed → preparing → ready → served.
///
/// Served orders stay visible for a short victory-lap window (30 min)
/// so the parent gets a humble "enjoy / thank you" moment before the
/// row drops off the home screen.
///
/// Filters in Dart rather than at the query level because Supabase
/// Realtime streams only support a single .eq filter at a time; we use
/// it for family_id and post-filter by status + age.
final activeOrdersProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }
  final stream = Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(20);

  final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 12));
  final servedCutoff =
      DateTime.now().toUtc().subtract(const Duration(minutes: 30));

  await for (final rows in stream) {
    final filtered = <Map<String, dynamic>>[];
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r);
      final status = m['status'] as String?;
      if (status != 'pending' &&
          status != 'preparing' &&
          status != 'ready' &&
          status != 'served') continue;
      final createdRaw = m['created_at'] as String?;
      final created = createdRaw != null
          ? DateTime.tryParse(createdRaw)?.toUtc()
          : null;
      if (created != null && created.isBefore(cutoff)) continue;
      // For served orders, only keep them visible for the victory-lap
      // window so the home screen doesn't get cluttered with hours of
      // historical thank-you banners.
      if (status == 'served' &&
          created != null &&
          created.isBefore(servedCutoff)) {
        continue;
      }
      filtered.add(m);
    }
    yield filtered;
  }
});

/// One-shot fetch of all order_items belonging to the given order_ids.
/// Used by the live-orders card to render line items inline so the
/// parent sees what each in-flight order contains without tapping in.
final activeOrderItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, List<String>>((ref, orderIds) async {
  if (orderIds.isEmpty) return const [];
  final rows = await Supabase.instance.client
      .from('order_items')
      .select()
      .inFilter('order_id', orderIds)
      .order('created_at', ascending: true);
  return (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
});
