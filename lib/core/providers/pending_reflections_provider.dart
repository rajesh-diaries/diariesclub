import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Streams sessions awaiting reflection within the reflection window
/// (default 24h, sourced from venue_config.reflection_window_hours).
///
/// A reflection card stays on the home tab for each session in this
/// list. The card disappears when:
///   * Parent completes the reflection (reflection_status flips to
///     'completed') — Realtime emits the new row, this list re-filters.
///   * The reflection_auto_split cron runs at the deadline and flips
///     reflection_status to 'auto_split' — same re-filter.
///
/// Returns sessions joined with their child name/photo for the UI card.
final pendingReflectionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  final client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> resolve(List<dynamic> rows) async {
    final now = DateTime.now().toUtc();
    final filtered = <Map<String, dynamic>>[];
    for (final r in rows) {
      final s = Map<String, dynamic>.from(r as Map);
      if (s['status'] != 'completed' && s['status'] != 'auto_closed') continue;
      if (s['reflection_status'] != 'pending') continue;
      final completedAtStr = s['completed_at'] as String?;
      if (completedAtStr == null) continue;
      final completedAt = DateTime.tryParse(completedAtStr);
      if (completedAt == null) continue;
      // Show for the reflection window — fall back to 24h if no deadline.
      final deadlineStr = s['reflection_deadline'] as String?;
      final deadline = deadlineStr != null
          ? DateTime.tryParse(deadlineStr) ??
              completedAt.add(const Duration(hours: 24))
          : completedAt.add(const Duration(hours: 24));
      if (now.isAfter(deadline)) continue;
      filtered.add(s);
    }

    if (filtered.isEmpty) return const [];

    // Join child rows so the card can show the name without a second
    // async call per item. Also drop sessions whose child has been
    // deleted (DPDP anonymise sets children.deleted_at) — reflect cards
    // for "Deleted Child" are noise that confuses parents who just
    // deleted their account or removed a kid.
    final childIds = filtered
        .map((s) => s['child_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final childRows = await client
        .from('children')
        .select('id, name, deleted_at')
        .inFilter('id', childIds);
    final byId = <String, Map<String, dynamic>>{
      for (final c in childRows as List)
        (c as Map)['id'] as String: Map<String, dynamic>.from(c),
    };

    filtered.removeWhere((s) {
      final cid = s['child_id'] as String?;
      if (cid == null) return false;
      final child = byId[cid];
      return child == null || child['deleted_at'] != null;
    });

    for (final s in filtered) {
      final cid = s['child_id'] as String?;
      if (cid != null) s['child'] = byId[cid];
    }
    // Newest completed first.
    filtered.sort((a, b) {
      final aa = DateTime.tryParse(a['completed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bb = DateTime.tryParse(b['completed_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bb.compareTo(aa);
    });
    return filtered;
  }

  // One-shot initial read so the home tab renders even if Realtime errors.
  final initial = await client
      .from('sessions')
      .select()
      .eq('family_id', familyId)
      .order('completed_at', ascending: false)
      .limit(20);
  yield await resolve(initial as List);

  try {
    final stream = client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('completed_at', ascending: false)
        .limit(20);
    await for (final rows in stream) {
      yield await resolve(rows);
    }
  } catch (e) {
    // ignore: avoid_print
    print('[pending_reflections_provider] realtime error (non-fatal): $e');
  }
});
