import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/profile_history_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'widgets/empty_state.dart';

/// Workshops attended. Empty state pushes the user toward Club /
/// Workshops where future sessions will surface (Session 7).
class PastWorkshopsScreen extends ConsumerWidget {
  const PastWorkshopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pastWorkshopsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshops'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const ProfileEmptyState(
            icon: PhosphorIconsRegular.paintBrush,
            message: "We couldn't load workshops. Try again in a moment.",
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const ProfileEmptyState(
                icon: PhosphorIconsRegular.paintBrush,
                message:
                    "No workshops yet. Discover what's coming up →",
                ctaLabel: 'See workshops',
                ctaRoute: '/club',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(pastWorkshopsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.lightBorder),
                itemBuilder: (_, i) => _Row(reg: rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> reg;
  const _Row({required this.reg});

  @override
  Widget build(BuildContext context) {
    final ws = (reg['workshops'] as Map?) ?? const {};
    final title = (ws['title'] as String?) ?? 'Workshop';
    final scheduledAt = ws['scheduled_at'] as String?;
    final dateStr = scheduledAt == null
        ? '—'
        : DateFormat('MMM d, yyyy')
            .format(DateTime.parse(scheduledAt).toLocal());
    final attended = reg['attended'] == true;

    return ListTile(
      leading: const Icon(
        PhosphorIconsRegular.paintBrush,
        color: AppColors.xpPurple,
      ),
      title: Text(title, style: AppTextStyles.body(context)),
      subtitle: Text(
        attended ? '$dateStr · attended' : dateStr,
        style: AppTextStyles.caption(
          context,
          color: AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}
