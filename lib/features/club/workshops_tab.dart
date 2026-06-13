import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton_card.dart';
import 'providers/workshops_provider.dart';
import 'widgets/workshop_card.dart';

class WorkshopsTab extends ConsumerWidget {
  const WorkshopsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(workshopFilterProvider);
    final async = ref.watch(workshopsProvider);
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final tagline = (cfg['workshops_tagline'] as String?)?.trim() ?? '';

    return async.when(
      loading: () => const SkeletonList(itemCount: 3, itemHeight: 260),
      error: (_, __) => Center(
        child: BrandedErrorState(
          message: "Couldn't load workshops.",
          onRetry: () => ref.invalidate(workshopsProvider),
        ),
      ),
      data: (workshops) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(workshopsProvider),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text('Workshops', style: AppTextStyles.h2(context)),
              ),
            ),
            if (tagline.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    tagline,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  children: [
                    for (final f in WorkshopFilter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: filter == f,
                          onSelected: (v) {
                            if (v) {
                              ref
                                  .read(workshopFilterProvider.notifier)
                                  .state = f;
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (workshops.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: BrandedEmptyState(
                    icon: PhosphorIconsRegular.paintBrush,
                    title: filter == WorkshopFilter.past
                        ? "You haven't attended any workshops yet."
                        : 'No workshops scheduled for that window.',
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => WorkshopCard(workshop: workshops[i]),
                  childCount: workshops.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}
