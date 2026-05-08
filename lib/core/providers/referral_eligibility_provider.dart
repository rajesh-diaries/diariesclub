import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'current_family_provider.dart';

/// Whether the customer is eligible to redeem a referral code.
/// True iff they have NO referrer attached AND have not yet completed a
/// session (the moment a session completes, the conversion fires and
/// the entry point should disappear from the UI).
final referralRedeemEligibleProvider = FutureProvider<bool>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return false;

  final family = await ref.watch(currentFamilyProvider.future);
  if (family == null) return false;
  if (family['referrer_family_id'] != null) return false;

  final completed = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('family_id', familyId)
      .inFilter('status', ['completed', 'auto_closed']).limit(1);
  return (completed as List).isEmpty;
});
