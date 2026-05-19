import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// True when the currently signed-in user is an active admin
/// (`admin_users` row with `is_active = true` for their auth.uid()).
///
/// Customer app uses this only for hiding/showing diagnostic surfaces
/// like the FCM debug screen entry. Regular customers will always get
/// `false` (RLS on `admin_users` doesn't allow them to see rows anyway,
/// but we use the `is_active_admin()` SECURITY DEFINER RPC for a
/// reliable answer regardless of RLS).
final isCurrentUserAdminProvider = FutureProvider<bool>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return false;
  try {
    final result = await Supabase.instance.client
        .rpc<bool>('is_active_admin');
    return result == true;
  } catch (_) {
    return false;
  }
});
