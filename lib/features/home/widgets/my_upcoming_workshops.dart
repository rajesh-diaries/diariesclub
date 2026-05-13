import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../club/providers/workshops_provider.dart';

/// Home-tab section listing the family's upcoming workshop registrations.
/// Renders nothing when there are no upcoming registrations (auto-hides).
///
/// Why a Future-backed provider that depends on a stream:
/// `myWorkshopRegistrationsProvider` is a realtime stream of registration
/// rows (no workshop details). For nice cards we need the workshop's title,
/// date, cover, etc. — which means a one-shot join. ref.watch on the stream
/// makes this provider re-run whenever the registration list changes.
final _myUpcomingWorkshopsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final regs =
      ref.watch(myWorkshopRegistrationsProvider).valueOrNull ?? const [];
  if (regs.isEmpty) return const [];

  final ids = regs.map((r) => r['workshop_id'] as String).toSet().toList();
  if (ids.isEmpty) return const [];

  final rows = await Supabase.instance.client
      .from('workshops')
      .select()
      .inFilter('id', ids);

  final now = DateTime.now();
  final byId = <String, Map<String, dynamic>>{
    for (final r in (rows as List))
      (r as Map)['id'] as String: Map<String, dynamic>.from(r),
  };

  final result = <Map<String, dynamic>>[];
  for (final reg in regs) {
    final w = byId[reg['workshop_id']];
    if (w == null) continue;
    final scheduled =
        DateTime.tryParse((w['scheduled_at'] as String?) ?? '');
    if (scheduled == null || scheduled.isBefore(now)) continue;
    result.add({...w, '_registration_id': reg['id']});
  }
  result.sort((a, b) => ((a['scheduled_at'] as String?) ?? '')
      .compareTo((b['scheduled_at'] as String?) ?? ''));
  return result;
});

class MyUpcomingWorkshopsSection extends ConsumerWidget {
  const MyUpcomingWorkshopsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myUpcomingWorkshopsProvider);
    final workshops = async.valueOrNull ?? const [];
    if (workshops.isEmpty) return const SizedBox.shrink();

    return Padding(
      // Self-margin so the parent doesn't leave a phantom gap when
      // this widget auto-hides (no upcoming registrations).
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                PhosphorIconsFill.paintBrush,
                size: 16,
                color: AppColors.navy.withValues(alpha: 0.70),
              ),
              const SizedBox(width: 6),
              Text(
                workshops.length == 1
                    ? 'Your upcoming workshop'
                    : 'Your upcoming workshops',
                style: AppTextStyles.body(context).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < workshops.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _UpcomingWorkshopCard(workshop: workshops[i]),
        ],
        ],
      ),
    );
  }
}

class _UpcomingWorkshopCard extends StatelessWidget {
  final Map<String, dynamic> workshop;
  const _UpcomingWorkshopCard({required this.workshop});

  @override
  Widget build(BuildContext context) {
    final id = (workshop['id'] as String?) ?? '';
    if (id.isEmpty) return const SizedBox.shrink();

    final title = (workshop['title'] as String?) ?? 'Workshop';
    final cover = workshop['cover_image_url'] as String?;
    final scheduled =
        DateTime.tryParse((workshop['scheduled_at'] as String?) ?? '');
    if (scheduled == null) return const SizedBox.shrink();

    final dateStr =
        DateFormat('EEE MMM d · h:mm a').format(scheduled.toLocal());
    final daysAway = scheduled.difference(DateTime.now()).inDays;
    final urgency = daysAway <= 1
        ? (daysAway == 0 ? 'Today' : 'Tomorrow')
        : (daysAway < 7 ? 'In $daysAway days' : null);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/club/workshop/$id'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: cover == null
                        ? Container(
                            color: AppColors.gold.withValues(alpha: 0.20),
                            alignment: Alignment.center,
                            child: const Icon(
                              PhosphorIconsRegular.paintBrush,
                              color: AppColors.gold,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.gold.withValues(alpha: 0.20),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTextStyles.bodyLarge(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (urgency != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                urgency,
                                style: AppTextStyles.caption(
                                  context,
                                  color: AppColors.navy,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "You're registered",
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.activeGreen,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.lightTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
