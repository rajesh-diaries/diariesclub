import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/family_children_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import 'providers/birthday_packages_provider.dart';
import 'providers/reservation_providers.dart';

const _supportPhone = '919876543210';

/// Reservation status — Realtime stream from `reservation_by_id_provider`.
/// Renders the status header, a summary card, the pipeline timeline, an
/// action block, and (depending on state) "add to calendar", a "view album"
/// button, or a "cancel" link. Status flips happen within seconds because
/// the table is in supabase_realtime.
class ReservationStatusScreen extends ConsumerWidget {
  final String reservationId;
  const ReservationStatusScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reservationByIdProvider(reservationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your reservation'),
        // BUG-011: explicit back arrow with web-safe fallback. The default
        // auto-leading uses Navigator.pop, which no-ops on web hash-routes
        // when this page is the entry point (refresh or push notification
        // deep link).
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Don't fall back to /birthday — the discovery screen
          // auto-redirects back to this same status page when the
          // family has an active reservation, so the user appeared
          // stuck. /home is the right escape hatch.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final reservation = async.valueOrNull;
              if (v == 'help') {
                _openWhatsApp();
              } else if (v == 'cancel' && reservation != null) {
                await _confirmCancel(context, reservation);
              }
            },
            // BUG-013: only expose Cancel on pre-confirmation states. Anything
            // past 'confirmed' goes through the admin refund flow — admin
            // contacts customer on WhatsApp (not surfaced in app).
            itemBuilder: (_) {
              final status = async.valueOrNull?['status'] as String?;
              final cancellable =
                  status == 'interested' || status == 'admin_contacted';
              return [
                const PopupMenuItem(value: 'help', child: Text('Get help')),
                if (cancellable)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Cancel reservation'),
                  ),
              ];
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-BSTAT',
          userMessage: "Couldn't load this reservation",
          technicalDetails: e.toString(),
        ),
        data: (r) {
          if (r == null) {
            return const FriendlyErrorScreen(
              code: 'E-BSTAT-404',
              userMessage: "We couldn't find this reservation.",
            );
          }
          return _StatusBody(reservation: r);
        },
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    Map<String, dynamic> r,
  ) async {
    // BUG-013 spec: bottom-sheet with Keep it / Yes, cancel buttons. No
    // free-text reason field; backend hardcodes cancelled_reason.
    final shouldCancel = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cancel this reservation?', style: AppTextStyles.h2(c)),
              const SizedBox(height: 8),
              Text(
                'You can submit again anytime.',
                style: AppTextStyles.body(
                  c,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: const Text('Keep it'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.adminRed,
                      ),
                      onPressed: () => Navigator.of(c).pop(true),
                      child: const Text('Yes, cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (shouldCancel != true || !context.mounted) return;

    try {
      await Supabase.instance.client.rpc<dynamic>(
        'birthday_reservation_cancel',
        params: {'p_reservation_id': r['id']},
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation cancelled')),
      );
      // Replace stack — back from /birthday should not return to a stale
      // status screen showing the now-cancelled reservation.
      context.go('/birthday');
    } on PostgrestException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't cancel. Please try again.")),
      );
    }
  }

  void _openWhatsApp() {
    launchUrl(Uri.parse('https://wa.me/$_supportPhone'));
  }
}

