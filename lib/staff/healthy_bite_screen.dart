import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/staff_auth_provider.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_pin_sheet.dart';

/// Healthy Bite decisions for the staff at this venue.
///
/// Two tabs:
///   * Pending — undecided sessions in the last 4h. Give / Didn't give
///     buttons go through StaffPinSheet, then drop off the list.
///   * Given today — sessions where a bite was already handed out in
///     the last 24h. Read-only review so staff can see their own
///     throughput and reconcile with the queue.
class HealthyBiteScreen extends ConsumerWidget {
  const HealthyBiteScreen({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/staff/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.navy,
          elevation: 0,
          title: const Text('Healthy Bite'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => _back(context),
          ),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(venuePendingHealthyBitesProvider);
                ref.invalidate(venueDistributedHealthyBitesProvider);
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.navy,
            unselectedLabelColor: AppColors.lightTextSecondary,
            indicatorColor: AppColors.navy,
            tabs: [
              Tab(icon: Icon(PhosphorIconsRegular.clock), text: 'Pending'),
              Tab(
                icon: Icon(PhosphorIconsRegular.checkCircle),
                text: 'Given today',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PendingTab(onBack: () => _back(context)),
            _DistributedTab(onBack: () => _back(context)),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
//  Pending tab — give / didn't-give decisions
// =========================================================================

class _PendingTab extends ConsumerWidget {
  final VoidCallback onBack;
  const _PendingTab({required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(venuePendingHealthyBitesProvider);
    final venueId = ref.watch(currentTabletVenueIdProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        e: '$e',
        onRetry: () => ref.invalidate(venuePendingHealthyBitesProvider),
        onBack: onBack,
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return _EmptyState(
            icon: PhosphorIconsRegular.carrot,
            title: 'Nothing pending right now',
            body:
                'Active sessions + completed-but-undecided sessions in the '
                'last 4 hours appear here. Tap refresh to check.',
            venueId: venueId,
            onBack: onBack,
          );
        }

        // Split: in-progress sessions (active/grace) and completed
        // sessions (completed/auto_closed). Staff sees both — active
        // rows are read-only (time remaining + bite-earned hint),
        // completed rows have the give / didn't-give buttons.
        final completed = rows
            .where((s) =>
                s['status'] == 'completed' || s['status'] == 'auto_closed')
            .toList();
        final live = rows
            .where(
                (s) => s['status'] == 'active' || s['status'] == 'grace')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (completed.isNotEmpty) ...[
              const _SectionHeader(
                icon: PhosphorIconsRegular.checkSquare,
                label: 'Awaiting decision',
              ),
              for (final s in completed) ...[
                _DecisionTile(
                  session: s,
                  onDone: () =>
                      ref.invalidate(venuePendingHealthyBitesProvider),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
            ],
            if (live.isNotEmpty) ...[
              const _SectionHeader(
                icon: PhosphorIconsRegular.timer,
                label: 'Active sessions',
              ),
              for (final s in live) ...[
                _ActiveSessionTile(session: s),
                const SizedBox(height: 12),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.lightTextSecondary),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.caption(
              context, color: AppColors.lightTextSecondary,
            ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionTile extends StatelessWidget {
  final Map<String, dynamic> session;
  const _ActiveSessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final childName =
        ((session['children'] as Map?)?['name'] as String?) ?? 'Child';
    final sessionShort =
        (session['id'] as String).substring(0, 6).toUpperCase();
    final status = session['status'] as String? ?? '?';
    final duration = session['duration_minutes'];
    final earned = (session['healthy_bite_earned'] as bool?) ?? false;
    final expiresAt =
        DateTime.tryParse(session['expires_at'] as String? ?? '');
    final remaining = expiresAt?.difference(DateTime.now()).inMinutes;

    String timeStr;
    Color timeColor;
    if (remaining == null) {
      timeStr = '—';
      timeColor = AppColors.lightTextSecondary;
    } else if (remaining > 0) {
      timeStr = '$remaining min left';
      timeColor = AppColors.navy;
    } else {
      timeStr = 'Wrapping up (${-remaining} min over)';
      timeColor = AppColors.warningYellow;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(
          color: status == 'grace'
              ? AppColors.warningYellow.withValues(alpha: 0.50)
              : AppColors.lightBorder,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: earned
              ? AppColors.fitGreen.withValues(alpha: 0.85)
              : AppColors.lightTextSecondary.withValues(alpha: 0.40),
          child: const Icon(PhosphorIconsFill.carrot, color: Colors.white),
        ),
        title: Text(childName, style: AppTextStyles.bodyLarge(context)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session $sessionShort · $duration-min · $status',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeStr,
                style: AppTextStyles.caption(context, color: timeColor)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: earned
                ? AppColors.fitGreen.withValues(alpha: 0.15)
                : AppColors.lightBorder.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            earned ? 'Bite earned' : 'Not yet',
            style: TextStyle(
              color:
                  earned ? AppColors.fitGreen : AppColors.lightTextSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
//  Given-today tab — read-only review of distributed bites
// =========================================================================

class _DistributedTab extends ConsumerWidget {
  final VoidCallback onBack;
  const _DistributedTab({required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(venueDistributedHealthyBitesProvider);
    final venueId = ref.watch(currentTabletVenueIdProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        e: '$e',
        onRetry: () =>
            ref.invalidate(venueDistributedHealthyBitesProvider),
        onBack: onBack,
      ),
      data: (rows) => rows.isEmpty
          ? _EmptyState(
              icon: PhosphorIconsRegular.checkCircle,
              title: 'Nothing given yet today',
              body:
                  "Sessions you mark as 'Gave bite' in the Pending tab "
                  'land here for the next 24h.',
              venueId: venueId,
              onBack: onBack,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _GivenTile(session: rows[i]),
            ),
    );
  }
}

class _GivenTile extends StatelessWidget {
  final Map<String, dynamic> session;
  const _GivenTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final childName =
        ((session['children'] as Map?)?['name'] as String?) ?? 'Child';
    final sessionShort =
        (session['id'] as String).substring(0, 6).toUpperCase();
    final duration = session['duration_minutes'];
    final claimed =
        DateTime.tryParse(session['healthy_bite_claimed_at'] as String? ?? '');
    final givenStr = claimed == null ? '—' : _hhmm(claimed.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.fitGreen.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: AppColors.fitGreen,
          child: Icon(
            PhosphorIconsFill.checkCircle,
            color: Colors.white,
          ),
        ),
        title: Text(childName, style: AppTextStyles.bodyLarge(context)),
        subtitle: Text(
          'Session $sessionShort · $duration-min · given at $givenStr',
          style: AppTextStyles.caption(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fitGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Given',
            style: TextStyle(
              color: AppColors.fitGreen,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
//  Shared widgets — empty state, error view, decision tile, time helper
// =========================================================================

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? venueId;
  final VoidCallback onBack;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.venueId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.lightTextSecondary),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              venueId == null
                  ? 'venue: (none — not signed in as staff?)'
                  : 'venue: ${venueId!.substring(0, 8)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to staff home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String e;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const _ErrorView({
    required this.e,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: AppColors.adminRed),
            const SizedBox(height: 12),
            Text("Couldn't load list",
                style: AppTextStyles.bodyLarge(context)),
            const SizedBox(height: 8),
            Text(e,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                )),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onBack,
              child: const Text('Back to staff home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onDone;
  const _DecisionTile({required this.session, required this.onDone});

  @override
  ConsumerState<_DecisionTile> createState() => _DecisionTileState();
}

class _DecisionTileState extends ConsumerState<_DecisionTile> {
  bool _busy = false;

  Future<void> _gave() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Give Healthy Bite + hero card (+25 XP)',
    );
    if (staff == null) return;
    setState(() => _busy = true);
    try {
      final raw = await Supabase.instance.client.rpc<dynamic>(
        'healthy_bite_distribute',
        params: {
          'p_session_id': widget.session['id'],
          'p_child_id': widget.session['child_id'],
          'p_staff_pin_id': staff.staffId,
        },
      );
      final result =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final cardName = result['card_name'] as String?;
      final isRare = result['is_rare'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.fitGreen,
          content: Text(
            cardName == null
                ? 'Healthy Bite given. +25 XP credited.'
                : 'Card given: $cardName${isRare ? ' (RARE!)' : ''}. +25 XP.',
          ),
        ),
      );
      // Refresh BOTH tabs so the row moves from Pending → Given today.
      ref.invalidate(venueDistributedHealthyBitesProvider);
      widget.onDone();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't give bite: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _didnt() async {
    final staff = await StaffPinSheet.show(
      context,
      actionLabel: 'Mark "did not take" — no XP, no card',
    );
    if (staff == null) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'healthy_bite_decline',
        params: {
          'p_session_id': widget.session['id'],
          'p_staff_pin_id': staff.staffId,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as not taken.')),
      );
      widget.onDone();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't update: ${e.message}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final childName =
        ((s['children'] as Map?)?['name'] as String?) ?? 'Child';
    final sessionShort =
        (s['id'] as String).substring(0, 6).toUpperCase();
    final status = s['status'] as String? ?? '?';
    final duration = s['duration_minutes'];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const CircleAvatar(
              backgroundColor: AppColors.gold,
              child: Icon(PhosphorIconsFill.carrot, color: Colors.white),
            ),
            title: Text(
              childName,
              style: AppTextStyles.bodyLarge(context),
            ),
            subtitle: Text(
              'Session $sessionShort · $duration-min · $status · '
              'started ${_started(s)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.lightBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _gave,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.fitGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Gave bite'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _didnt,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.lightTextSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side:
                          const BorderSide(color: AppColors.lightBorder),
                    ),
                    child: const Text("Didn't give"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _started(Map<String, dynamic> s) {
    final dt = DateTime.tryParse(s['started_at'] as String? ?? '')?.toLocal();
    if (dt == null) return '—';
    return _hhmm(dt);
  }
}

String _hhmm(DateTime dt) {
  final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
  return '$hour:${dt.minute.toString().padLeft(2, '0')}'
      ' ${dt.hour >= 12 ? 'PM' : 'AM'}';
}
