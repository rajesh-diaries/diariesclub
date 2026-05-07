import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_channels.dart';
import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// FEATURE-002 — complimentary Healthy Bite reminder banner.
///
/// Shows above the session timer when:
///   - session has 10 minutes or less remaining (and not yet expired)
///   - session.healthy_bite_claimed_at IS NULL (staff hasn't marked claimed)
///   - customer hasn't dismissed the banner this session
///
/// Self-hides when staff marks claimed (Realtime updates the session row →
/// claimed_at non-null → banner returns SizedBox.shrink). Dismissal is
/// per-session (SharedPreferences key `hb_dismissed_<sessionId>`).
class HealthyBiteReminderBanner extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const HealthyBiteReminderBanner({super.key, required this.session});

  @override
  ConsumerState<HealthyBiteReminderBanner> createState() =>
      _HealthyBiteReminderBannerState();
}

class _HealthyBiteReminderBannerState
    extends ConsumerState<HealthyBiteReminderBanner> {
  bool _dismissed = false;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = widget.session['id'] as String;
    if (!mounted) return;
    setState(() {
      _dismissed = prefs.getBool('hb_dismissed_$sessionId') ?? false;
      _notified = prefs.getBool('hb_notified_$sessionId') ?? false;
    });
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = widget.session['id'] as String;
    await prefs.setBool('hb_dismissed_$sessionId', true);
    if (mounted) setState(() => _dismissed = true);
  }

  /// Fire a local notification once, the moment we first detect the
  /// eligibility window. Mobile only — `flutter_local_notifications` has
  /// no reliable web implementation and `kIsWeb` short-circuits cleanly.
  /// Server-side FCM cron for backgrounded clients is a v1.1 follow-up.
  Future<void> _maybeNotify(String childName) async {
    if (_notified || kIsWeb) return;
    _notified = true; // set immediately to prevent re-fire on next tick
    final prefs = await SharedPreferences.getInstance();
    final sessionId = widget.session['id'] as String;
    await prefs.setBool('hb_notified_$sessionId', true);
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.show(
        sessionId.hashCode & 0x7fffffff, // stable per-session notif id
        'A treat for $childName!',
        'Pop by the counter for a complimentary Healthy Bite.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationChannels.sessionChannelId,
            'Sessions',
            channelDescription:
                'Active session events: grace, hydration, healthy bite.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // Notification is a nice-to-have; banner is the primary surface.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    // Already claimed by staff → hide.
    if (widget.session['healthy_bite_claimed_at'] != null) {
      return const SizedBox.shrink();
    }

    final expiresAtStr = widget.session['expires_at'] as String?;
    if (expiresAtStr == null) return const SizedBox.shrink();
    final expiresAt = DateTime.parse(expiresAtStr);
    final remaining = expiresAt.difference(DateTime.now());

    // Show only when within the last 10 minutes (and session hasn't ended).
    if (remaining.inSeconds <= 0 || remaining.inMinutes > 10) {
      return const SizedBox.shrink();
    }

    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final childId = widget.session['child_id'] as String?;
    final childName = children.firstWhere(
      (c) => c['id'] == childId,
      orElse: () => const <String, dynamic>{},
    )['name'] as String? ?? 'Your hero';

    // Side effect: fire local notification once when first eligible.
    // Banner is rebuilt on the parent's 1Hz tick, so this fires on the
    // first eligible build and short-circuits thereafter via _notified.
    if (!_notified) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeNotify(childName);
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold,
            AppColors.gold.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsFill.gift,
            color: AppColors.navy,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$childName deserves a Healthy Bite!',
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Please collect from counter — our compliments.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.navy.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _dismiss,
            tooltip: 'Dismiss',
            icon: const Icon(
              PhosphorIconsRegular.x,
              color: AppColors.navy,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
