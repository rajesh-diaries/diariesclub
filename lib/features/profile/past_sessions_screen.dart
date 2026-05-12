import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import 'widgets/empty_state.dart';

/// "Past sessions" — every play session for this family, most recent first.
/// Status badge shows {Active, Reflected, Auto-split, Completed, Cancelled}.
class PastSessionsScreen extends ConsumerWidget {
  const PastSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Past sessions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load sessions.",
                style: AppTextStyles.body(context),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.timer,
                message: 'Your first session is just a tap away.',
                ctaLabel: 'Start a session',
                ctaRoute: '/session/start',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastSessionsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.lightBorder),
                itemBuilder: (_, i) => _Row(session: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> session;
  const _Row({required this.session});

  @override
  Widget build(BuildContext context) {
    final id = session['id'] as String;
    final duration = session['duration_minutes'] as int? ?? 0;
    final amount = session['amount_paise'] as int? ?? 0;
    final status = session['status'] as String? ?? 'completed';
    final reflection = session['reflection_status'] as String? ?? 'pending';
    final xp = session['total_xp_earned'] as int? ?? 0;
    final childName =
        ((session['children'] as Map?)?['name'] as String?) ?? 'Your child';
    final createdAt =
        DateTime.parse(session['created_at'] as String).toLocal();

    return ListTile(
      leading: const Icon(
        PhosphorIconsRegular.timer,
        color: AppColors.navy,
      ),
      title: Text(
        '$childName · ${duration == 60 ? '1 hour' : '$duration min'}',
        style: AppTextStyles.body(context),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMM d · EEEE').format(createdAt),
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              _StatusChip(status: status),
              if (reflection == 'reflected')
                const _Chip(text: 'Reflected', color: AppColors.activeGreen),
              if (reflection == 'auto_split')
                const _Chip(text: 'Auto-split', color: AppColors.gold),
              if (xp > 0) _Chip(text: '+$xp XP', color: AppColors.xpPurple),
            ],
          ),
        ],
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            Money.fromPaise(amount),
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 2),
          const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppColors.lightTextSecondary,
          ),
        ],
      ),
      onTap: () => context.push('/profile/sessions/$id'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Active', AppColors.activeGreen),
      'grace' => ('Wrapping up', AppColors.warningYellow),
      'completed' => ('Completed', AppColors.lightTextSecondary),
      'auto_closed' => ('Auto-closed', AppColors.warningYellow),
      'void' => ('Cancelled', AppColors.adminRed),
      _ => (status, AppColors.lightTextSecondary),
    };
    return _Chip(text: label, color: color);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}
