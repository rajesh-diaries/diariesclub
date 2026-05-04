import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/ist_dates.dart';
import 'auth_provider.dart';

/// One upcoming birthday, with optional reservation status. The birthday
/// card on Home morphs based on whether `reservation` is non-null.
class UpcomingBirthday {
  final Map<String, dynamic> child;
  final int daysUntil;
  final Map<String, dynamic>? reservation;

  const UpcomingBirthday({
    required this.child,
    required this.daysUntil,
    this.reservation,
  });
}

/// All children whose next birthday is within the 90-day window. Empty list
/// if no children, or all are further out. Re-evaluated when the auth user
/// changes; refresh manually via `ref.invalidate(upcomingBirthdaysProvider)`
/// after onboarding or DOB edits.
final upcomingBirthdaysProvider =
    FutureProvider<List<UpcomingBirthday>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const [];

  final children = await Supabase.instance.client
      .from('children')
      .select()
      .eq('family_id', familyId);

  final today = IstDates.istDate(DateTime.now().toUtc());
  final results = <UpcomingBirthday>[];

  for (final c in children as List) {
    final child = (c as Map).cast<String, dynamic>();
    final dobRaw = child['date_of_birth'] as String?;
    if (dobRaw == null) continue;

    final dob = DateTime.parse(dobRaw);

    // Compute "next birthday" — this year's, or next year's if it already
    // passed (with a +1-day grace so today counts as 0 days, not 364).
    var nextBday = DateTime(today.year, dob.month, dob.day);
    if (nextBday.isBefore(DateTime(today.year, today.month, today.day))) {
      nextBday = DateTime(today.year + 1, dob.month, dob.day);
    }
    final daysUntil = nextBday
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;

    if (daysUntil < 0 || daysUntil > 90) continue;

    final reservation = await Supabase.instance.client
        .from('birthday_reservations')
        .select()
        .eq('child_id', child['id'] as String)
        .inFilter('status', ['reserved', 'deposit_paid', 'confirmed'])
        .maybeSingle();

    results.add(UpcomingBirthday(
      child: child,
      daysUntil: daysUntil,
      reservation: reservation == null
          ? null
          : Map<String, dynamic>.from(reservation),
    ));
  }

  return results;
});

/// True if any child has a birthday within the next 7 days. Used by Home
/// to decide whether to compact the active-session timer.
final birthdayWithinWeekProvider = Provider<bool>((ref) {
  final list = ref.watch(upcomingBirthdaysProvider).valueOrNull ?? const [];
  return list.any((b) => b.daysUntil <= 7);
});
