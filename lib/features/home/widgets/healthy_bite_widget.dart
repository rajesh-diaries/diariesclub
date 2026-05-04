import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Pulsing card shown when the latest completed session has
/// `healthy_bite_earned=true` AND `healthy_bite_distributed=false`.
///
/// Distribution itself is staff-side (Session 10). For now: "Show" deep-
/// links to a bite-only QR (placeholder route) and "I got it" optimistically
/// flips `healthy_bite_distributed=true` so the card disappears.
class HealthyBiteWidget extends ConsumerStatefulWidget {
  const HealthyBiteWidget({super.key});

  @override
  ConsumerState<HealthyBiteWidget> createState() => _HealthyBiteWidgetState();
}

class _HealthyBiteWidgetState extends ConsumerState<HealthyBiteWidget> {
  Future<void> _markGot(String sessionId) async {
    try {
      await Supabase.instance.client
          .from('sessions')
          .update({'healthy_bite_distributed': true}).eq('id', sessionId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update. Try again later.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyId = ref.watch(currentFamilyIdProvider);
    if (familyId == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('sessions')
          .select('id, child_id, children(name)')
          .eq('family_id', familyId)
          .eq('healthy_bite_earned', true)
          .eq('healthy_bite_distributed', false)
          .order('completed_at', ascending: false)
          .limit(1),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final row = snap.data!.first;
        final childName =
            ((row['children'] as Map?)?['name'] as String?) ?? 'Your child';
        final sessionId = row['id'] as String;

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
                      'Show this at the FIT counter',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _markGot(sessionId),
                child: const Text('I got it'),
              ),
            ],
          ),
        );
      },
    );
  }
}
