import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/utils/currency.dart';
import 'providers/staff_auth_provider.dart';
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
    // BUG-031 final: StaffAppBar is now a plain StatelessWidget that
    // accepts the device label as a constructor param. The screen reads
    // the provider once here and passes the resolved label in. This
    // decouples the AppBar from Riverpod rebuilds, which the bisect
    // identified as the source of the body-tap-absorbing behaviour
    // on Flutter web.
    final device = ref.watch(currentTabletDeviceProvider).valueOrNull;
    final deviceLabel = device?['device_label'] as String?;

    return Scaffold(
      appBar: StaffAppBar(deviceLabel: deviceLabel),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatsBar(),
            SizedBox(height: 24),
            _ActionsGrid(),
            SizedBox(height: 24),
            _EndShiftCta(),
          ],
        ),
      ),
    );
  }
}

class _StatsBar extends ConsumerWidget {
  const _StatsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // Surface provider errors visibly so RLS/network failures don't
    // silently degrade tiles to "0". Loading shows an inline spinner.
    final errors = asyncs.where((e) => e.$2.hasError).toList();
    if (errors.isNotEmpty) {
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
    // BUG-030 fix: bumped border + soft shadow + accent top stripe so the
    // tiles are visibly distinct from the page background (lightSurface
    // on lightBackground was ~20 RGB points of contrast — easy to miss
    // on a glossy phone screen, especially with all-zero values for a
    // fresh dev account).
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(
          color: AppColors.lightTextSecondary.withValues(alpha: 0.20),
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 3, color: color),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
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
    // BUG-031 v1 fallback: 3×3 card grid with custom InkWell/GestureDetector
    // shapes consistently triggered tap-absorbing hit-test issues on Flutter
    // web. After 10 fix attempts, BUG-031 was deferred to v1.1; the polished
    // card grid lands then. For v1 staff app to be functional, this falls
    // back to a Column of plain Material ListTile rows — the most-tested
    // tappable widget in Flutter, very unlikely to hit the same hit-test
    // pathology. Same 9 actions, same routes, same PIN gating.
    return Column(
      children: [
        _ActionTile(
          icon: PhosphorIconsRegular.qrCode,
          label: 'Scan QR',
          onTap: () => _withPin(
            context,
            actionLabel: 'Scan session QR',
            route: '/staff/qr',
          ),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.phoneCall,
          label: 'Manual session',
          onTap: () => _withPin(
            context,
            actionLabel: 'Create manual session',
            route: '/staff/manual',
          ),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.clock,
          label: 'Active sessions',
          onTap: () => context.push('/staff/sessions'),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.cookingPot,
          label: 'Kitchen (KDS)',
          onTap: () => context.push('/staff/kds'),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.carrot,
          label: 'Healthy Bite',
          onTap: () => context.push('/staff/healthy-bite'),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.arrowUUpLeft,
          label: 'Refund',
          onTap: () => _withPin(
            context,
            actionLabel: 'Issue refund',
            route: '/staff/refund',
          ),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.cashRegister,
          label: 'Walk-in POS',
          onTap: () => _withPin(
            context,
            actionLabel: 'Walk-in cash checkout',
            route: '/staff/walkin',
          ),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.toggleRight,
          label: 'Menu availability',
          onTap: () => context.push('/staff/menu'),
        ),
        _ActionTile(
          icon: PhosphorIconsRegular.fileText,
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

/// BUG-031 fallback row. Plain Material ListTile — most-tested tappable
/// pattern in Flutter. Polished _ActionCard returns in v1.1.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lightSurface,
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(label, style: AppTextStyles.bodyLarge(context)),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.lightTextSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
        onTap: onTap,
      ),
    );
  }
}

// _ActionCard (3×3 grid card variant) removed pending BUG-031 v1.1
// resolution. Restore from git history (commit 59c8e50) when the
// underlying Flutter web hit-test issue is understood.

class _EndShiftCta extends StatelessWidget {
  const _EndShiftCta();
  @override
  Widget build(BuildContext context) {
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
