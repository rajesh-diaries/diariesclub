import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/family_children_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ist_dates.dart';
import '../../birthday/providers/reservation_providers.dart';

/// Persistent Home cards for birthday journeys. Two layers stacked
/// vertically:
///
///   1. Per-child reservation cards. One card per child with an active
///      birthday_reservation (interested → admin_contacted → confirmed →
///      completed/album_ready). Variant is reservation-status-driven.
///
///   2. ONE residual card (BUG-018) representing the family's
///      no-reservation state. Two flavours:
///        - Rich: at least one child has interest_state='interested' AND
///          days_until_birthday <= venue_config.birthday_home_card_
///          threshold_days (default 30). Shows the closest-upcoming such
///          child with the existing gradient style and "Plan the party →".
///        - Discovery: anything else (no children, all opted out,
///          threshold exceeded). Lighter outlined card with "Explore
///          birthday packages →".
///
///      The residual card is suppressed only when EVERY child already has
///      an active reservation — at that point the per-child status cards
///      cover the full state and a discovery prompt would be redundant.
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
    final venueCfg = ref.watch(venueConfigProvider).valueOrNull;
    final thresholdDays =
        (venueCfg?['birthday_home_card_threshold_days'] as int?) ?? 30;

    final today = IstDates.istDate(DateTime.now().toUtc());
    final reservationEntries = <_CardEntry>[];
    final unengaged = <_UnengagedChild>[];

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

      final activeReservation = reservations.firstWhere(
        (r) =>
            r['child_id'] == child['id'] &&
            r['status'] != 'cancelled' &&
            r['status'] != 'cancelled_by_customer' &&
            r['status'] != 'no_show',
        orElse: () => const <String, dynamic>{},
      );

      if (activeReservation.isNotEmpty) {
        final variant = _resolveActiveVariant(
          status: activeReservation['status'] as String? ?? '',
          albumReady: activeReservation['album_ready_at'] != null,
          daysUntil: daysUntil,
        );
        if (variant != _Variant.hidden) {
          reservationEntries.add(_CardEntry(
            child: child,
            reservation: activeReservation,
            daysUntil: daysUntil,
            variant: variant,
          ));
        }
      } else {
        unengaged.add(_UnengagedChild(child: child, daysUntil: daysUntil));
      }
    }

    // BUG-018 residual card: at most one, for the family's no-reservation
    // state. Suppressed when every child has a reservation already.
    Widget? residualCard;
    if (children.isEmpty || unengaged.isNotEmpty) {
      final richEligible = unengaged
          .where((u) {
            final state = (u.child['birthday_interest_state'] as String?) ??
                'interested';
            return state == 'interested' &&
                u.daysUntil >= 0 &&
                u.daysUntil <= thresholdDays;
          })
          .toList()
        ..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

      if (richEligible.isNotEmpty) {
        final closest = richEligible.first;
        residualCard = _RichBirthdayCard(
          child: closest.child,
          daysUntil: closest.daysUntil,
        );
      } else {
        residualCard = const _DiscoveryBirthdayCard();
      }
    }

    if (reservationEntries.isEmpty && residualCard == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        for (final e in reservationEntries) ...[
          _BirthdayCardTile(entry: e),
          const SizedBox(height: 12),
        ],
        if (residualCard != null) residualCard,
      ],
    );
  }

  static _Variant _resolveActiveVariant({
    required String status,
    required bool albumReady,
    required int daysUntil,
  }) =>
      switch (status) {
        'interested' => _Variant.interestSubmitted,
        'admin_contacted' => _Variant.adminContacted,
        'confirmed' =>
          daysUntil <= 1 ? _Variant.tomorrow : _Variant.confirmed,
        'completed' =>
          albumReady ? _Variant.albumReady : _Variant.albumPending,
        _ => _Variant.hidden,
      };
}

enum _Variant {
  hidden,
  interestSubmitted,
  adminContacted,
  confirmed,
  tomorrow,
  albumPending,
  albumReady,
}

class _CardEntry {
  final Map<String, dynamic> child;
  final Map<String, dynamic> reservation;
  final int daysUntil;
  final _Variant variant;
  const _CardEntry({
    required this.child,
    required this.reservation,
    required this.daysUntil,
    required this.variant,
  });
}

class _UnengagedChild {
  final Map<String, dynamic> child;
  final int daysUntil;
  const _UnengagedChild({required this.child, required this.daysUntil});
}

class _BirthdayCardTile extends StatelessWidget {
  final _CardEntry entry;
  const _BirthdayCardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final name = (entry.child['name'] as String?) ?? 'Your child';
    final r = entry.reservation;
    final spec = _styleFor(name: name, daysUntil: entry.daysUntil, r: r);

    final destination = entry.variant == _Variant.albumReady
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
    required Map<String, dynamic> r,
  }) {
    switch (entry.variant) {
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
          gradient: const [AppColors.gold, AppColors.rafiCoral],
          icon: PhosphorIconsFill.cake,
          title: daysUntil <= 0
              ? "It's $name's birthday!"
              : "$name's party tomorrow!",
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
          gradient: const [AppColors.gold, AppColors.activeGreen],
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

  String _confirmedSubtitle(Map<String, dynamic> r) {
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

/// BUG-018 rich variant — closest-upcoming child with interest='interested'
/// and days_until_birthday within the venue threshold. Same gradient
/// language as the previous "prompting" card so the visual treatment for
/// "your kid's birthday is near, plan it with us" is consistent.
class _RichBirthdayCard extends StatelessWidget {
  final Map<String, dynamic> child;
  final int daysUntil;
  const _RichBirthdayCard({required this.child, required this.daysUntil});

  @override
  Widget build(BuildContext context) {
    final name = (child['name'] as String?) ?? 'Your child';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/birthday'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.85),
              AppColors.rafiCoral.withValues(alpha: 0.75),
            ],
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
              child: const Icon(
                PhosphorIconsFill.cake,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$name's birthday",
                    style: AppTextStyles.h3(context, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    daysUntil == 0
                        ? 'Today!'
                        : '$daysUntil day${daysUntil == 1 ? "" : "s"} to go',
                    style: AppTextStyles.body(
                      context,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plan the party →',
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
}

/// BUG-018 discovery variant — lighter outlined card surfaced when no
/// rich-eligible child exists (or no children at all). Deliberately less
/// prominent than rich/reservation cards so it doesn't compete for
/// attention when other content is on the home screen.
class _DiscoveryBirthdayCard extends StatelessWidget {
  const _DiscoveryBirthdayCard();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/birthday'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsFill.cake,
                color: AppColors.gold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Explore birthday packages →',
                    style: AppTextStyles.body(context).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Plan a party at Play Diaries',
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
      ),
    );
  }
}
