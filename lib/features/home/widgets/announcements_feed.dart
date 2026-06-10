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
class AnnouncementsFeed extends ConsumerStatefulWidget {
  const AnnouncementsFeed({super.key});

  @override
  ConsumerState<AnnouncementsFeed> createState() => _AnnouncementsFeedState();
}

class _AnnouncementsFeedState extends ConsumerState<AnnouncementsFeed> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_announcementsStreamProvider);
    final rows = async.valueOrNull ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 110,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: rows.length,
              itemBuilder: (_, i) => _AnnouncementBanner(row: rows[i]),
            ),
          ),
          if (rows.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(rows.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _currentPage == i ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? AppColors.navy
                        : AppColors.lightBorder,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> row;
  const _AnnouncementBanner({required this.row});

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

    final bgGradient = switch (type) {
      'promo' => const LinearGradient(
          colors: [Color(0xFFFFF9E6), Color(0xFFFFF3CC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      'workshop' => const LinearGradient(
          colors: [Color(0xFFF0F4FF), Color(0xFFE2EBF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      'event' => const LinearGradient(
          colors: [Color(0xFFF0FFF4), Color(0xFFE6F5EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      _ => const LinearGradient(
          colors: [Color(0xFFF7FBFF), Color(0xFFEDF3FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: ctaRoute == null || ctaRoute.isEmpty
            ? null
            : () => context.go(ctaRoute),
        child: Container(
          decoration: BoxDecoration(
            gradient: bgGradient,
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            type.toUpperCase(),
                            style: AppTextStyles.caption(
                              context,
                              color: accent,
                            ).copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: AppTextStyles.bodyLarge(context).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body != null && body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (ctaLabel != null && ctaLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ctaLabel,
                              style: AppTextStyles.caption(
                                context,
                                color: accent,
                              ).copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              PhosphorIconsRegular.arrowRight,
                              size: 12,
                              color: accent,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (photo != null && photo.isNotEmpty)
                SizedBox(
                  width: 100,
                  height: double.infinity,
                  child: Image.network(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: accent.withValues(alpha: 0.10),
                    ),
                  ),
                ),
            ],
          ),
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
