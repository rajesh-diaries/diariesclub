import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';

/// Set of package IDs the current family has hearted on the birthday
/// packages screen. Backed by saved_birthday_packages; RLS scopes rows
/// to the caller's family.
final savedBirthdayPackageIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return const <String>{};
  final rows = await Supabase.instance.client
      .from('saved_birthday_packages')
      .select('package_id')
      .eq('family_id', familyId);
  return {
    for (final r in (rows as List))
      (r as Map)['package_id'] as String,
  };
});

/// Action: toggle a package's saved state for the current family.
/// Returns the new state (true = saved, false = unsaved). Invalidates
/// the set provider so any card watching it reflows.
///
/// Accepts [WidgetRef] because the callers are widgets — both `Ref` and
/// `WidgetRef` expose `read` + `invalidate`, but the static types are
/// distinct in Riverpod 2.x and we'd hit a compile-time mismatch.
Future<bool> toggleBirthdayPackageSaved(
  WidgetRef ref,
  String packageId,
) async {
  final familyId = ref.read(currentFamilyIdProvider);
  if (familyId == null) return false;

  final client = Supabase.instance.client;
  final existing = await client
      .from('saved_birthday_packages')
      .select('id')
      .eq('family_id', familyId)
      .eq('package_id', packageId)
      .maybeSingle();

  final bool isNowSaved;
  if (existing == null) {
    await client.from('saved_birthday_packages').insert({
      'family_id': familyId,
      'package_id': packageId,
    });
    isNowSaved = true;
  } else {
    await client
        .from('saved_birthday_packages')
        .delete()
        .eq('family_id', familyId)
        .eq('package_id', packageId);
    isNowSaved = false;
  }
  ref.invalidate(savedBirthdayPackageIdsProvider);
  return isNowSaved;
}
