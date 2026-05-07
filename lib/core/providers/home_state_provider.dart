import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// One of four high-level Home tab states. Active vs grace is a *visual*
/// distinction computed at render time (compare `session.expires_at` to
/// server time) — the DB only carries 'active' / 'completed' / 'auto_closed'
/// / 'void' for v1 (no server-side cron flips active → grace). So this
/// provider returns `inSession` for any open session and lets the view
/// decide whether to render the active or grace layout.
sealed class HomeState {
  const HomeState();
}

class HomeStateIdle extends HomeState {
  const HomeStateIdle();
}

class HomeStateInSession extends HomeState {
  final Map<String, dynamic> session;
  const HomeStateInSession(this.session);
}

class HomeStatePostSession extends HomeState {
  final Map<String, dynamic> session;
  const HomeStatePostSession(this.session);
}

/// Subscribes to the family's recent sessions and derives the Home tab
/// state. Re-emits on any change to the relevant rows. (The active → grace
/// visual flip is time-based, not DB-based — see comment above.)
///
/// `postSession` is recognised when the latest completed session is < 30
/// minutes old AND its reflection is still pending. After 30 min the recap
/// just becomes a regular notification entry.
final homeStateProvider = StreamProvider<HomeState>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const HomeStateIdle();
    return;
  }

  final stream = Supabase.instance.client
      .from('sessions')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(5);

  await for (final rows in stream) {
    final classified = _classify(rows);
    // ignore: avoid_print
    print('[BUG-038] homeStateProvider stream emitted ${rows.length} rows '
        '→ ${classified.runtimeType}');
    yield classified;
  }
});

HomeState _classify(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return const HomeStateIdle();

  // Open session: status must be 'active' or 'grace' AND expires_at must
  // not be hours in the past. The expires_at sanity check defends against
  // stale realtime state (e.g. Chrome tab backgrounded while staff/server
  // closed the session) — without it, the customer can be trapped on a
  // phantom overrun timer that no UI gesture clears. 2 hours covers the
  // configured grace + force-close max with margin.
  final now = DateTime.now();
  for (final r in rows) {
    final status = r['status'] as String?;
    if (status != 'active' && status != 'grace') continue;

    final expiresAtStr = r['expires_at'] as String?;
    if (expiresAtStr != null) {
      try {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (now.difference(expiresAt).inHours > 2) {
          // Session is stuck. Skip — let the customer see Idle so they're
          // not trapped. Server reconciliation will eventually flip status.
          continue;
        }
      } catch (_) {
        // If we can't parse expires_at, fall through and trust the status.
      }
    }

    return HomeStateInSession(r);
  }

  // BUG-038 v1 fallback: PostSession branch disabled. PostSessionHomeView
  // was rendering blank after `session_complete` (root cause not pinpointed
  // in v1; tracked as v1.1 follow-up). For v1 the customer lands on Idle
  // immediately after wrap-up; recap reachable via notification or
  // /profile/sessions list.
  return const HomeStateIdle();
}
