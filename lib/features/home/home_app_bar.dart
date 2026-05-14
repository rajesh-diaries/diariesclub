import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    final family = ref.watch(currentFamilyProvider).valueOrNull;
    final initials = _initials(family?['name'] as String?);
    final unread = ref.watch(unreadNotificationCountProvider);
    final balancePaise = ref.watch(walletBalancePaiseProvider);

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 16,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.gold.withValues(alpha: 0.30),
              child: Text(
                initials,
                style: AppTextStyles.bodyLarge(
                  context,
                  color: AppColors.navy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Wordmark: "Diaries ★ Club" — gold star between the two words.
          // Sits next to the avatar so the brand reads at every Home open.
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
                letterSpacing: -0.2,
              ),
              children: [
                const TextSpan(text: 'Diaries '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Icon(
                      PhosphorIconsFill.star,
                      color: AppColors.gold,
                      size: 14,
                    ),
                  ),
                ),
                const TextSpan(text: ' Club'),
              ],
            ),
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
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.adminRed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
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

  String _initials(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return '?';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
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
                style: AppTextStyles.body(context, color: AppColors.navy)
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
