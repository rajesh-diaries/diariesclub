import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'providers/workshops_provider.dart';
import 'widgets/workshop_card.dart';

class WorkshopsTab extends ConsumerWidget {
  const WorkshopsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(workshopFilterProvider);
    final async = ref.watch(workshopsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _Empty(text: "Couldn't load workshops."),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Themed sessions earn extra XP.',
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
                child: _Empty(
                  text: filter == WorkshopFilter.past
                      ? "You haven't attended any workshops yet."
                      : 'No workshops scheduled for that window.',
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

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsRegular.paintBrush,
              size: 56,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
