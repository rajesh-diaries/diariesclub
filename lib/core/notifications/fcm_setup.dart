import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';
import 'notification_channels.dart';

/// Top-level reference so any screen (e.g., the FCM debug page) can read
/// the current token without round-tripping Firebase. Set during
/// FcmSetup.initialize and refreshed via onTokenRefresh.
String? currentFcmToken;

/// Pending deep link from a notification tap. Reactive so resumed-from-
/// background and foreground-tap events route correctly without waiting
/// for home_screen.initState to fire again.
///
///   * Cold start (app killed)  → set in initialize() from getInitialMessage
///   * Background resume tap    → set in _onMessageOpenedApp
///   * Foreground tap on banner → set in _onLocalTap
///
/// Home screen attaches a listener and pushes whenever this changes.
final ValueNotifier<String?> pendingFcmDeepLinkNotifier =
    ValueNotifier<String?>(null);

/// Backwards-compat shim used by the FCM debug screen and any callers
/// that just want a one-shot read.
String? get pendingFcmDeepLink => pendingFcmDeepLinkNotifier.value;
set pendingFcmDeepLink(String? v) => pendingFcmDeepLinkNotifier.value = v;

/// Background message handler must be a top-level / static function
/// annotated with @pragma so the Dart entry-point survives AOT tree-shaking.
/// Runs in a separate isolate when the app is fully terminated; persistent
/// state (Riverpod, Supabase) is unavailable here. We only use it to log
/// for now — the actual notification rendering is handled by the system
/// when FCM payload includes a `notification` block.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  dev.log(
    'FCM background message: ${message.messageId}',
    name: 'fcm',
  );
}

/// Customer-app FCM lifecycle. iOS support is partial — token request
/// works on simulator without APNs but real delivery needs an APNs auth
/// key uploaded to Firebase + push entitlement on Runner.entitlements.
/// Search for `TODO(ios)` to find the gaps.
class FcmSetup {
  FcmSetup._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Whether FCM has been initialised this app run. Guards against
  /// double-init when the auth state stream re-fires.
  static bool _initialised = false;

  /// Whether the onTokenRefresh listener has been wired this run.
  /// Critical for iOS: the listener must be attached BEFORE the first
  /// getToken() call so a token that arrives after APNs registers (which
  /// can take several seconds) still gets persisted.
  static bool _tokenListenerWired = false;

  /// One-shot init called from bootstrap when:
  ///   1) the flavor is the customer app (caller checks; this class is
  ///      not invoked from staff/admin flavors)
  ///   2) Firebase.initializeApp() has succeeded
  ///
  /// Permission prompt is deferred to onSignIn() so first launch (no
  /// account) doesn't surface a system dialog before the value-prop
  /// screen explains why.
  static Future<void> initialize() async {
    if (_initialised) return;

    try {
      // Firebase.initializeApp may already have been called in bootstrap;
      // .apps check makes this safe to call again.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Background handler must be registered before any other FCM call.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // iOS: explicitly OPT OUT of FCM's auto-present in foreground.
      // We render every foreground push via _onForegroundMessage →
      // flutter_local_notifications instead. The previous setup (alert:
      // true) double-rendered some pushes and silently dropped others
      // on iOS 26 — letting iOS try to merge FCM's `notification` block
      // into `aps.alert` was the inconsistent bit. Now there's exactly
      // one banner path: data arrives, we explicitly call
      // _localNotifications.show(). suppress_foreground from the server
      // is still honoured for the few in-context types.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      // Local notifications plugin — used to render banners in the
      // foreground for both Android and iOS. The plugin has its own
      // iOS permission state (FCM's permission grant doesn't carry over)
      // so we must request alert/badge/sound here too; iOS dedupes the
      // prompt against the FCM grant, so the user doesn't see a second
      // dialog. Without this, _localNotifications.show() was silently
      // failing for session_started in foreground (iOS doesn't present
      // the FCM 'notification' block while the app is active, and our
      // fallback was no-op'd by the missing permission).
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: _onLocalTap,
      );

      await NotificationChannels.registerAll(_localNotifications);

      // Foreground stream — Android shows nothing system-side for
      // foreground messages, so we render via flutter_local_notifications.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Tap-to-open from background (app was backgrounded, not killed).
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // Cold-start tap (app was terminated). Capture the deep link;
      // router consumes pendingFcmDeepLink on first frame.
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        pendingFcmDeepLink = _deepLinkFor(initialMessage);
      }

