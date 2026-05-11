import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 4 Android notification channels. Registered once on bootstrap; channel
/// IDs match the `data.channel` field that the Edge Function send-push
/// (Session 13) sets per notification type.
///
/// iOS doesn't have channels; categories are configured via the
/// permission flow in fcm_setup.dart. TODO(ios): when iOS push lands,
/// audit category mapping in matrix below.
class NotificationChannels {
  NotificationChannels._();

  static const defaultChannelId = 'default';
  static const sessionChannelId = 'session';
  static const birthdayChannelId = 'birthday';
  static const marketingChannelId = 'marketing';

  /// Mapping from notifications.type → channel id. Single source of truth
  /// so the foreground handler picks the same channel the Edge Function
  /// would.
  static String channelForType(String type) {
    if (type.startsWith('session_') ||
        type == 'grace_started' ||
        type == 'extend_nudge' ||
        type == 'hydration_nudge' ||
        type == 'recap_ready' ||
        type == 'reflection_prompt' ||
        type == 'reflection_auto_split') {
      return sessionChannelId;
    }
    if (type.startsWith('birthday_')) {
      return birthdayChannelId;
    }
    if (type.startsWith('marketing_') ||
        type == 'gift_unlocked' ||
        type == 'topup_offer') {
      return marketingChannelId;
    }
    return defaultChannelId;
  }

  /// Create all 4 channels on Android. No-op on iOS (channels are an
  /// Android concept; iOS uses categories via UNNotificationCategory).
  static Future<void> registerAll(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    const channels = <AndroidNotificationChannel>[
      AndroidNotificationChannel(
        defaultChannelId,
        'General',
        description: 'Order updates, character card unlocks, wallet alerts.',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        sessionChannelId,
        'Sessions',
        description:
            'Active session events: grace, hydration nudges, recap ready.',
        importance: Importance.high,
      ),
      AndroidNotificationChannel(
        birthdayChannelId,
        'Birthdays',
        description: 'Birthday journey reminders and album notifications.',
        importance: Importance.defaultImportance,
      ),
      AndroidNotificationChannel(
        marketingChannelId,
        'Offers & promos',
        description: 'Top-up offers, gift drops, seasonal campaigns.',
        importance: Importance.low,
      ),
    ];

    for (final channel in channels) {
      await android.createNotificationChannel(channel);
    }
  }
}
