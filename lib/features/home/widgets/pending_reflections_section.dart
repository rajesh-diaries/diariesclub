import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/pending_reflections_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One reflection card per session awaiting reflection within the 24h
/// window. Renders nothing when the list is empty (no phantom gap).
class PendingReflectionsSection extends ConsumerWidget {
  const PendingReflectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingReflectionsProvider);
    final rows = async.valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              rows.length == 1 ? 'Reflect on the session' : 'Reflect on these sessions',
              style: AppTextStyles.h3(context),
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _ReflectionCard(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _ReflectionCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ReflectionCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final sessionId = row['id'] as String? ?? '';
    final child = (row['child'] as Map?)?.cast<String, dynamic>();
    final childName = (child?['name'] as String?) ?? '—';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/reflection/$sessionId'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _Avatar(name: childName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$childName had a session',
                    style: AppTextStyles.body(context).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Reflect to earn full XP',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reflect',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    PhosphorIconsFill.sparkle,
                    color: AppColors.gold,
                    size: 14,
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

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.gold.withValues(alpha: 0.20),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}
