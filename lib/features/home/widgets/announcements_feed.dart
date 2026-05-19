import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Customer-side announcements section. Realtime stream from the
/// announcements table; the table's RLS already filters to
/// is_published+visible. We additionally cap to top 5 and sort by
/// type-priority (workshop > promo > event > general > closure) then
/// recency.
class AnnouncementsFeed extends ConsumerWidget {
  const AnnouncementsFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_announcementsStreamProvider);
    final rows = async.valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    // Top margin baked in so this widget pulls its own 16px gap when
    // it renders content; no phantom gap when it auto-hides. Internal
    // cards stacked with 12px between them, no trailing space.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _AnnouncementCard(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AnnouncementCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final title = (row['title'] as String?) ?? '';
    final body = row['body'] as String?;
    final ctaLabel = row['cta_label'] as String?;
    final ctaRoute = row['cta_route'] as String?;
    final photo = row['photo_url'] as String?;
    final type = (row['type'] as String?) ?? 'general';

    final accent = switch (type) {
      'workshop' => AppColors.navy,
      'promo' => AppColors.gold,
      'event' => AppColors.activeGreen,
      'closure' => AppColors.adminRed,
      _ => AppColors.lightTextSecondary,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      // context.go (not push): some cta_routes target shell-tab paths
      // like /club/workshops whose redirect lands on the /club shell
      // branch. push() on a shell branch path silently keeps you on the
      // current branch (Home); go() correctly switches branches.
      onTap: ctaRoute == null || ctaRoute.isEmpty
          ? null
          : () => context.go(ctaRoute),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo != null && photo.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.network(
                  photo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type.toUpperCase(),
                        style: AppTextStyles.caption(
                          context,
                          color: accent,
                        ).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(title, style: AppTextStyles.h3(context)),
                  if (body != null && body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: AppTextStyles.body(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (ctaLabel != null && ctaLabel.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          ctaLabel,
                          style: AppTextStyles.body(
                            context,
                            color: accent,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          PhosphorIconsRegular.arrowRight,
                          size: 14,
                          color: accent,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Realtime stream of active announcements, capped at 5 and ordered by
/// type priority + recency. Sorting happens client-side because Supabase
/// `.stream()` does not support arbitrary CASE expressions in order_by.
final _announcementsStreamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  const order = {
    'workshop': 1,
    'promo': 2,
    'event': 3,
    'general': 4,
    'closure': 5,
  };
  final stream = Supabase.instance.client
      .from('announcements')
      .stream(primaryKey: ['id']);

  await for (final rows in stream) {
    final now = DateTime.now();
    final filtered = rows.where((r) {
      if (r['is_published'] != true) return false;
      final from = DateTime.tryParse((r['visible_from'] as String?) ?? '');
      if (from == null || from.isAfter(now)) return false;
      final until = DateTime.tryParse((r['visible_until'] as String?) ?? '');
      if (until != null && until.isBefore(now)) return false;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final pa = order[a['type'] as String?] ?? 99;
      final pb = order[b['type'] as String?] ?? 99;
      final byType = pa.compareTo(pb);
      if (byType != 0) return byType;
      final ca = DateTime.tryParse((a['created_at'] as String?) ?? '') ?? now;
      final cb = DateTime.tryParse((b['created_at'] as String?) ?? '') ?? now;
      return cb.compareTo(ca);
    });
    yield filtered.take(5).toList();
  }
});
