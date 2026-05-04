import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tablet auth state. The staff app signs in once per device with a
/// long-lived email/password (the tablet user, e.g.
/// `tablet-kondapur-001@diariesclub.local`). Per-staff identity is then
/// established per-action via the PIN sheet.
final tabletAuthStateProvider = StreamProvider<AuthState?>((ref) async* {
  final client = Supabase.instance.client;
  yield AuthState(
    AuthChangeEvent.initialSession,
    client.auth.currentSession,
  );
  yield* client.auth.onAuthStateChange;
});

/// True iff a tablet auth session exists. Staff router uses this to
/// decide login vs home redirect.
final isTabletSignedInProvider = Provider<bool>((ref) {
  final state = ref.watch(tabletAuthStateProvider).valueOrNull;
  return state?.session != null;
});

/// The tablet's auth.uid() — pulled from the active Supabase session.
/// Used by the providers below to filter to "this venue".
final tabletAuthUserIdProvider = Provider<String?>((ref) {
  ref.watch(tabletAuthStateProvider);
  return Supabase.instance.client.auth.currentUser?.id;
});

/// Look up the tablet's tablet_devices row → resolves the venue id.
/// Returns null if the tablet is signed in but its device row is
/// inactive or missing (revoked from admin web).
final currentTabletDeviceProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(tabletAuthUserIdProvider);
  if (userId == null) return null;

  final row = await Supabase.instance.client
      .from('tablet_devices')
      .select()
      .eq('auth_user_id', userId)
      .eq('is_active', true)
      .maybeSingle();
  return row == null ? null : Map<String, dynamic>.from(row);
});

/// The tablet's venue id, or null when no active tablet device row.
/// Most staff RPCs derive venue server-side from auth.uid() — this is
/// the client-side mirror for stat queries / filters.
final currentTabletVenueIdProvider = Provider<String?>((ref) {
  final device = ref.watch(currentTabletDeviceProvider).valueOrNull;
  return device?['venue_id'] as String?;
});
