import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/providers/upcoming_birthdays_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/child_avatar.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/reservation_providers.dart';

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
          // BUG-014: pop() no-ops on web hash-routes when this page was the
          // entry point (refresh or deep-link). Fall back to /home so the
          // user is never trapped.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
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
              // BUG-015: timeline only ever rendered when an active
              // reservation exists. Discovery is the no-reservation state
              // (page redirects away above when one is found), so the
              // timeline is intentionally absent here.
              if (selectedChild != null)
                _BirthdayInterestCard(child: selectedChild),
              const SizedBox(height: 16),
              const _MainCta(),
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
  const _MainCta();

  @override
  Widget build(BuildContext context) {
    // Heading deliberately omits the child's name — the hero card
    // immediately above this CTA already shows "$name's birthday"
    // and repeating the name reads as filler. (BUG-027)
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
            'Plan the celebration with us',
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

/// FEATURE-002: per-child birthday interest opt-out card. Two states:
/// 'interested' (default) and 'not_this_year'. Picking 'not_this_year'
/// fires the warm decline modal; the family-set RPC is idempotent so
/// re-tapping the same option is a no-op.
class _BirthdayInterestCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> child;
  const _BirthdayInterestCard({required this.child});

  @override
  ConsumerState<_BirthdayInterestCard> createState() =>
      _BirthdayInterestCardState();
}

class _BirthdayInterestCardState extends ConsumerState<_BirthdayInterestCard> {
  bool _busy = false;

  Future<void> _setState(String newState) async {
    if (_busy) return;
    final current =
        widget.child['birthday_interest_state'] as String? ?? 'interested';
    if (current == newState) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'family_set_birthday_interest',
        params: {
          'p_child_id': widget.child['id'],
          'p_interest_state': newState,
        },
      );
      if (!mounted) return;
      // Realtime stream on family_children_provider will reflect the new
      // state — no manual invalidate needed.
      if (newState == 'not_this_year') {
        await _showDeclineModal(
          context,
          (widget.child['name'] as String?) ?? 'your child',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Please try again.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.child['name'] as String?) ?? 'your child';
    final state =
        widget.child['birthday_interest_state'] as String? ?? 'interested';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Tell us about $name's birthday",
            style: AppTextStyles.h3(context),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: state,
            onChanged: (v) {
              if (_busy || v == null) return;
              _setState(v);
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'interested',
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Yes, we'd love to celebrate here",
                    style: AppTextStyles.body(context),
                  ),
                ),
                RadioListTile<String>(
                  value: 'not_this_year',
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Not this year, thanks',
                    style: AppTextStyles.body(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Warm acknowledgement when a customer opts out for the year. Deliberately
/// silent on the universal birthday wish (FEATURE-001) — the wish is a
/// surprise brand moment and shouldn't be foreshadowed here. Per-family
/// opt-out for the wish itself lives in Profile → Notifications.
///
/// Single Done CTA that routes to /home (replace stack). The customer
/// chose "Not this year" — give them one clear exit, don't push further
/// engagement on the way out.
Future<void> _showDeclineModal(BuildContext context, String childName) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No worries!',
              style: AppTextStyles.h2(sheetCtx),
            ),
            const SizedBox(height: 12),
            Text(
              '$childName is always part of our Play Diaries family — '
              'celebrate on!',
              style: AppTextStyles.body(sheetCtx),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Done',
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  sheetCtx.go('/home');
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
