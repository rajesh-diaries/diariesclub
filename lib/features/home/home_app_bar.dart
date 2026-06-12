import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/active_sessions_provider.dart';
import '../../core/providers/current_family_provider.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import 'widgets/notification_inbox_sheet.dart';
import 'widgets/top_up_sheet.dart';

/// AppBar for the Home tab.
/// Avatar (left → /profile) · wallet pill (centre-right → top-up sheet)
/// · bell with unread badge (right → inbox).
class HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _openInbox(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationInboxSheet(),
    );
  }

  void _openTopUp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TopUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    final balancePaise = ref.watch(walletBalancePaiseProvider);
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final sessions = ref.watch(activeSessionsProvider).valueOrNull ?? const [];

    final familyName = (family?['name'] as String?) ?? '';
    final firstName = familyName.isEmpty ? 'there' : familyName.split(' ').first;
    final hasActive = sessions.any((s) => s['status'] == 'active');
    final tagline = hasActive ? 'Play time is here!' : "Let's get the kids playing!";

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hey $firstName!',
            style: AppTextStyles.bodyLarge(context)
                .copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            tagline,
            style: AppTextStyles.caption(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        _WalletPill(
          balancePaise: balancePaise,
          onTap: () => _openTopUp(context),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: 'Notifications',
            onPressed: () => _openInbox(context),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  PhosphorIconsRegular.bell,
                  color: AppColors.navy,
                  size: 26,
                ),
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 15,
                        minHeight: 15,
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

/// Always-visible wallet balance pill — gold-tinted, star icon + amount.
/// Tap → opens the Top-up sheet. Renders "₹—" while the wallet provider
/// is still loading so we never flash an incorrect zero balance.
class _WalletPill extends StatelessWidget {
  final int? balancePaise;
  final VoidCallback onTap;
  const _WalletPill({required this.balancePaise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = balancePaise == null ? '₹—' : Money.fromPaise(balancePaise!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.50),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsFill.star,
                color: AppColors.gold,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.caption(context, color: AppColors.navy)
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
