import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Informational card shown on home when a session has
/// `healthy_bite_earned=true` AND `healthy_bite_distributed=false`.
///
/// Realtime via supabase stream — the moment staff confirms distribution
/// (the unified healthy_bite_distribute RPC sets distributed=true and
/// claimed_at=now()), this widget hides itself automatically.
///
/// History note: this used to have an "I got it" button that flipped
/// distributed=true client-side. That was always RLS-blocked (customer
/// JWT can't write that column) AND was architecturally wrong — under
/// the v2 model (BUG-044, migration 0046), distribution is a staff RPC
/// that mints a card and credits +20 XP. A customer self-mark would
/// skip both. The button has been removed; the widget is purely
/// informational.
class HealthyBiteWidget extends ConsumerWidget {
  const HealthyBiteWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyId = ref.watch(currentFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('sessions')
          .stream(primaryKey: ['id'])
          .eq('family_id', familyId)
          .order('started_at', ascending: false),
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        // Newest pending bite for this family; cap at the last 24h so a
        // forgotten session from days ago doesn't ride along indefinitely.
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        Map<String, dynamic>? row;
        for (final r in rows) {
          if (r['healthy_bite_earned'] != true) continue;
          if (r['healthy_bite_distributed'] == true) continue;
          final startedRaw = r['started_at'] as String?;
          final started = startedRaw == null
              ? null
              : DateTime.tryParse(startedRaw);
          if (started == null || started.isBefore(cutoff)) continue;
          row = r;
          break;
        }
        if (row == null) return const SizedBox.shrink();

        final childId = row['child_id'] as String?;
        return _Body(childId: childId);
      },
    );
  }
}

class _Body extends StatelessWidget {
  final String? childId;
  const _Body({required this.childId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: childId == null
          ? Future.value(null)
          : Supabase.instance.client
              .from('children')
              .select('name')
              .eq('id', childId!)
              .maybeSingle(),
      builder: (context, snap) {
        final childName = (snap.data?['name'] as String?) ?? 'Your child';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.fitGreen.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.fitGreen),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                PhosphorIconsFill.carrot,
                color: AppColors.fitGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$childName earned a Healthy Bite!',
                      style: AppTextStyles.bodyLarge(context),
                    ),
                    Text(
                      'Show this at the FIT counter — staff will hand it over.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
