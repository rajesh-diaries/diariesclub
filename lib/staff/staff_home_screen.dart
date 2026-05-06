import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'providers/staff_auth_provider.dart';
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
