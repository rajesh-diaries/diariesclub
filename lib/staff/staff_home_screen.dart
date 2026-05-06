import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import 'providers/venue_streams_provider.dart';
import 'widgets/staff_app_bar.dart';
import 'widgets/staff_pin_sheet.dart';

/// Staff home dashboard. Top stats bar (live counts), then a 3×3 grid of
/// quick actions, then the End Shift CTA at the bottom. PIN-gated routes
/// open the PIN sheet first; non-gated routes navigate immediately.
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[BUG-023-V4] StaffHomeScreen.build()');
    // BUG-023 V4 — restore original body, wrap each child in a coloured
    // border so we can see WHICH child fails to paint. Border visible →
    // child has non-zero size. Border missing → child collapsed.
    return Scaffold(
      appBar: const StaffAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.20),
                  border: Border.all(color: Colors.deepOrange, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'DEBUG: BUG-023 V4 body entry — coloured borders mark each child',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _DebugWrap(
                label: 'STATS_BAR',
                color: Colors.red,
                child: _StatsBar(),
              ),
              const SizedBox(height: 16),
              const _DebugWrap(
                label: 'ACTIONS_GRID',
                color: Colors.blue,
                child: _ActionsGrid(),
              ),
              const SizedBox(height: 16),
              const _DebugWrap(
                label: 'END_SHIFT',
                color: Colors.green,
                child: _EndShiftCta(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// BUG-023 V4 helper — wraps a child in a coloured border + label header
/// so we can see which children are rendering at zero size on the device.
/// Remove once root cause is found.
class _DebugWrap extends StatelessWidget {
  final String label;
  final Color color;
  final Widget child;
  const _DebugWrap({
    required this.label,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[BUG-023-V4] _DebugWrap($label).build()');
    return Container(
      decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _StatsBar extends ConsumerWidget {
  const _StatsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[BUG-023-V4] _StatsBar.build()');
    final activeAsync = ref.watch(venueActiveSessionsProvider);
    final ordersAsync = ref.watch(venueOrdersProvider);
    final todayAsync = ref.watch(todaySessionsCountProvider);
    final cashAsync = ref.watch(todayCashCollectedProvider);

    final asyncs = <(String, AsyncValue<dynamic>)>[
      ('venueActiveSessions', activeAsync),
      ('venueOrders', ordersAsync),
      ('todaySessionsCount', todayAsync),
      ('todayCashCollected', cashAsync),
    ];

    // BUG-023 diagnostic — surface provider errors visibly instead of
    // swallowing them via `valueOrNull ?? 0`. Remove the explicit
    // error/loading branches once root cause is found and revert to
    // the prior render path.
    final errors = asyncs.where((e) => e.$2.hasError).toList();
    if (errors.isNotEmpty) {
      debugPrint(
        '[BUG-023-V4] _StatsBar errors: '
        '${errors.map((e) => "${e.$1}=${e.$2.error}").join(", ")}',
      );
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.adminRed.withValues(alpha: 0.10),
          border:
              Border.all(color: AppColors.adminRed.withValues(alpha: 0.40)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stats provider errors:',
              style: AppTextStyles.body(context, color: AppColors.adminRed)
                  .copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            for (final (name, async) in errors)
              Text(
                '• $name: ${async.error}',
                style:
                    AppTextStyles.caption(context, color: AppColors.adminRed),
              ),
          ],
        ),
      );
    }

    final allLoading = asyncs.every((e) => e.$2.isLoading);
    if (allLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading stats…',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final activeSessions = activeAsync.valueOrNull?.length ?? 0;
    final pendingOrders = ordersAsync.valueOrNull?.length ?? 0;
    final todaySessions = todayAsync.valueOrNull ?? 0;
    final cashPaise = cashAsync.valueOrNull ?? 0;

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Active',
            value: '$activeSessions',
            color: AppColors.activeGreen,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Today',
            value: '$todaySessions',
            color: AppColors.navy,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Pending',
            value: '$pendingOrders',
            color: AppColors.gold,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Cash',
            value: Money.fromPaise(cashPaise),
            color: AppColors.activeGreen,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTextStyles.h2(context, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsGrid extends StatelessWidget {
  const _ActionsGrid();

  @override
  Widget build(BuildContext context) {
    debugPrint('[BUG-023-V4] _ActionsGrid.build()');
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        _ActionCard(
          icon: PhosphorIconsFill.qrCode,
          label: 'Scan QR',
          onTap: () => _withPin(
            context,
            actionLabel: 'Scan session QR',
            route: '/staff/qr',
          ),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.phoneCall,
          label: 'Manual session',
          onTap: () => _withPin(
            context,
            actionLabel: 'Create manual session',
            route: '/staff/manual',
          ),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.clock,
          label: 'Active sessions',
          onTap: () => context.push('/staff/sessions'),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.cookingPot,
          label: 'Kitchen (KDS)',
          onTap: () => context.push('/staff/kds'),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.carrot,
          label: 'Healthy Bite',
          onTap: () => context.push('/staff/healthy-bite'),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.arrowUUpLeft,
          label: 'Refund',
          onTap: () => _withPin(
            context,
            actionLabel: 'Issue refund',
            route: '/staff/refund',
          ),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.cashRegister,
          label: 'Walk-in POS',
          onTap: () => _withPin(
            context,
            actionLabel: 'Walk-in cash checkout',
            route: '/staff/walkin',
          ),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.toggleRight,
          label: 'Menu availability',
          onTap: () => context.push('/staff/menu'),
        ),
        _ActionCard(
          icon: PhosphorIconsFill.fileText,
          label: 'Audit log',
          onTap: () => context.push('/staff/audit'),
        ),
      ],
    );
  }

  Future<void> _withPin(
    BuildContext context, {
    required String actionLabel,
    required String route,
  }) async {
    final staff = await StaffPinSheet.show(context, actionLabel: actionLabel);
    if (staff == null) return;
    if (!context.mounted) return;
    context.push(route, extra: {'staffId': staff.staffId});
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: AppColors.navy),
            const SizedBox(height: 12),
            Text(
              label,
              style: AppTextStyles.bodyLarge(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EndShiftCta extends StatelessWidget {
  const _EndShiftCta();
  @override
  Widget build(BuildContext context) {
    debugPrint('[BUG-023-V4] _EndShiftCta.build()');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.moon, color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'End shift & reconcile cash',
              style: AppTextStyles.bodyLarge(context),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
            onPressed: () async {
              final staff = await StaffPinSheet.show(
                context,
                actionLabel: 'End shift',
              );
              if (staff == null) return;
              if (!context.mounted) return;
              context.push(
                '/staff/shift-close',
                extra: {'staffId': staff.staffId},
              );
            },
            child: const Text('End shift'),
          ),
        ],
      ),
    );
  }
}
