import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'widgets/empty_state.dart';

/// Birthday reservations — past or upcoming. Tapping a row deep-links to
/// the existing /birthday/status/:id flow (Session 9 owns the detail).
class PastBirthdaysScreen extends ConsumerWidget {
  const PastBirthdaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastBirthdaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthday parties'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const ProfileEmptyState(
            icon: PhosphorIconsRegular.cake,
            message: "We couldn't load reservations. Try again in a moment.",
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.cake,
                message: 'No celebrations yet. Plan a party →',
                ctaLabel: 'Plan a birthday',
                ctaRoute: '/birthday',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastBirthdaysProvider),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.lightBorder),
                itemBuilder: (_, i) => _Row(reservation: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> reservation;
  const _Row({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final id = reservation['id'] as String;
    final childName =
        ((reservation['children'] as Map?)?['name'] as String?) ?? 'child';
    final dateStr = reservation['slot_date'] as String?;
    final timeStr = reservation['slot_start_time'] as String?;
    final status = reservation['status'] as String? ?? 'reserved';

    final parsedDate = dateStr == null ? null : DateTime.tryParse(dateStr);
    final dateLabel = parsedDate == null
        ? '—'
        : DateFormat('EEE MMM d, yyyy').format(parsedDate);

    return ListTile(
      leading: const Icon(
        PhosphorIconsRegular.cake,
        color: AppColors.rafiCoral,
      ),
      title: Text("$childName's party", style: AppTextStyles.body(context)),
      subtitle: Text(
        timeStr == null ? dateLabel : '$dateLabel · $timeStr',
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ),
      ),
      trailing: _StatusChip(status: status),
      onTap: () => context.push('/birthday/status/$id'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'reserved' => ('Reserved', AppColors.gold),
      'deposit_paid' => ('Deposit paid', AppColors.activeGreen),
      'confirmed' => ('Confirmed', AppColors.activeGreen),
      'completed' => ('Completed', AppColors.lightTextSecondary),
      'cancelled' => ('Cancelled', AppColors.adminRed),
      'no_show' => ('No-show', AppColors.adminRed),
      _ => (status, AppColors.lightTextSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption(context, color: color),
      ),
    );
  }
}
