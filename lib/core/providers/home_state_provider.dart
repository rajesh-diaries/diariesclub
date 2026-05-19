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

  final client = Supabase.instance.client;

  // One-shot read so the screen renders even if Realtime later fails. On
  // iOS prod builds we've seen the Realtime subscribe time out on the first
  // post-login attempt (JWT propagation race); the one-shot uses the
  // already-attached PostgREST client and reliably succeeds.
  final initialRows = await client
      .from('sessions')
      .select()
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(5);
  yield _classify(
    (initialRows as List).cast<Map<String, dynamic>>(),
  );

  // Best-effort Realtime subscription for live updates. If it errors
  // (timeout, transport drop), keep the last emitted state instead of
  // bubbling the error up to the home screen as E-HOME.
  try {
    final stream = client
        .from('sessions')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .order('created_at', ascending: false)
        .limit(5);

    await for (final rows in stream) {
      yield _classify(rows);
    }
  } catch (e) {
    // ignore: avoid_print
    print('[home_state_provider] realtime stream error (non-fatal): $e');
  }
});

HomeState _classify(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return const HomeStateIdle();

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
    return HomeStateInSession(r);
  }

  // Pending reflections are now surfaced by `PendingReflectionsSection`
  // (renders one card per pending reflection inside both Idle and
  // MultiSession home views, for the full 24h reflection window). The
  // top-level home state is just idle vs in-session.
  return const HomeStateIdle();
}
