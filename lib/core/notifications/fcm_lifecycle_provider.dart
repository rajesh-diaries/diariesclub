import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import 'fcm_setup.dart';

/// Bridges Riverpod auth state to FCM lifecycle:
///   - signed in → request permission + persist token
///   - signed out → clear token from families row
///
/// Watch this once from AppRoot (or any always-mounted widget) and
/// the side effects fire on every auth transition.
final fcmLifecycleProvider = Provider<void>((ref) {
  String? lastFamilyId;
  ref.listen<String?>(currentFamilyIdProvider, (prev, next) {
    if (prev == next) return;
    if (next != null && next != lastFamilyId) {
      lastFamilyId = next;
      // ignore: discarded_futures
      FcmSetup.onSignIn(next);
    } else if (next == null && prev != null) {
      // ignore: discarded_futures
      FcmSetup.onSignOut(prev);
      lastFamilyId = null;
    }
  }, fireImmediately: true);
});

/// Pull + clear the pending FCM deep link captured on cold-start tap.
/// Returns null if no pending link (or already consumed).
String? consumePendingFcmDeepLink() {
  final link = pendingFcmDeepLink;
  pendingFcmDeepLink = null;
  return link;
}
