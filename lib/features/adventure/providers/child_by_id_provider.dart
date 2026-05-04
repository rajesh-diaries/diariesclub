import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/family_children_provider.dart';

/// Picks a single child out of the live `familyChildrenProvider` stream.
/// Lets multiple sub-widgets watch the same child without each opening
/// its own subscription. Returns `null` if the id no longer matches a
/// live row (e.g. the child was soft-deleted while the dashboard was
/// open).
final childByIdProvider =
    Provider.family<Map<String, dynamic>?, String>((ref, childId) {
  final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
  for (final c in children) {
    if (c['id'] == childId) return c;
  }
  return null;
});
