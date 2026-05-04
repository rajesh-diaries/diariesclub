import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/upcoming_birthdays_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Persistent Home card for any child whose birthday is within 90 days.
/// Stacks one card per matching child. Once a reservation exists, the card
/// morphs to show the booking summary instead of the planning CTA.
class BirthdayCardList extends ConsumerWidget {
  const BirthdayCardList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final birthdays = ref.watch(upcomingBirthdaysProvider).valueOrNull ?? [];
    if (birthdays.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final b in birthdays) ...[
          _BirthdayCard(birthday: b),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _BirthdayCard extends StatelessWidget {
  final UpcomingBirthday birthday;
  const _BirthdayCard({required this.birthday});

  @override
  Widget build(BuildContext context) {
    final name = (birthday.child['name'] as String?) ?? 'Your child';
    final reservation = birthday.reservation;
    final hasReservation = reservation != null;

    final title = hasReservation
        ? "$name's party is coming up!"
        : "$name's birthday";

    final subtitle = hasReservation
        ? _reservationSubtitle(reservation)
        : (birthday.daysUntil == 0
            ? 'Today!'
            : '${birthday.daysUntil} day${birthday.daysUntil == 1 ? "" : "s"} to go');

    final ctaLabel = hasReservation ? 'View status →' : 'Plan the party →';
    final destination = hasReservation
        ? '/birthday/status/${reservation['id']}'
        : '/birthday';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push(destination),
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
                  Text(title,
                      style:
                          AppTextStyles.h3(context, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.body(
                      context,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ctaLabel,
                    style: AppTextStyles.caption(
                      context,
                      color: Colors.white,
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

  String _reservationSubtitle(Map<String, dynamic> r) {
    final dateStr = r['slot_date'] as String?;
    final timeStr = r['slot_start_time'] as String?;
    if (dateStr == null || timeStr == null) return 'Reserved';
    final date = DateTime.parse(dateStr);
    return '${DateFormat('EEEE MMM d').format(date)}, $timeStr';
  }
}
