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

      // Local notifications plugin (used to render foreground banners on
      // Android — iOS shows them itself if the user grants permission).
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // TODO(ios): swap for DarwinInitializationSettings with
          // requestAlertPermission etc. once iOS push lands.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
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
    if (!_initialised) return;

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

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      currentFcmToken = token;
      await _persistToken(familyId, token);

      // Refresh listener — fires when the token rotates (rare but happens
      // after reinstall, app-data clear, or backend rotation).
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        currentFcmToken = newToken;
        await _persistToken(familyId, newToken);
      });
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
    // The Edge Function sets `data.suppress_foreground=true` for events
    // the user is already looking at (session screens, etc.). Skip the
    // banner in that case — the in-app stream already updates the UI.
    if (message.data['suppress_foreground'] == 'true') return;

    final notification = message.notification;
    final type = message.data['type'] as String? ?? '';
    final channelId = NotificationChannels.channelForType(type);

    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null && body == null) return;

    // ID is a small hash so re-deliveries dedupe; not strictly required.
    final id = message.messageId?.hashCode.abs() ?? DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelDisplayName(channelId),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        // TODO(ios): mirror channel concept via notification categories.
        iOS: const DarwinNotificationDetails(),
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
