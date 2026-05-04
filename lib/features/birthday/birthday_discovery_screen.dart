import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/providers/upcoming_birthdays_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/child_avatar.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/reservation_providers.dart';
import 'widgets/journey_progress_bar.dart';

/// Birthday discovery hub. Hero section with the closest-upcoming child,
/// the journey progress bar, the "see packages" CTA, and a help link.
/// If the user already has an active reservation for any child we
/// redirect to the status screen for that reservation — discovery is
/// only for parents not yet in the funnel.
class BirthdayDiscoveryScreen extends ConsumerWidget {
  const BirthdayDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming =
        ref.watch(upcomingBirthdaysProvider).valueOrNull ?? const [];
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final reservations =
        ref.watch(familyReservationsProvider).valueOrNull ?? const [];

    // If any child has an active reservation, jump to its status screen
    // — discovery is only meaningful pre-reservation.
    final activeReservation = reservations.firstWhere(
      (r) {
        final status = r['status'] as String?;
        return status == 'interested' ||
            status == 'admin_contacted' ||
            status == 'confirmed' ||
            (status == 'completed' && r['album_ready_at'] == null);
      },
      orElse: () => const <String, dynamic>{},
    );
    if (activeReservation.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go('/birthday/status/${activeReservation['id']}');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final upcomingBirthday =
        upcoming.isEmpty ? null : upcoming.first;
    final selectedChild = upcomingBirthday?.child ??
        (children.isEmpty ? null : children.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Birthday'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selectedChild != null)
                _Hero(
                  child: selectedChild,
                  daysUntil: upcomingBirthday?.daysUntil,
                ),
              const SizedBox(height: 16),
              if (upcomingBirthday != null)
                JourneyProgressBar(daysUntil: upcomingBirthday.daysUntil),
              const SizedBox(height: 16),
              _MainCta(
                childName: (selectedChild?['name'] as String?) ?? 'your child',
              ),
              const SizedBox(height: 16),
              const _PackagesTeaser(),
              const SizedBox(height: 16),
              const _HelpRow(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Map<String, dynamic> child;
  final int? daysUntil;
  const _Hero({required this.child, required this.daysUntil});

  @override
  Widget build(BuildContext context) {
    final name = (child['name'] as String?) ?? '—';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.85),
            AppColors.rafiCoral.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: ChildAvatar(
              name: name,
              size: 80,
              photoPath: child['photo_url'] as String?,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "$name's birthday",
            style: AppTextStyles.h1(context, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            daysUntil == null
                ? 'Plan ahead — celebrate with us'
                : daysUntil! == 0
                    ? 'Today!'
                    : "$daysUntil day${daysUntil == 1 ? '' : 's'} to go",
            style: AppTextStyles.body(
              context,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MainCta extends StatelessWidget {
  final String childName;
  const _MainCta({required this.childName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Plan $childName's birthday with us",
            style: AppTextStyles.h3(context),
          ),
          const SizedBox(height: 4),
          Text(
            '3 packages, every detail handled.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'See packages',
              onPressed: () => context.push('/birthday/packages'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagesTeaser extends StatelessWidget {
  const _PackagesTeaser();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tier in const ['Basics', 'Hero Adventure', 'Legendary']) ...[
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.lightBackground,
                border: Border.all(color: AppColors.lightBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(
                    PhosphorIconsFill.cake,
                    color: AppColors.gold,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tier,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
          ),
          if (tier != 'Legendary') const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            PhosphorIconsRegular.chatCircleText,
            color: AppColors.navy,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Have questions? Tap a package to see what is included, or reach our team via WhatsApp from the help screen.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
