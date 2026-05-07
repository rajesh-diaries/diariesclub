import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'widgets/empty_state.dart';

/// Workshops the family has registered for. Two sections: Upcoming
/// (scheduled in the future, not cancelled) + Past (already happened OR
/// cancelled). Each section uses card rows with cover image + title +
/// date + status pill so the screen reads as workshops, not a SQL dump.
///
/// (Was a flat ListTile list — too text-heavy per founder feedback.)
class PastWorkshopsScreen extends ConsumerWidget {
  const PastWorkshopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastWorkshopsProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Workshops'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const ProfileEmptyState(
            icon: PhosphorIconsRegular.paintBrush,
            message: "We couldn't load workshops. Try again in a moment.",
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.paintBrush,
                message: "No workshops yet. Discover what's coming up →",
                ctaLabel: 'See workshops',
                ctaRoute: '/club',
              );
            }

            final now = DateTime.now();
            final upcoming = <Map<String, dynamic>>[];
            final past = <Map<String, dynamic>>[];
            for (final r in rows) {
              final ws = (r['workshops'] as Map?) ?? const {};
              final dt = DateTime.tryParse(
                  (ws['scheduled_at'] as String?) ?? '');
              final cancelled = r['cancelled_at'] != null;
              if (!cancelled && dt != null && dt.isAfter(now)) {
                upcoming.add(r);
              } else {
                past.add(r);
              }
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastWorkshopsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (upcoming.isNotEmpty) ...[
                    _SectionHeader(
                      label: 'Upcoming',
                      count: upcoming.length,
                    ),
                    for (final r in upcoming)
                      _WorkshopRegistrationCard(reg: r, isPast: false),
                    const SizedBox(height: 8),
                  ],
                  if (past.isNotEmpty) ...[
                    _SectionHeader(label: 'Past', count: past.length),
                    for (final r in past)
                      _WorkshopRegistrationCard(reg: r, isPast: true),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.lightSurface,
              border: Border.all(color: AppColors.lightBorder),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '$count',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkshopRegistrationCard extends StatelessWidget {
  final Map<String, dynamic> reg;
  final bool isPast;
  const _WorkshopRegistrationCard({
    required this.reg,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    final ws = (reg['workshops'] as Map?) ?? const {};
    final title = (ws['title'] as String?) ?? 'Workshop';
    final cover = ws['cover_image_url'] as String?;
    final scheduled =
        DateTime.tryParse((ws['scheduled_at'] as String?) ?? '');
    final attended = reg['attended'] == true;
    final cancelled = reg['cancelled_at'] != null;
    final workshopId = ws['id'] as String?;

    final dateStr = scheduled == null
        ? '—'
        : DateFormat('EEE MMM d, yyyy').format(scheduled.toLocal());
    final timeStr = scheduled == null
        ? null
        : DateFormat('h:mm a').format(scheduled.toLocal());

    final (statusLabel, statusColor) = cancelled
        ? ('Cancelled', AppColors.adminRed)
        : attended
            ? ('Attended', AppColors.activeGreen)
            : isPast
                ? ('Missed', AppColors.lightTextSecondary)
                : ("You're registered", AppColors.activeGreen);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: workshopId == null
              ? null
              : () => context.push('/club/workshop/$workshopId'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: cover == null
                        ? Container(
                            color: AppColors.gold.withValues(alpha: 0.20),
                            alignment: Alignment.center,
                            child: const Icon(
                              PhosphorIconsRegular.paintBrush,
                              color: AppColors.gold,
                              size: 28,
                            ),
                          )
                        : ColorFiltered(
                            colorFilter: isPast
                                ? const ColorFilter.matrix(<double>[
                                    0.33, 0.33, 0.33, 0, 0,
                                    0.33, 0.33, 0.33, 0, 0,
                                    0.33, 0.33, 0.33, 0, 0,
                                    0,    0,    0,    1, 0,
                                  ])
                                : const ColorFilter.mode(
                                    Colors.transparent, BlendMode.dst),
                            child: CachedNetworkImage(
                              imageUrl: cover,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.gold.withValues(alpha: 0.20),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyLarge(context).copyWith(
                          color: cancelled
                              ? AppColors.lightTextSecondary
                              : null,
                          decoration: cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeStr == null ? dateStr : '$dateStr · $timeStr',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          statusLabel,
                          style: AppTextStyles.caption(
                            context,
                            color: statusColor,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (workshopId != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.lightTextSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
