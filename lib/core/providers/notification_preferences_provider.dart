import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_provider.dart';

/// Per-category notification preferences stored on `families.notification_preferences`.
/// Defaults (set in migration 0009): everything on except `marketing`.
class NotificationPreferences {
  final bool sessionReminders;
  final bool heroProgression;
  final bool birthdayReminders;
  final bool orderStatus;
  final bool walletAlerts;
  final bool marketing;
  final bool streaksMilestones;
  final bool workshopReminders;

  const NotificationPreferences({
    required this.sessionReminders,
    required this.heroProgression,
    required this.birthdayReminders,
    required this.orderStatus,
    required this.walletAlerts,
    required this.marketing,
    required this.streaksMilestones,
    required this.workshopReminders,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    return NotificationPreferences(
      sessionReminders: j['session_reminders'] as bool? ?? true,
      heroProgression: j['hero_progression'] as bool? ?? true,
      birthdayReminders: j['birthday_reminders'] as bool? ?? true,
      orderStatus: j['order_status'] as bool? ?? true,
      walletAlerts: j['wallet_alerts'] as bool? ?? true,
      marketing: j['marketing'] as bool? ?? false,
      streaksMilestones: j['streaks_milestones'] as bool? ?? true,
      workshopReminders: j['workshop_reminders'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_reminders': sessionReminders,
        'hero_progression': heroProgression,
        'birthday_reminders': birthdayReminders,
        'order_status': orderStatus,
        'wallet_alerts': walletAlerts,
        'marketing': marketing,
        'streaks_milestones': streaksMilestones,
        'workshop_reminders': workshopReminders,
      };

  NotificationPreferences copyWith({
    bool? sessionReminders,
    bool? heroProgression,
    bool? birthdayReminders,
    bool? orderStatus,
    bool? walletAlerts,
    bool? marketing,
    bool? streaksMilestones,
    bool? workshopReminders,
  }) =>
      NotificationPreferences(
        sessionReminders: sessionReminders ?? this.sessionReminders,
        heroProgression: heroProgression ?? this.heroProgression,
        birthdayReminders: birthdayReminders ?? this.birthdayReminders,
        orderStatus: orderStatus ?? this.orderStatus,
        walletAlerts: walletAlerts ?? this.walletAlerts,
        marketing: marketing ?? this.marketing,
        streaksMilestones: streaksMilestones ?? this.streaksMilestones,
        workshopReminders: workshopReminders ?? this.workshopReminders,
      );
}

/// Streams the current family's notification preferences via the families
/// realtime publication (added in 0009). Yields defaults until the row
/// loads.
final notificationPreferencesProvider =
    StreamProvider<NotificationPreferences>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield NotificationPreferences.fromJson(null);
    return;
  }

  final stream = Supabase.instance.client
      .from('families')
      .stream(primaryKey: ['id'])
      .eq('id', familyId)
      .limit(1);

  await for (final rows in stream) {
    if (rows.isEmpty) continue;
    yield NotificationPreferences.fromJson(
      rows.first['notification_preferences'] as Map<String, dynamic>?,
    );
  }
});
