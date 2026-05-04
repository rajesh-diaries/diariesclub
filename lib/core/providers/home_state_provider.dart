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
    yield _classify(rows);
  }
});

HomeState _classify(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return const HomeStateIdle();

  // Open session: anything still in 'active' or 'grace' status. The visual
  // active/grace switch happens in the view.
  for (final r in rows) {
    final status = r['status'] as String?;
    if (status == 'active' || status == 'grace') {
      return HomeStateInSession(r);
    }
  }

  // Most recent completed/auto_closed session, if it's recent + reflection
  // hasn't been done.
  for (final r in rows) {
    final status = r['status'] as String?;
    if (status != 'completed' && status != 'auto_closed') continue;

    final reflection = r['reflection_status'] as String?;
    if (reflection != 'pending') continue;

    final completedAt = r['completed_at'] as String?;
    if (completedAt == null) continue;

    final closedAt = DateTime.parse(completedAt);
    if (DateTime.now().toUtc().difference(closedAt.toUtc()).inMinutes <= 30) {
      return HomeStatePostSession(r);
    }
  }

  return const HomeStateIdle();
}