class _StatusBody extends ConsumerWidget {
  final Map<String, dynamic> reservation;
  const _StatusBody({required this.reservation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? const [];
    final child = children.firstWhere(
      (c) => c['id'] == reservation['child_id'],
      orElse: () => const <String, dynamic>{},
    );
    final childName = (child['name'] as String?) ?? 'Your child';

    final pkgAsync = ref.watch(
      birthdayPackageByIdProvider(reservation['package_id'] as String),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusHeader(reservation: reservation, childName: childName),
          _SummaryCard(
            reservation: reservation,
            packageName: pkgAsync.valueOrNull?['name'] as String?,
          ),
          _PipelineTimeline(reservation: reservation),
          _ActionCard(reservation: reservation),
          if (reservation['status'] == 'confirmed')
            _PartyDetailsCard(reservation: reservation),
          const _ContactCard(),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final Map<String, dynamic> reservation;
  final String childName;
  const _StatusHeader({required this.reservation, required this.childName});

  @override
  Widget build(BuildContext context) {
    final spec = _resolveSpec(reservation, childName);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: spec.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Icon(spec.icon, color: Colors.white, size: 44),
          const SizedBox(height: 12),
          Text(
            spec.title,
            style: AppTextStyles.h2(context, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          if (spec.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              spec.subtitle!,
              style: AppTextStyles.body(
                context,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  _HeaderSpec _resolveSpec(Map<String, dynamic> r, String name) {
    final status = r['status'] as String?;
    final albumReady = r['album_ready_at'] != null;
    final isToday = _isPartyToday(r);

    return switch (status) {
      'interested' => _HeaderSpec(
          gradient: [
            AppColors.gold.withValues(alpha: 0.92),
            AppColors.rafiCoral.withValues(alpha: 0.85),
          ],
          icon: PhosphorIconsFill.envelope,
          title: 'Reservation request received',
          subtitle: "We'll WhatsApp you within 24 hours.",
        ),
      'admin_contacted' => const _HeaderSpec(
          gradient: [Color(0xFF2A4A8B), AppColors.navy],
          icon: PhosphorIconsFill.chatCircleText,
          title: 'Our team has reached out',
          subtitle: 'Check your WhatsApp for details.',
        ),
      'confirmed' when isToday => _HeaderSpec(
          gradient: [AppColors.gold, AppColors.rafiCoral],
          icon: PhosphorIconsFill.cake,
          title: "It's $name's birthday!",
          subtitle: 'See you at the venue.',
        ),
      'confirmed' => _HeaderSpec(
          gradient: [
            AppColors.activeGreen.withValues(alpha: 0.85),
            AppColors.gold.withValues(alpha: 0.85),
          ],
          icon: PhosphorIconsFill.checkCircle,
          title: "You're confirmed!",
          subtitle: 'Date locked. See party details below.',
        ),
      'completed' when albumReady => const _HeaderSpec(
          gradient: [AppColors.gold, AppColors.activeGreen],
          icon: PhosphorIconsFill.gift,
          title: 'A little memory from us',
          subtitle: 'Tap below to open it.',
        ),
      'completed' => _HeaderSpec(
          gradient: [
            AppColors.lightTextSecondary.withValues(alpha: 0.55),
            AppColors.navy.withValues(alpha: 0.75),
          ],
          icon: PhosphorIconsFill.confetti,
          title: 'Thank you for celebrating',
          subtitle: 'A small keepsake is on its way.',
        ),
      'cancelled' => const _HeaderSpec(
          gradient: [
            AppColors.lightTextSecondary,
            AppColors.lightTextSecondary,
          ],
          icon: PhosphorIconsFill.xCircle,
          title: 'Reservation cancelled',
          subtitle: null,
        ),
      'no_show' => const _HeaderSpec(
          gradient: [
            AppColors.lightTextSecondary,
            AppColors.lightTextSecondary,
          ],
          icon: PhosphorIconsFill.xCircle,
          title: 'Reservation closed',
          subtitle: null,
        ),
      _ => const _HeaderSpec(
          gradient: [AppColors.navy, AppColors.navy],
          icon: PhosphorIconsFill.cake,
          title: 'Reservation',
          subtitle: null,
        ),
    };
  }

  bool _isPartyToday(Map<String, dynamic> r) {
    final dateStr = r['slot_date'] as String?;
    if (dateStr == null) return false;
    try {
      final d = DateTime.parse(dateStr);
      final now = DateTime.now();
      return d.year == now.year && d.month == now.month && d.day == now.day;
    } catch (_) {
      return false;
    }
  }
}

class _HeaderSpec {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String? subtitle;
  const _HeaderSpec({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> reservation;
  final String? packageName;
  const _SummaryCard({required this.reservation, required this.packageName});

  @override
  Widget build(BuildContext context) {
    final guestCount = reservation['num_kids'] as int? ?? 0;
    final slotDate = reservation['slot_date'] as String?;
    final slot = reservation['slot'] as String?;
    final special = reservation['special_requests'] as String?;
    // Backwards-compat for older rows that still have preferred_month/window.
    final preferredMonth = reservation['preferred_month'] as String?;
    final preferredWindow = reservation['preferred_window'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (packageName != null)
            _Row(label: 'Package', value: packageName!),
          if (slotDate != null && slotDate.isNotEmpty)
            _Row(label: 'Date', value: slotDate),
          if (slot != null && slot.isNotEmpty)
            _Row(label: 'Slot', value: slot[0].toUpperCase() + slot.substring(1)),
          if (slotDate == null && preferredMonth != null)
            _Row(label: 'Preferred month', value: preferredMonth),
          if (slotDate == null && preferredWindow != null)
            _Row(label: 'Preferred time', value: _humanizeWindow(preferredWindow)),
          _Row(label: 'Guests', value: '$guestCount approx.'),
          if (special != null && special.isNotEmpty)
            _Row(label: 'Special requests', value: special),
        ],
      ),
    );
  }

  String _humanizeWindow(String key) => switch (key) {
        'weekend_morning' => 'Weekend morning',
        'weekend_afternoon' => 'Weekend afternoon',
        'weekend_evening' => 'Weekend evening',
        'weekday_evening' => 'Weekday evening',
        _ => key,
      };
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(context)),
          ),
        ],
      ),
    );
  }
}

class _PipelineTimeline extends StatelessWidget {
  final Map<String, dynamic> reservation;
  const _PipelineTimeline({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final status = reservation['status'] as String? ?? '';
    final hasAlbum = reservation['album_ready_at'] != null;

    final steps = <(String, String?)>[
      ('Interest received', null),
      ('Team reaching out', null),
      ('Date confirmed', null),
      ('Party day', null),
      ('A little memory', 'A small keepsake from us, after the party'),
    ];

    final currentIndex = switch (status) {
      'interested' => 0,
      'admin_contacted' => 1,
      'confirmed' => 2,
      'completed' => hasAlbum ? 4 : 3,
      _ => -1,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _PipelineStep(
              label: steps[i].$1,
              hint: steps[i].$2,
              isPast: i < currentIndex,
              isCurrent: i == currentIndex,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _PipelineStep extends StatelessWidget {
  final String label;
  final String? hint;
  final bool isPast;
  final bool isCurrent;
  final bool isLast;
  const _PipelineStep({
    required this.label,
    required this.hint,
    required this.isPast,
    required this.isCurrent,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPast || isCurrent
        ? AppColors.gold
        : AppColors.lightBorder;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isCurrent
                      ? Border.all(color: AppColors.gold, width: 4)
                      : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isPast ? AppColors.gold : AppColors.lightBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body(
                      context,
                      color: isPast || isCurrent
                          ? null
                          : AppColors.lightTextSecondary,
                    ).copyWith(
                      fontWeight:
                          isCurrent ? FontWeight.w800 : FontWeight.w400,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final Map<String, dynamic> reservation;
  const _ActionCard({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final status = reservation['status'] as String?;
    final albumReady = reservation['album_ready_at'] != null;

    final body = switch (status) {
      'interested' =>
        "We'll WhatsApp you within 24 hours to confirm available dates.",
      'admin_contacted' =>
        'Our team has been in touch. Check your WhatsApp for the next steps.',
      'confirmed' =>
        'See party details below. Bring the cake — we handle the rest.',
      'completed' when albumReady => 'Tap below to open your keepsake.',
      'completed' =>
        "We'll send a push when your little memory is ready.",
      _ => null,
    };
    if (body == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.05),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.10)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body, style: AppTextStyles.body(context)),
          if (status == 'completed' && albumReady) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Open keepsake',
              onPressed: () =>
                  context.push('/birthday/album/${reservation['id']}'),
            ),
          ],
          if (status == 'confirmed') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(PhosphorIconsRegular.calendar),
              label: const Text('Add to calendar'),
              onPressed: () => _addToCalendar(context, reservation),
            ),
          ],
        ],
      ),
    );
  }

  void _addToCalendar(BuildContext context, Map<String, dynamic> r) {
    final dateStr = r['slot_date'] as String?;
    final start = r['slot_start_time'] as String?;
    if (dateStr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date not yet locked.')),
      );
      return;
    }
    final ymd = dateStr.replaceAll('-', '');
    final hm = (start ?? '11:00').replaceAll(':', '').padRight(6, '0');
    final url = Uri.parse(
      'https://www.google.com/calendar/render'
      '?action=TEMPLATE'
      '&text=Birthday+at+Diaries+Club'
      '&dates=${ymd}T$hm/${ymd}T$hm',
    );
    launchUrl(url);
  }
}

class _PartyDetailsCard extends StatelessWidget {
  final Map<String, dynamic> reservation;
  const _PartyDetailsCard({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final dateStr = reservation['slot_date'] as String?;
    final start = reservation['slot_start_time'] as String?;
    final end = reservation['slot_end_time'] as String?;

    String when;
    if (dateStr != null) {
      try {
        final d = DateTime.parse(dateStr);
        when = DateFormat('EEEE, MMM d').format(d);
        if (start != null) when = '$when · $start${end != null ? ' – $end' : ''}';
      } catch (_) {
        when = dateStr;
      }
    } else {
      when = reservation['preferred_month'] as String? ?? 'Date pending';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.calendarStar,
              color: AppColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Party day', style: AppTextStyles.caption(context)),
                Text(when, style: AppTextStyles.bodyLarge(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsRegular.chatCircleText,
              color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Need to change something? WhatsApp our team.',
              style: AppTextStyles.body(context),
            ),
          ),
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse('https://wa.me/$_supportPhone')),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