      _initialised = true;
    } catch (e, st) {
      // Don't let a missing google-services.json or APNs misconfig crash
      // the app — FCM is best-effort. Log and continue.
      dev.log('FCM init failed (non-fatal): $e', name: 'fcm', error: e, stackTrace: st);
    }
  }

  /// Called after a successful auth event (OTP verify success). Asks for
  /// permission, fetches the token, persists it on families.fcm_token.
  /// Idempotent — safe to call on every auth state change.
  static Future<void> onSignIn(String familyId) async {
    // Defensive: if initialize() timed out at boot (iOS APNs first-launch
    // delay can exceed the 4s cap in bootstrap.dart), _initialised stays
    // false and we'd otherwise never prompt the user. Best-effort attempt
    // a late init so the permission prompt + token fetch still happen.
    if (!_initialised) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        _initialised = true;
      } catch (e) {
        dev.log('FCM late-init failed; aborting onSignIn: $e', name: 'fcm');
        return;
      }
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        dev.log('FCM permission denied; in-app inbox only.', name: 'fcm');
        return;
      }

      // Wire the refresh listener FIRST — before any getToken call.
      // On iOS, getToken() often returns null on the first attempt while
      // APNs registration is still in flight; the token then arrives a
      // few seconds later via this listener. If we registered the
      // listener AFTER getToken (the previous bug), an iPhone whose
      // initial getToken returned null would silently never register
      // its token at all.
      if (!_tokenListenerWired) {
        _tokenListenerWired = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          currentFcmToken = newToken;
          await _persistToken(familyId, newToken);
        });
      }

      // iOS: poll for the APNs token up to ~10s before asking Firebase
      // for the FCM token. Without an APNs token, FCM's getToken either
      // returns null or throws — neither of which the previous code
      // handled.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken;
        for (var i = 0; i < 20; i++) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          if (apnsToken != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apnsToken == null) {
          dev.log(
            'FCM iOS: APNs token never arrived in 10s; onTokenRefresh '
            'listener will pick it up if it lands later',
            name: 'fcm',
          );
          return;
        }
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        dev.log(
          'FCM getToken() returned null; relying on onTokenRefresh listener',
          name: 'fcm',
        );
        return;
      }

      currentFcmToken = token;
      await _persistToken(familyId, token);
    } catch (e, st) {
      dev.log('FCM onSignIn failed: $e', name: 'fcm', error: e, stackTrace: st);
    }
  }

  /// On sign-out, clear the token from the families row so a stale device
  /// doesn't keep receiving pushes after a parent hands the phone back.
  static Future<void> onSignOut(String familyId) async {
    try {
      await Supabase.instance.client
          .from('families')
          .update({'fcm_token': null}).eq('id', familyId);
      currentFcmToken = null;
    } catch (_) {
      // Non-fatal.
    }
  }

  static Future<void> _persistToken(String familyId, String token) async {
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    try {
      await Supabase.instance.client.from('families').update({
        'fcm_token': token,
        'fcm_platform': platform,
      }).eq('id', familyId);
    } catch (e) {
      dev.log('FCM token persist failed: $e', name: 'fcm', error: e);
    }
  }

  // ── handlers ─────────────────────────────────────────────────────────

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    // iOS foreground rendering is now done natively in
    // AppDelegate.userNotificationCenter(_:willPresent:) — that path
    // forces a banner unless `suppress_foreground=true`. Android still
    // needs a local notification because its FCM SDK doesn't auto-
    // present in foreground.
    if (message.data['suppress_foreground'] == 'true') return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // No-op on iOS — AppDelegate handles the banner. Skipping the
      // local notification avoids double-rendering.
      return;
    }

    final notification = message.notification;
    final type = message.data['type'] as String? ?? '';
    final channelId = NotificationChannels.channelForType(type);

    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null && body == null) return;

    final id = message.messageId?.hashCode.abs() ?? DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelDisplayName(channelId),
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static String _channelDisplayName(String channelId) {
    return switch (channelId) {
      NotificationChannels.sessionChannelId => 'Sessions',
      NotificationChannels.birthdayChannelId => 'Birthdays',
      NotificationChannels.marketingChannelId => 'Offers & promos',
      _ => 'General',
    };
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    pendingFcmDeepLink = _deepLinkFor(message);
    // Router has its own listener wired to consume pendingFcmDeepLink on
    // the next frame. This keeps tap-handling separate from go_router's
    // ChangeNotifier wiring and avoids a circular-import issue.
  }

  static void _onLocalTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final link = data['deep_link'] as String?;
      if (link != null && link.isNotEmpty) {
        pendingFcmDeepLink = link;
      }
    } catch (_) {
      // Malformed payload — drop silently.
    }
  }

  static String? _deepLinkFor(RemoteMessage message) {
    final dl = message.data['deep_link'];
    if (dl is String && dl.isNotEmpty) return dl;
    return null;
  }
}
