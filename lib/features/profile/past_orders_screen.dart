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

/// Past Café Diaries / FIT Diaries / Combos orders. Empty state CTA goes
/// to the Club tab to browse the menu (Session 7 builds the placement
/// flow; this screen lights up automatically once orders start landing).
class PastOrdersScreen extends ConsumerWidget {
  const PastOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Past orders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const ProfileEmptyState(
            icon: PhosphorIconsRegular.coffee,
            message: "We couldn't load orders. Try again in a moment.",
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.coffee,
                message:
                    "You'll see your café and FIT orders here. Browse the menu →",
                ctaLabel: 'Browse menu',
                ctaRoute: '/club',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastOrdersProvider),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.lightBorder),
                itemBuilder: (_, i) => _OrderRow(order: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final brand = (order['brand'] as String?) ?? 'café';
    final amount = (order['total_paise'] as int?) ?? 0;
    final coins = (order['coins_earned'] as int?) ?? 0;
    final created = order['created_at'] as String?;
    final parsedCreated =
        created == null ? null : DateTime.tryParse(created)?.toLocal();
    final dateStr = parsedCreated == null
        ? '—'
        : DateFormat('MMM d').format(parsedCreated);

    return ListTile(
      leading: Icon(
        brand == 'fit'
            ? PhosphorIconsRegular.carrot
            : PhosphorIconsRegular.coffee,
        color: AppColors.coffeeBrown,
      ),
      title: Text(
        brand == 'fit' ? 'FIT Diaries' : 'Coffee Diaries',
        style: AppTextStyles.body(context),
      ),
      subtitle: Text(
        coins > 0
            ? '$dateStr · earned $coins coins'
            : dateStr,
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ),
      ),
      trailing: Text(
        Money.fromPaise(amount),
        style: AppTextStyles.body(context),
      ),
    );
  }
}
