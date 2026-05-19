import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Count of completed birthday reservations at the venue — used as a
/// "Hosted N parties so far" social-proof banner at the top of the
/// packages screen. Refetched on every screen build (autoDispose) so
/// it stays close-to-live as bookings complete.
final completedBirthdayCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final res = await Supabase.instance.client
      .from('birthday_reservations')
      .select('id')
      .eq('status', 'completed')
      .count(CountOption.exact);
  return res.count;
});
