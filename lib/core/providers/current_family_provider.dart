import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// The current signed-in user's `families` row, or null if onboarding
/// hasn't progressed past `family_create` yet (auth user exists but no
/// family row).
///
/// Re-evaluates whenever the auth user changes (sign-in / sign-out) and
/// can be invalidated by callers after onboarding mutations.
final currentFamilyProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return null;

  // 8s timeout — this is read at splash to decide onboarding vs home
  // routing. Hanging here = blank screen forever. Surface as null so the
  // splash error path activates and the user gets a retry option.
  final row = await Supabase.instance.client
      .from('families')
      .select()
      .eq('id', familyId)
      .maybeSingle()
      .timeout(const Duration(seconds: 8));

  return row;
});
