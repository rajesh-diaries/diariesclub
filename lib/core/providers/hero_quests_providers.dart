import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Shared hero-quest providers used by the Home tab card and the
/// per-kid Adventure tab card. Quest progress is exposed as a realtime
/// stream so server-side trigger writes (auto quest completion when a
/// kid finishes a 2-hour session, etc.) reach the UI without a refresh.

/// Today's IST Monday in YYYY-MM-DD form. Quest schedules + progress
/// rows are keyed on this date.
final currentQuestWeekDateProvider = Provider<String>((ref) {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  final monday = DateTime.utc(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  return '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
});

/// The single hero_quest_weeks row scheduled for the current Monday,
/// or null if no quests are scheduled this week.
final questWeekProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final week = ref.watch(currentQuestWeekDateProvider);
  final row = await Supabase.instance.client
      .from('hero_quest_weeks')
      .select()
      .eq('week_start_date', week)
      .maybeSingle();
  return row;
});

/// Active quest definitions across all heroes.
final questDefinitionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('hero_quest_definitions')
      .select('id, hero, title, description, xp_bonus')
      .eq('is_active', true);
  return List<Map<String, dynamic>>.from(rows);
});

/// Family-scoped quest progress for the current week, as a realtime
/// stream. Trigger-driven inserts (quest auto-complete) flow back here
/// without manual invalidation, so the Home + Adventure cards reflect
/// completion the moment the trigger fires.
final questProgressForFamilyStreamProvider = StreamProvider.autoDispose<
    List<Map<String, dynamic>>>((ref) {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    return Stream.value(const <Map<String, dynamic>>[]);
  }
  final week = ref.watch(currentQuestWeekDateProvider);
  return Supabase.instance.client
      .from('hero_quest_progress')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .map((rows) {
        // Server-side filter on week_start_date isn't supported on
        // .stream() in this SDK version; client-side filter works fine
        // because the family typically has <10 progress rows per week.
        return rows
            .where((r) => r['week_start_date'] == week)
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      });
});
