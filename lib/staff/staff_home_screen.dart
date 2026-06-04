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

/// Staff home — BUG-031 v1.1 investigation move #1.
///
/// MaterialApp.router builder MediaQuery wrapper dropped in app_staff.dart
/// (commit pending). Body restored to a Column of interactive Material
/// ListTile rows. If taps fire on web now, we close BUG-031. If not, the
/// builder wasn't the absorber and we move to move #2 (bisect _StatsBar
/// stream subscriptions).
class StaffHomeScreen extends ConsumerWidget {
  const StaffHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(currentTabletDeviceProvider).valueOrNull;
    final deviceLabel = device?['device_label'] as String?;

    return Scaffold(
      appBar: StaffAppBar(deviceLabel: deviceLabel),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TodayPanel(),
            const SizedBox(height: 16),
            _ActionTile(
              icon: PhosphorIconsRegular.qrCode,
              label: 'Scan QR',
              // QR scan is a read-mostly operation (validates a session +
              // marks it scanned). It doesn't move money or change menu
              // pricing, so we skip the PIN gate to keep the floor flow
              // quick. The session row's staff_pin_id stays null for these
              // scans; the tablet_device_id on the audit log still ties
              // the action to a specific device.
              onTap: () => context.push('/staff/qr'),
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
              icon: PhosphorIconsRegular.ticket,
              label: 'Redeem perk code',
              onTap: () => context.push('/staff/redeem-perk'),
            ),
            _ActionTile(
              icon: PhosphorIconsRegular.graduationCap,
              label: 'Workshops · attendance',
              onTap: () => context.push('/staff/workshops'),
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
        ),
      ),
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

/// Today-at-a-glance dashboard panel — 4-tile grid of the must-see live
/// counters (on-floor, sessions, orders, cash) plus a pending-bites
/// alert banner that only appears when there's a queue.
class _TodayPanel extends ConsumerWidget {
  const _TodayPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onFloor = ref.watch(venueActiveSessionsProvider).valueOrNull?.length ?? 0;
    final sessionsToday = ref.watch(todaySessionsCountProvider).valueOrNull ?? 0;
    final bitesGiven =
        ref.watch(venueDistributedHealthyBitesProvider).valueOrNull?.length ?? 0;
    final bitesPending =
        ref.watch(venuePendingHealthyBitesProvider).valueOrNull?.length ?? 0;
    final cashPaise = ref.watch(todayCashCollectedProvider).valueOrNull ?? 0;
    final ordersToday = ref.watch(todayOrdersCountProvider).valueOrNull ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.gauge,
                  color: AppColors.navy, size: 18),
              const SizedBox(width: 6),
              Text(
                "Today's pulse",
                style: AppTextStyles.bodyLarge(context).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
                onPressed: () {
                  ref.invalidate(venueActiveSessionsProvider);
                  ref.invalidate(todaySessionsCountProvider);
                  ref.invalidate(venueDistributedHealthyBitesProvider);
                  ref.invalidate(venuePendingHealthyBitesProvider);
                  ref.invalidate(todayCashCollectedProvider);
                  ref.invalidate(todayOrdersCountProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Four-tile 2x2 grid — trimmed from six tiles 2026-05-21.
          // "Kids today" removed (redundant with Sessions today). "Bites
          // given" rolled into the carrot tile which now ONLY shows when
          // there are pending decisions, freeing screen space when the
          // queue is clear.
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: [
              _StatTile(
                icon: PhosphorIconsFill.users,
                label: 'On floor now',
                value: '$onFloor',
                accent: onFloor > 0
                    ? AppColors.fitGreen
                    : AppColors.lightTextSecondary,
                onTap: () => context.push('/staff/sessions'),
              ),
              _StatTile(
                icon: PhosphorIconsFill.clock,
                label: 'Sessions today',
                value: '$sessionsToday',
                accent: AppColors.navy,
                onTap: () => context.push('/staff/sessions'),
              ),
              _StatTile(
                icon: PhosphorIconsFill.cookingPot,
                label: 'Orders today',
                value: '$ordersToday',
                accent: AppColors.navy,
                onTap: () => context.push('/staff/kds'),
              ),
              _StatTile(
                icon: PhosphorIconsFill.currencyInr,
                label: 'Cash today',
                value: Money.fromPaise(cashPaise),
                accent: AppColors.gold,
              ),
            ],
          ),
          // Pending-bites alert lives below the grid as a full-width
          // banner — only renders when there's actually a queue, so it
          // disappears when staff has nothing to do.
          if (bitesPending > 0) ...[
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.push('/staff/healthy-bite'),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.10),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.40)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsFill.carrot,
                          color: AppColors.gold, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Healthy Bite · $bitesPending pending'
                          '${bitesGiven > 0 ? '  ·  $bitesGiven given today' : ''}',
                          style: AppTextStyles.body(context, color: AppColors.gold)
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(PhosphorIconsRegular.caretRight,
                          color: AppColors.gold, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: AppTextStyles.h3(context, color: accent),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
