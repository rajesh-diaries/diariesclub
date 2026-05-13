import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Compact card for a single active/pending/grace session in the
/// multi-session home stack. Shows kid name + status + time remaining
/// (or "Awaiting QR scan" for pending). Tap → opens that session's QR
/// screen for staff to scan / extend / wrap up.
class ActiveSessionCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const ActiveSessionCard({super.key, required this.session});

  @override
  ConsumerState<ActiveSessionCard> createState() => _ActiveSessionCardState();
}

class _ActiveSessionCardState extends ConsumerState<ActiveSessionCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final status = session['status'] as String? ?? 'active';
    final childId = session['child_id'] as String?;
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final child = children.firstWhere(
      (c) => c['id'] == childId,
      orElse: () => const <String, dynamic>{},
    );
    final childName = (child['name'] as String?) ?? 'Your kid';

    final expiresAtStr = session['expires_at'] as String?;
    // tryParse so a malformed/null timestamp from a transient API state
    // doesn't kill the Home tab with a FormatException — the timer just
    // shows "—" until the next stream tick refreshes.
    final expiresAt = expiresAtStr == null
        ? null
        : DateTime.tryParse(expiresAtStr)?.toLocal();
    final now = DateTime.now();
    final isPending = status == 'pending';
    final isGrace = expiresAt != null && expiresAt.isBefore(now);

    final timeLabel = _timeLabel(
      isPending: isPending,
      isGrace: isGrace,
      expiresAt: expiresAt,
      now: now,
    );

    final accentColor = isPending
        ? AppColors.gold
        : isGrace
            ? AppColors.warningYellow
            : AppColors.activeGreen;

    // Pending = QR not scanned yet; tap routes to QR for staff to scan.
    // Active/grace = already scanned; tap routes to the detail controls
    // (Order food / Extend / Wrap up). Going back to QR would be a
    // dead-end at that point.
    final route = isPending
        ? '/session/qr/${session['id']}'
        : '/session/${session['id']}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIconsFill.smileyMelting,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    childName,
                    style: AppTextStyles.h3(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: AppTextStyles.caption(
                      context,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.navy),
          ],
        ),
      ),
    );
  }

  String _timeLabel({
    required bool isPending,
    required bool isGrace,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    if (isPending) return 'Awaiting QR scan at venue';
    if (expiresAt == null) return 'In session';
    final diff = expiresAt.difference(now);
    if (isGrace) {
      final overrun = -diff.inMinutes;
      return overrun <= 0
          ? 'Wrapping up'
          : 'Wrapping up · +$overrun min';
    }
    final mins = diff.inMinutes;
    final secs = diff.inSeconds.remainder(60);
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return 'Playing · ${hrs}h ${remMins.toString()}m left';
    }
    return 'Playing · $mins:${secs.toString().padLeft(2, '0')} left';
  }
}
