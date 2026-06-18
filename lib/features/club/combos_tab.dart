import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_state.dart';
import '../../core/widgets/skeleton_card.dart';
import 'providers/club_search_provider.dart';
import 'providers/combos_provider.dart';
import 'widgets/combo_card.dart';

class CombosTab extends ConsumerWidget {
  const CombosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combosAsync = ref.watch(combosProvider);
    final query = ref.watch(clubSearchQueryProvider);

    return combosAsync.when(
      loading: () => const SkeletonList(itemCount: 2, itemHeight: 320),
      error: (_, __) => Center(
        child: BrandedErrorState(
          message: "Couldn't load combos.",
          onRetry: () => ref.invalidate(combosProvider),
        ),
      ),
      data: (combos) {
        final filtered = query.isEmpty
            ? combos
            : combos.where((c) => _matchesQuery(c, query)).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(combosProvider),
          child: filtered.isEmpty
              ? const Center(
                  child: BrandedEmptyState(
                    icon: PhosphorIconsRegular.gift,
                    title: 'No combos match your search.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text('Better together', style: AppTextStyles.h2(context)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Bundle deals across Coffee + FIT.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    for (final c in filtered) ComboCard(combo: c),
                  ],
                ),
        );
      },
    );
  }

  bool _matchesQuery(Map<String, dynamic> combo, String query) {
    final haystack = [
      combo['name']?.toString() ?? '',
      combo['description']?.toString() ?? '',
      ...(combo['tags'] as List<dynamic>? ?? []).map((t) => t.toString()),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
