import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/current_family_provider.dart';
import '../../core/providers/notification_preferences_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Per-category notification toggles. Backed by `families.notification_preferences`
/// (JSONB). Marketing toggle is a *single source of truth* with
/// `families.marketing_consent` — flipping one flips both, so users don't
/// see two settings drift apart.
class NotificationsSettingsScreen extends ConsumerStatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  ConsumerState<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends ConsumerState<NotificationsSettingsScreen> {
  bool _busy = false;

  Future<void> _toggle({
    required NotificationPreferences current,
    required NotificationPreferences updated,
    required String key,
    required bool newValue,
  }) async {
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId == null) return;
    setState(() => _busy = true);

    try {
      final patch = <String, dynamic>{
        'notification_preferences': updated.toJson(),
      };
      // Marketing is mirrored to families.marketing_consent so the Home
      // marketing card and notification dispatch share the same source.
      if (key == 'marketing') {
        patch['marketing_consent'] = newValue;
      }
      await Supabase.instance.client
          .from('families')
          .update(patch)
          .eq('id', familyId);
      ref.invalidate(currentFamilyProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load preferences.",
                style: AppTextStyles.body(context),
              ),
            ),
          ),
          data: (prefs) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  "Pick which notifications you'd like to receive. We "
                  'default everything on, except marketing.',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
              _Toggle(
                title: 'Session reminders',
                subtitle:
                    'Time-running-out, grace nudges, session-complete pings.',
                value: prefs.sessionReminders,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(sessionReminders: v),
                          key: 'session_reminders',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Hero progression',
                subtitle:
                    'Stage transitions, hero card unlocks, level-ups.',
                value: prefs.heroProgression,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(heroProgression: v),
                          key: 'hero_progression',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Birthday reminders',
                subtitle: 'Countdown nudges as the big day approaches.',
                value: prefs.birthdayReminders,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(birthdayReminders: v),
                          key: 'birthday_reminders',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Birthday wishes for my children',
                subtitle:
                    'A short note from us on your kids\' birthdays — even if you celebrate elsewhere.',
                value: prefs.birthdayWishEnabled,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(birthdayWishEnabled: v),
                          key: 'birthday_wish_enabled',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Order status',
                subtitle: 'Confirmations and ready-to-pickup pings.',
                value: prefs.orderStatus,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(orderStatus: v),
                          key: 'order_status',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Wallet alerts',
                subtitle: 'Low balance, top-up confirmations.',
                value: prefs.walletAlerts,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(walletAlerts: v),
                          key: 'wallet_alerts',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Marketing & offers',
                subtitle: 'Tips, party ideas, special offers.',
                value: prefs.marketing,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(marketing: v),
                          key: 'marketing',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Streaks & milestones',
                subtitle: 'Visit milestones, weekly streak rewards.',
                value: prefs.streaksMilestones,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(streaksMilestones: v),
                          key: 'streaks_milestones',
                          newValue: v,
                        ),
              ),
              _Toggle(
                title: 'Workshop reminders',
                subtitle: 'Upcoming workshops your kids might enjoy.',
                value: prefs.workshopReminders,
                onChanged: _busy
                    ? null
                    : (v) => _toggle(
                          current: prefs,
                          updated: prefs.copyWith(workshopReminders: v),
                          key: 'workshop_reminders',
                          newValue: v,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: AppTextStyles.body(context)),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
