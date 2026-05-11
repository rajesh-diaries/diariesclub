import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shown on the active session view once the session has been running
/// for 20+ minutes. The push notification fires server-side via the
/// `_hydration_reminder_sweep()` cron — this banner is the in-app twin.
///
/// Dismissable. Auto-hides if the parent rebuilds without the
/// hydration_reminded_at flag (e.g., session ended or session row
/// invalidated).
class HydrationReminderBanner extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const HydrationReminderBanner({super.key, required this.session});

  @override
  ConsumerState<HydrationReminderBanner> createState() =>
      _HydrationReminderBannerState();
}

class _HydrationReminderBannerState
    extends ConsumerState<HydrationReminderBanner> {
  bool _dismissed = false;

  static const _hydrationThreshold = Duration(minutes: 20);

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final startedAtStr = widget.session['started_at'] as String?;
    if (startedAtStr == null) return const SizedBox.shrink();
    final startedAt = DateTime.parse(startedAtStr);
    final elapsed = DateTime.now().difference(startedAt);

    // Only show after 20 minutes have elapsed.
    if (elapsed < _hydrationThreshold) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        border: Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF1976D2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              PhosphorIconsFill.drop,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hydration check',
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0D47A1),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Quick sip of water for your kid — keeps the play going strong.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Got it',
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.lightTextSecondary,
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
