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

  final row = await Supabase.instance.client
      .from('families')
      .select()
      .eq('id', familyId)
      .maybeSingle();

  return row;
});
