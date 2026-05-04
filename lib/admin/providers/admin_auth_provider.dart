import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Web auth state. Mirrors the staff auth provider shape so navigation +
/// redirect logic feels familiar across the three flavors.
final adminAuthStateProvider = StreamProvider<AuthState?>((ref) async* {
  final client = Supabase.instance.client;
  yield AuthState(
    AuthChangeEvent.initialSession,
    client.auth.currentSession,
  );
  yield* client.auth.onAuthStateChange;
});

/// True iff a Supabase session exists. Doesn't check `admin_users`
/// membership — that happens via [currentAdminUserProvider]. Login screen
/// uses this to show a spinner during sign-in.
final isAdminSignedInProvider = Provider<bool>((ref) {
  final state = ref.watch(adminAuthStateProvider).valueOrNull;
  return state?.session != null;
});

final adminAuthUserIdProvider = Provider<String?>((ref) {
  ref.watch(adminAuthStateProvider);
  return Supabase.instance.client.auth.currentUser?.id;
});

/// The signed-in admin's `admin_users` row. Returns null if the auth
/// session belongs to someone who isn't an active admin (e.g., a customer
/// session leaking in, or a deactivated admin). Router uses this to gate
/// every /admin/* route except /admin/login.
final currentAdminUserProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final userId = ref.watch(adminAuthUserIdProvider);
  if (userId == null) return null;

  final row = await Supabase.instance.client
      .from('admin_users')
      .select()
      .eq('auth_user_id', userId)
      .eq('is_active', true)
      .maybeSingle();
  return row == null ? null : Map<String, dynamic>.from(row);
});

/// Convenience: true iff the current admin has the super_admin role.
/// Drives the visibility of "Add admin" / "Change role" / "Deactivate
/// admin" controls in the Users section.
final isSuperAdminProvider = Provider<bool>((ref) {
  final admin = ref.watch(currentAdminUserProvider).valueOrNull;
  return admin?['role'] == 'super_admin';
});
