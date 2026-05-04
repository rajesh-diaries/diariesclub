import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ist_dates.dart';
import '../../birthday/providers/reservation_providers.dart';

/// Persistent Home cards for each child whose birthday journey is active.
/// Renders one card per child, stacking vertically. Variants per child
/// are resolved from (status, days-until, album_ready_at) — see
/// `_resolveVariant` below.
///
/// Both inputs (children + reservations) are Realtime: card variants
/// flip the moment admin moves a reservation forward.
class BirthdayCardList extends ConsumerWidget {
  const BirthdayCardList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final reservations =
        ref.watch(familyReservationsProvider).valueOrNull ?? const [];
    if (children.isEmpty) return const SizedBox.shrink();

    final today = IstDates.istDate(DateTime.now().toUtc());
    final entries = <_CardEntry>[];

    for (final child in children) {
      final dobRaw = child['date_of_birth'] as String?;
      if (dobRaw == null) continue;
      final dob = DateTime.parse(dobRaw);

      // Next birthday (this year's, or next year's if already passed today).
      var nextBday = DateTime(today.year, dob.month, dob.day);
      if (nextBday.isBefore(DateTime(today.year, today.month, today.day))) {
        nextBday = DateTime(today.year + 1, dob.month, dob.day);
      }
      final daysUntil = nextBday
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;

      // Most recent reservation for this child that's not cancelled/no_show.
      final activeReservation = reservations.firstWhere(
        (r) =>
            r['child_id'] == child['id'] &&
            r['status'] != 'cancelled' &&
            r['status'] != 'no_show',
        orElse: () => const <String, dynamic>{},
      );

      final variant = _resolveVariant(
        reservation: activeReservation.isEmpty ? null : activeReservation,
        daysUntil: daysUntil,
      );
      if (variant == _Variant.hidden) continue;

      entries.add(_CardEntry(
        child: child,
        reservation: activeReservation.isEmpty ? null : activeReservation,
        daysUntil: daysUntil,
        variant: variant,
      ));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final e in entries) ...[
          _BirthdayCardTile(entry: e),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  static _Variant _resolveVariant({
    required Map<String, dynamic>? reservation,
    required int daysUntil,
  }) {
    if (reservation == null) {
      // No reservation: only prompt if the birthday is in the upcoming
      // 90 days. Otherwise the card disappears.
      if (daysUntil < 0 || daysUntil > 90) return _Variant.hidden;
      return _Variant.prompting;
    }
    final status = reservation['status'] as String? ?? '';
    final albumReady = reservation['album_ready_at'] != null;
    return switch (status) {
      'interested' => _Variant.interestSubmitted,
      'admin_contacted' => _Variant.adminContacted,
      'confirmed' => daysUntil <= 1 ? _Variant.tomorrow : _Variant.confirmed,
      'completed' =>
        albumReady ? _Variant.albumReady : _Variant.albumPending,
      _ => _Variant.hidden,
    };
  }
}

enum _Variant {
  hidden,
  prompting,
  interestSubmitted,
  adminContacted,
  confirmed,
  tomorrow,
  albumPending,
  albumReady,
}

class _CardEntry {
  final Map<String, dynamic> child;
  final Map<String, dynamic>? reservation;
  final int daysUntil;
  final _Variant variant;
  const _CardEntry({
    required this.child,
    required this.reservation,
    required this.daysUntil,
    required this.variant,
  });
}

class _BirthdayCardTile extends StatelessWidget {
  final _CardEntry entry;
  const _BirthdayCardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final name = (entry.child['name'] as String?) ?? 'Your child';
    final r = entry.reservation;

    final spec = _styleFor(name: name, daysUntil: entry.daysUntil, r: r);

