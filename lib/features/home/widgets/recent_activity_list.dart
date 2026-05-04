import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/recent_activity_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';

/// Last few activity rows from the `home_recent_activity` view, with a
/// "See all →" link that navigates to the full Profile activity log
/// (Session 5b).
class RecentActivityList extends ConsumerWidget {
  const RecentActivityList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(recentActivityProvider).valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent activity', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 12),
          for (final r in rows) _ActivityRow(row: r),
          // "See all" navigates into Profile's full activity log — wired in
          // Session 5b. Hidden until then.
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ActivityRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final kind = row['kind'] as String? ?? '';
    final subtype = row['subtype'] as String? ?? '';
    final amountPaise = row['amount_paise'] as int? ?? 0;
    final xp = row['xp_total'] as int? ?? 0;
    final duration = row['duration_minutes'] as int?;

    final (icon, color, title) = switch (kind) {
      'wallet_tx' => _walletTxLine(subtype, amountPaise),
      'session' => (
          PhosphorIconsFill.timer,
          AppColors.navy,
          duration != null
              ? 'Played ${_durationLabel(duration)}'
              : 'Session completed',
        ),
      'xp' => (
          PhosphorIconsFill.star,
          AppColors.xpPurple,
          xp > 0 ? '+$xp XP earned' : 'XP event',
        ),
      _ => (PhosphorIconsFill.circle, AppColors.lightTextSecondary, subtype),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: AppTextStyles.body(context)),
          ),
          Text(
            _relativeTime(row['created_at'] as String?),
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _walletTxLine(String subtype, int amount) {
    if (amount > 0) {
      final label = switch (subtype) {
        'topup' => 'Topped up ${Money.fromPaise(amount)}',
        'bonus' => 'Bonus credited ${Money.fromPaise(amount)}',
        'refund' => 'Refund ${Money.fromPaise(amount)}',
        'reactivation_credit' => 'Welcome back credit',
        _ => '+${Money.fromPaise(amount)}',
      };
      return (PhosphorIconsFill.plusCircle, AppColors.activeGreen, label);
    }
    final abs = -amount;
    final label = switch (subtype) {
      'session_debit' => 'Session ${Money.fromPaise(abs)}',
      'extension_debit' => 'Extension ${Money.fromPaise(abs)}',
      'order_debit' => 'Order ${Money.fromPaise(abs)}',
      _ => '-${Money.fromPaise(abs)}',
    };
    return (PhosphorIconsFill.minusCircle, AppColors.lightTextSecondary, label);
  }

  String _durationLabel(int minutes) {
    if (minutes >= 60 && minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return '$h hour${h == 1 ? "" : "s"}';
    }
    return '$minutes min';
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final t = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][t.month - 1];
    return '$m ${t.day}';
  }
}
