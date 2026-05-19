import Flutter
import UIKit
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register as the UNUserNotificationCenter delegate so our
    // willPresent override below runs. FlutterAppDelegate conforms to
    // UNUserNotificationCenterDelegate, so `self` is a valid delegate.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
  }

  // ── Foreground presentation override ──────────────────────────────────
  //
  // Why this exists: on iOS 26, the Dart-side path
  // (`FlutterFire.setForegroundNotificationPresentationOptions` plus
  // `_onForegroundMessage` calling `flutter_local_notifications.show()`)
  // was inconsistent — lock screen + background banners worked, but
  // foreground banners silently dropped. Native willPresent gives us a
  // single deterministic decision point at the OS layer, before any
  // plugin races.
  //
  // We notify FCM manually (Messaging.appDidReceiveMessage) so the
  // analytics + data_message_handler side-effects still fire, then
  // force [.banner, .badge, .sound] unless the push explicitly asked
  // us to suppress in-app (suppress_foreground=true — used by types
  // like hydration_nudge / grace_started where the relevant UI is
  // already on screen).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    Messaging.messaging().appDidReceiveMessage(userInfo)

    let suppress = (userInfo["suppress_foreground"] as? String) == "true"
    if suppress {
      completionHandler([])
      return
    }
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
