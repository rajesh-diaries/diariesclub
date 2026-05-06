// BUG-023 candidate D state: body is intentionally a minimum-viable
// Center>Column>Text. Original widgets (_StatsBar, _ActionsGrid,
// _EndShiftCta) are kept in this file but temporarily unreferenced so
// we can rewire fast once we know which one throws.
// ignore_for_file: unused_element

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
    // BUG-023 fix candidate D — minimum viable body. Logs from candidate C
    // showed `Null check operator used on a null value` thrown repeatedly
    // from rendering/box.dart + rendering/sliver_mul (ListView's sliver
    // pipeline). That's a build-time crash, not a layout pathology — one
    // of the body subwidgets (_StatsBar / _ActionsGrid / _EndShiftCta) is
    // throwing during build, which Flutter swallows and renders nothing.
    // Body replaced with three plain Text widgets to test the hypothesis.
    // If THIS renders, the bug is in one of the three custom widgets and
    // we bisect tomorrow. If this is also blank, the failure is higher in
    // the tree (StaffApp shell, MediaQuery wrapper, theme).
    return const Scaffold(
      appBar: StaffAppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CANDIDATE D',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text('If you see this, body renders fine.'),
            SizedBox(height: 8),
            Text('Bug is in _StatsBar / _ActionsGrid / _EndShiftCta.'),
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

  static const double _cellHeight = 112;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    // BUG-023 fix candidate B: replaced GridView.count(shrinkWrap, NeverScroll)
    // with a manual Column of three Rows. GridView's sliver/viewport internals
    // collapsed to zero content on Vivo Funtouch Android 15 inside a ListView
    // (and previously inside a SingleChildScrollView). Pure RenderBox layout
    // (Column + Row + Expanded + SizedBox) is deterministic and avoids the
    // sliver path entirely.
    final cards = <_ActionCard>[
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
    ];

    Widget rowOf3(int start) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _gap),
        child: SizedBox(
          height: _cellHeight,
          child: Row(
            children: [
              Expanded(child: cards[start]),
              const SizedBox(width: _gap),
              Expanded(child: cards[start + 1]),
              const SizedBox(width: _gap),
              Expanded(child: cards[start + 2]),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        rowOf3(0),
        rowOf3(3),
        rowOf3(6),
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
