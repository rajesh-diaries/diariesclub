import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// Filter pill choice for the workshops tab.
enum WorkshopFilter { all, thisWeek, nextWeek, past }

extension WorkshopFilterX on WorkshopFilter {
  String get label => switch (this) {
        WorkshopFilter.all => 'All',
        WorkshopFilter.thisWeek => 'This week',
        WorkshopFilter.nextWeek => 'Next week',
        WorkshopFilter.past => 'Past',
      };
}

final workshopFilterProvider =
    StateProvider<WorkshopFilter>((_) => WorkshopFilter.all);

/// Realtime list of workshops, with client-side filter applied per the
/// pill selection. Spots-remaining updates land via Realtime (workshops
/// table is in supabase_realtime per 0011).
final workshopsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final filter = ref.watch(workshopFilterProvider);
  final stream = Supabase.instance.client
      .from('workshops')
      .stream(primaryKey: ['id'])
      .order('scheduled_at', ascending: true);

  await for (final rows in stream) {
    yield _applyFilter(rows, filter);
  }
});

List<Map<String, dynamic>> _applyFilter(
  List<Map<String, dynamic>> rows,
  WorkshopFilter filter,
) {
  final now = DateTime.now();
  final endOfWeek = _endOfWeek(now);
  final endOfNextWeek = endOfWeek.add(const Duration(days: 7));

  return rows.where((r) {
    final scheduled = DateTime.tryParse(r['scheduled_at'] as String? ?? '');
    if (scheduled == null) return false;
    switch (filter) {
      case WorkshopFilter.all:
        return scheduled.isAfter(now) ||
            scheduled.isAtSameMomentAs(now);
      case WorkshopFilter.thisWeek:
        return scheduled.isAfter(now) && !scheduled.isAfter(endOfWeek);
      case WorkshopFilter.nextWeek:
        return scheduled.isAfter(endOfWeek) &&
            !scheduled.isAfter(endOfNextWeek);
      case WorkshopFilter.past:
        return scheduled.isBefore(now);
    }
  }).toList();
}

DateTime _endOfWeek(DateTime t) {
  // Sunday end-of-day (local). Indian week is Sun-start by convention but
  // for "this week" / "next week" filters, end-of-Sunday is universal.
  final daysToSunday = (DateTime.sunday - t.weekday + 7) % 7;
  return DateTime(t.year, t.month, t.day, 23, 59, 59)
      .add(Duration(days: daysToSunday));
}

/// Single workshop lookup by id (workshop detail screen).
final workshopByIdProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, id) async {
  final row = await Supabase.instance.client
      .from('workshops')
      .select()
      .eq('id', id)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});

/// Live workshop registrations for the current family. Used so the
/// workshop detail screen can show "You're already registered" instead
/// of the Register CTA.
final myWorkshopRegistrationsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }
  final stream = Supabase.instance.client
      .from('workshop_registrations')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId);
  await for (final rows in stream) {
    yield rows.where((r) => r['cancelled_at'] == null).toList();
  }
});
