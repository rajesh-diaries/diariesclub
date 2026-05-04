import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'providers/combos_provider.dart';
import 'widgets/combo_card.dart';

class CombosTab extends ConsumerWidget {
  const CombosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combosAsync = ref.watch(combosProvider);

    return combosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const _Empty(text: "Couldn't load combos. Pull to retry."),
      data: (combos) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(combosProvider),
        child: combos.isEmpty
            ? const _Empty(text: 'New combos coming soon.')
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
                  for (final c in combos) ComboCard(combo: c),
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
              PhosphorIconsRegular.gift,
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