    final destination = r == null
        ? '/birthday'
        : entry.variant == _Variant.albumReady
            ? '/birthday/album/${r['id']}'
            : '/birthday/status/${r['id']}';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push(destination),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: spec.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.30),
                shape: BoxShape.circle,
              ),
              child: Icon(spec.icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    style: AppTextStyles.h3(context, color: Colors.white),
                  ),
                  if (spec.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      spec.subtitle,
                      style: AppTextStyles.body(
                        context,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    spec.cta,
                    style: AppTextStyles.caption(context, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _CardSpec _styleFor({
    required String name,
    required int daysUntil,
    required Map<String, dynamic>? r,
  }) {
    switch (entry.variant) {
      case _Variant.prompting:
        return _CardSpec(
          gradient: [
            AppColors.gold.withValues(alpha: 0.85),
            AppColors.rafiCoral.withValues(alpha: 0.75),
          ],
          icon: PhosphorIconsFill.cake,
          title: "$name's birthday",
          subtitle: daysUntil == 0
              ? 'Today!'
              : '$daysUntil day${daysUntil == 1 ? "" : "s"} to go',
          cta: 'Plan the party →',
        );
      case _Variant.interestSubmitted:
        return const _CardSpec(
          gradient: [Color(0xFF2A4A8B), AppColors.navy],
          icon: PhosphorIconsFill.envelope,
          title: 'Reservation request received',
          subtitle: "We'll WhatsApp you within 24 hours.",
          cta: 'View status →',
        );
      case _Variant.adminContacted:
        return const _CardSpec(
          gradient: [Color(0xFF2A4A8B), AppColors.navy],
          icon: PhosphorIconsFill.chatCircleText,
          title: 'Talking with our team',
          subtitle: 'Check WhatsApp for the details.',
          cta: 'View status →',
        );
      case _Variant.confirmed:
        return _CardSpec(
          gradient: [
            AppColors.activeGreen.withValues(alpha: 0.85),
            AppColors.gold.withValues(alpha: 0.85),
          ],
          icon: PhosphorIconsFill.checkCircle,
          title: "$name's party is confirmed!",
          subtitle: _confirmedSubtitle(r),
          cta: 'View details →',
        );
      case _Variant.tomorrow:
        return _CardSpec(
          gradient: [
            AppColors.gold,
            AppColors.rafiCoral,
          ],
          icon: PhosphorIconsFill.cake,
          title: daysUntil <= 0 ? "It's $name's birthday!" : "$name's party tomorrow!",
          subtitle: 'See you soon!',
          cta: 'View details →',
        );
      case _Variant.albumPending:
        return _CardSpec(
          gradient: [
            AppColors.lightTextSecondary.withValues(alpha: 0.40),
            AppColors.navy.withValues(alpha: 0.60),
          ],
          icon: PhosphorIconsFill.images,
          title: 'Thank you for celebrating',
          subtitle: 'Photos coming in 3-5 days.',
          cta: 'View status →',
        );
      case _Variant.albumReady:
        return _CardSpec(
          gradient: [
            AppColors.gold,
            AppColors.activeGreen,
          ],
          icon: PhosphorIconsFill.images,
          title: "$name's album is ready!",
          subtitle: 'Tap to relive the moments.',
          cta: 'View album →',
        );
      case _Variant.hidden:
        return const _CardSpec(
          gradient: [Colors.transparent, Colors.transparent],
          icon: PhosphorIconsFill.cake,
          title: '',
          subtitle: '',
          cta: '',
        );
    }
  }

  String _confirmedSubtitle(Map<String, dynamic>? r) {
    if (r == null) return '';
    final dateStr = r['slot_date'] as String?;
    final timeStr = r['slot_start_time'] as String?;
    if (dateStr != null && timeStr != null) {
      final d = DateTime.parse(dateStr);
      return '${DateFormat('EEE MMM d').format(d)} · $timeStr';
    }
    final preferredMonth = r['preferred_month'] as String?;
    return preferredMonth ?? 'Date locked';
  }
}

class _CardSpec {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  const _CardSpec({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
  });
}
