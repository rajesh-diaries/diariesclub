import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// Whether to show the "While [child] plays..." card on Home during an
/// active session. Visible iff:
///   - Family has at least 2 completed sessions (2nd visit or later)
///   - Caller has not dismissed the prompt for *this* session_id
///
/// Dismissal is per-session (key `wyw_dismissed_<session_id>`), so the
/// nudge reappears on the family's next session.
final shouldShowWhileYouWaitProvider =
    FutureProvider.family<bool, String?>((ref, sessionId) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null || sessionId == null) return false;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('wyw_dismissed_$sessionId') == true) return false;

  // Use head+count so the result is an exact integer rather than a
  // .limit(2) probe that's brittle if PostgREST pagination ever
  // changes. We just need "did the family complete >= 2 sessions?".
  final res = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('family_id', familyId)
      .inFilter('status', ['completed', 'auto_closed']).count(
          CountOption.exact);
  return res.count >= 2;
});

/// Persists the per-session dismissal. The active-session card on Home
/// passes its session_id and calls this on tap.
Future<void> dismissWhileYouWait(String sessionId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('wyw_dismissed_$sessionId', true);
}
