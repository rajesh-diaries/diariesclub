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
  if (rows.isEmpty) {
    // ignore: avoid_print
    print('[BUG-039] _classify: rows empty → Idle');
    return const HomeStateIdle();
  }

  final now = DateTime.now();
  for (final r in rows) {
    final status = r['status'] as String?;
    if (status != 'active' && status != 'grace') continue;

    final expiresAtStr = r['expires_at'] as String?;
    if (expiresAtStr != null) {
      try {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (now.difference(expiresAt).inHours > 2) {
          continue; // stuck-session escape (BUG-038)
        }
      } catch (_) { /* fall through */ }
    }

    // ignore: avoid_print
    print('[BUG-039] _classify: returning InSession sessionId=${r['id']} '
        'status=$status');
    return HomeStateInSession(r);
  }

  // BUG-039 — PostSession branch RE-ENABLED. The branch was disabled in
  // commit 3182553 because PostSessionHomeView was rendering blank; with
  // it disabled, the reflection prompt never surfaces and Adventure tab's
  // children.total_xp gate stays at 0 forever. Re-enabling so the
  // diagnostic instrumentation can capture which downstream widget /
  // provider is the actual source of the blank render.
  for (final r in rows) {
    final status = r['status'] as String?;
    if (status != 'completed' && status != 'auto_closed') continue;

    final reflection = r['reflection_status'] as String?;
    if (reflection != 'pending') continue;

    final completedAt = r['completed_at'] as String?;
    if (completedAt == null) continue;

    try {
      final closedAt = DateTime.parse(completedAt);
      if (DateTime.now().toUtc().difference(closedAt.toUtc()).inMinutes > 30) {
        continue; // older than 30 min, not in post-session window
      }
    } catch (_) { continue; }

    // ignore: avoid_print
    print('[BUG-039] _classify: returning PostSession sessionId=${r['id']} '
        'status=$status reflection_status=$reflection '
        'completed_at=$completedAt total_xp_earned=${r['total_xp_earned']} '
        'reflection_deadline=${r['reflection_deadline']}');
    return HomeStatePostSession(r);
  }

  // ignore: avoid_print
  print('[BUG-039] _classify: no matching row → Idle');
  return const HomeStateIdle();
}
