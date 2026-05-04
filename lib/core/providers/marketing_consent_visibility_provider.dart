import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';
import 'current_family_provider.dart';

const _dismissedKey = 'marketing_consent_dismissed_at';

/// Whether to show the marketing-consent card on Home. Visible iff:
///   - family has not opted in (`marketing_consent` IS NOT TRUE)
///   - card has not been dismissed locally (per-device, per spec)
///   - AND either the family is > 24h old OR has at least one completed
///     session (so we don't pester people in the first 60 seconds).
///
/// Returns false (hidden) while loading — no spinner-blink on cold start.
final marketingConsentVisibleProvider = FutureProvider<bool>((ref) async {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) return false;

  final family = await ref.watch(currentFamilyProvider.future);
  if (family == null) return false;
  if (family['marketing_consent'] == true) return false;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_dismissedKey) != null) return false;

  final createdAtRaw = family['created_at'] as String?;
  final isOldEnough = createdAtRaw != null &&
      DateTime.now()
              .toUtc()
              .difference(DateTime.parse(createdAtRaw).toUtc())
              .inHours >=
          24;

  if (isOldEnough) return true;

  // Otherwise need at least one completed session.
  final completedCount = await Supabase.instance.client
      .from('sessions')
      .select('id')
      .eq('family_id', familyId)
      .inFilter('status', ['completed', 'auto_closed']).limit(1);
  return (completedCount as List).isNotEmpty;
});

/// Persists the local-dismissal sentinel + invalidates the visibility
/// provider so the Home tab re-renders without the card.
Future<void> dismissMarketingConsent(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_dismissedKey, DateTime.now().toIso8601String());
  ref.invalidate(marketingConsentVisibleProvider);
}
