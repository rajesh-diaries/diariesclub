import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/error_screen.dart';
import 'child_adventure_dashboard.dart';
import 'providers/selected_adventure_child_id_provider.dart';
import 'widgets/cafe_only_empty_state.dart';
import 'widgets/child_select_card.dart';

/// Tab 3 — Adventure. Routes to one of:
///   * CafeOnlyEmptyState — no live children
///   * ChildAdventureDashboard — single child (auto-select)
///   * _MultiChildSelector — multi-child picker
///   * ChildAdventureDashboard — once a child is picked
///
/// The picked child is persisted in SharedPreferences via
/// `selectedAdventureChildIdProvider`, so coming back to the tab returns
/// to the same dashboard.
class AdventureScreen extends ConsumerWidget {
  const AdventureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenAsync = ref.watch(familyChildrenProvider);
    final selectedId = ref.watch(selectedAdventureChildIdProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Adventure'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                context.push('/onboarding/welcome?revisit=1'),
            icon: const Icon(
              PhosphorIconsRegular.info,
              size: 18,
              color: AppColors.navy,
            ),
            label: const Text(
              'About',
              style: TextStyle(color: AppColors.navy),
            ),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
          IconButton(
            tooltip: 'Wall of Legends',
            icon: const Icon(
              PhosphorIconsRegular.trophy,
              color: AppColors.gold,
            ),
            onPressed: () => context.push('/adventure/wall-of-legends'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: childrenAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-ADV',
          userMessage: "Couldn't load adventure",
          technicalDetails: e.toString(),
        ),
        data: (children) {
          if (children.isEmpty) return const CafeOnlyEmptyState();

          // Single child → auto-select to skip the picker.
          if (children.length == 1) {
            final id = children.first['id'] as String;
            if (selectedId != id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref
                    .read(selectedAdventureChildIdProvider.notifier)
                    .select(id);
              });
            }
            return ChildAdventureDashboard(childId: id);
          }

          if (selectedId == null ||
              !children.any((c) => c['id'] == selectedId)) {
            return _MultiChildSelector(children: children);
          }
          return ChildAdventureDashboard(childId: selectedId);
        },
      ),
    );
  }
}

class _MultiChildSelector extends ConsumerWidget {
  final List<Map<String, dynamic>> children;
  const _MultiChildSelector({required this.children});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Whose adventure?', style: AppTextStyles.h1(context)),
            const SizedBox(height: 6),
            Text(
              'Pick a hero to follow today.',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.78,
                children: [
                  for (final c in children)
                    ChildSelectCard(
                      child: c,
                      onTap: () => ref
                          .read(selectedAdventureChildIdProvider.notifier)
                          .select(c['id'] as String),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
