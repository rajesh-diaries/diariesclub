import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams Supabase auth state so the router can react to sign-in / sign-out.
/// Real auth flow (OTP) is built in Session 4.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Current authenticated user's UUID, or null if signed out.
/// families.id == auth.users.id, so this is the family_id.
final currentFamilyIdProvider = Provider<String?>((ref) {
  // Listen so dependents rebuild on sign-in/out.
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser?.id;
});

/// True if the user is signed in.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentFamilyIdProvider) != null;
});
