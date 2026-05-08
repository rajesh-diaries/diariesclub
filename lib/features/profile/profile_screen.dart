import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_theme_mode_provider.dart';
import '../../core/providers/current_family_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/current_wallet_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../../core/widgets/error_screen.dart';
import '../home/widgets/top_up_sheet.dart';
import 'widgets/children_list.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_nav_row.dart';
import 'widgets/profile_section.dart';
import 'widgets/referral_card.dart';
import 'widgets/theme_selector_sheet.dart';

/// Tab 4 — single sectioned Profile screen (iOS Settings style). Most
/// rows just navigate; everything reactive (header, children, wallet
/// balance) reads from Realtime providers.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(currentFamilyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: familyAsync.when(
        data: (_) => const _Body(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-PROF',
          userMessage: "Couldn't load profile",
          technicalDetails: e.toString(),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      children: const [
        ProfileHeader(),
        ReferralCard(),

        ProfileSectionHeader(title: 'Family'),
        ChildrenList(),

        ProfileSectionHeader(title: 'Wallet'),
        _WalletSection(),

        ProfileSectionHeader(title: 'Diaries Coins'),
        _CoinsSection(),

        ProfileSectionHeader(title: 'Activity'),
        _ActivitySection(),

        ProfileSectionHeader(title: 'Settings'),
        _SettingsSection(),

        ProfileSectionHeader(title: 'Support'),
        _SupportSection(),

        ProfileSectionHeader(title: 'Account'),
        _AccountSection(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Wallet section
// ---------------------------------------------------------------------------
class _WalletSection extends ConsumerWidget {
  const _WalletSection();

  void _topUp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TopUpSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletBalancePaiseProvider);
    return ProfileSectionCard(
      children: [
        ListTile(
          leading: const Icon(
            PhosphorIconsRegular.wallet,
            color: AppColors.navy,
          ),
          title: Text('Balance', style: AppTextStyles.body(context)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                balance == null ? '—' : Money.fromPaise(balance),
                style: AppTextStyles.bodyLarge(context),
              ),
              const SizedBox(width: 12),
              // Material+InkWell instead of FilledButton — FilledButton
              // inside ListTile.trailing > Row(min) silently asserts on
              // Flutter web (same root cause as BUG-039a).
              Material(
                color: AppColors.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _topUp(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      'Top up',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const ProfileNavRow(
          label: 'History',
          route: '/profile/wallet-history',
          leading: PhosphorIconsRegular.clockCounterClockwise,
        ),
        const ProfileNavRow(
          label: 'Pre-book a session',
          route: '/profile/pre-book',
          leading: PhosphorIconsRegular.calendarPlus,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Coins section
// ---------------------------------------------------------------------------
class _CoinsSection extends ConsumerStatefulWidget {
  const _CoinsSection();

  @override
  ConsumerState<_CoinsSection> createState() => _CoinsSectionState();
}

class _CoinsSectionState extends ConsumerState<_CoinsSection> {
  bool _busy = false;

  Future<void> _redeem(int amount) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Redeem coins?'),
        content: Text(
          'Convert $amount Diaries Coins → ₹$amount in your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .rpc<dynamic>('coins_redeem', params: {'p_amount': amount});
      ref.invalidate(currentWalletProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Redeemed $amount coins → ₹$amount')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message.contains('min_redeem_100')
          ? 'You need at least 100 coins to redeem.'
          : e.message.contains('insufficient_coins')
              ? "You don't have that many coins."
              : "Couldn't redeem: ${e.message}";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't redeem: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(currentWalletProvider).valueOrNull;
    final coinsBalance = (wallet?['coins_balance'] as int?) ?? 0;
    final coinsLifetime = (wallet?['coins_lifetime'] as int?) ?? 0;
    final canRedeem = coinsBalance >= 100;

    return ProfileSectionCard(
      children: [
        ListTile(
          leading: const Icon(
            PhosphorIconsFill.coin,
            color: AppColors.gold,
          ),
          title: Text('Available coins',
              style: AppTextStyles.body(context)),
          subtitle: Text(
            canRedeem
                ? '1 coin = ₹1 · tap Redeem to add to wallet'
                : 'Earn ${100 - coinsBalance} more to redeem (min 100)',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          trailing: Text(
            '$coinsBalance',
            style: AppTextStyles.h3(context, color: AppColors.gold),
          ),
        ),
        if (coinsLifetime > 0)
          ListTile(
            leading: const Icon(
              PhosphorIconsRegular.trophy,
              color: AppColors.lightTextSecondary,
            ),
            title:
                Text('Lifetime earned', style: AppTextStyles.body(context)),
            trailing: Text(
              '$coinsLifetime',
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!canRedeem || _busy) ? null : () => _redeem(coinsBalance),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      canRedeem
                          ? 'Redeem $coinsBalance coins → ₹$coinsBalance'
                          : 'Redeem coins (min 100)',
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Activity section
// ---------------------------------------------------------------------------
class _ActivitySection extends StatelessWidget {
  const _ActivitySection();

  @override
  Widget build(BuildContext context) {
    return const ProfileSectionCard(
      children: [
        ProfileNavRow(
          label: 'Past sessions',
          route: '/profile/sessions',
          leading: PhosphorIconsRegular.timer,
        ),
        ProfileNavRow(
          label: 'Past orders',
          route: '/profile/orders',
          leading: PhosphorIconsRegular.coffee,
        ),
        ProfileNavRow(
          label: 'Workshops attended',
          route: '/profile/workshops',
          leading: PhosphorIconsRegular.paintBrush,
        ),
        ProfileNavRow(
          label: 'Birthday parties',
          route: '/profile/birthdays',
          leading: PhosphorIconsRegular.cake,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Settings section
// ---------------------------------------------------------------------------
class _SettingsSection extends ConsumerWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return ProfileSectionCard(
      children: [
        ProfileActionRow(
          label: 'Theme',
          leading: PhosphorIconsRegular.palette,
          trailing: _themeLabel(mode),
          onTap: () {
            showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => const ThemeSelectorSheet(),
            );
          },
        ),
        const ProfileNavRow(
          label: 'Notifications',
          route: '/profile/notifications-settings',
          leading: PhosphorIconsRegular.bell,
        ),
        const ProfileNavRow(
          label: 'Language',
          route: '/profile/language',
          trailing: 'English',
          leading: PhosphorIconsRegular.translate,
        ),
      ],
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

// ---------------------------------------------------------------------------
//  Support section
// ---------------------------------------------------------------------------
class _SupportSection extends ConsumerWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final whatsapp = (cfg['whatsapp_support_phone'] as String?) ?? '';
    final phone = (cfg['support_phone'] as String?) ?? whatsapp;

    final waNum = whatsapp.replaceAll(RegExp(r'[^\d]'), '');
    final waUrl = waNum.isEmpty
        ? 'https://wa.me/'
        : 'https://wa.me/$waNum?text=${Uri.encodeComponent("Hi, I need help with Diaries Club.")}';

    return ProfileSectionCard(
      children: [
        const ProfileNavRow(
          label: 'Help & FAQ',
          route: '/profile/help',
          leading: PhosphorIconsRegular.question,
        ),
        ProfileExternalRow(
          label: 'Talk to us on WhatsApp',
          leading: PhosphorIconsRegular.whatsappLogo,
          url: waUrl,
        ),
        if (phone.isNotEmpty)
          ProfileExternalRow(
            label: 'Call us',
            leading: PhosphorIconsRegular.phone,
            url: 'tel:$phone',
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Account section — privacy / terms / refund / version / sign out / delete
// ---------------------------------------------------------------------------
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version}+${info.buildNumber}');
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll need to enter your phone number again to sign back in.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    debugPrint('[SIGNOUT] dialog confirmed, awaiting endOfFrame');
    // Let dialog pop animation fully settle before we trigger anything
    // that touches the navigator.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    debugPrint('[SIGNOUT] clearing prefs + secure storage');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_otp_phone');
      await const FlutterSecureStorage().deleteAll();
    } catch (_) {
      debugPrint('[SIGNOUT] prefs/secure-storage error');
    }
    debugPrint('[SIGNOUT] calling Supabase.signOut');
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      debugPrint('[SIGNOUT] Supabase.signOut error');
    }
    debugPrint('[SIGNOUT] signOut complete — listener should redirect now');
    // Defensive fallback: if the auth listener didn't trigger redirect
    // within 1 frame, navigate explicitly via the router provider (which
    // bypasses BuildContext lifecycle).
    await WidgetsBinding.instance.endOfFrame;
    if (Supabase.instance.client.auth.currentUser == null) {
      debugPrint('[SIGNOUT] still on profile — forcing router.go');
      ref.read(appRouterProvider).go('/auth/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final privacy = (cfg['privacy_policy_url'] as String?) ?? '';
    final terms = (cfg['terms_of_service_url'] as String?) ?? '';
    final refund = (cfg['refund_policy_url'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileSectionCard(
            children: [
              if (privacy.isNotEmpty)
                ProfileExternalRow(label: 'Privacy Policy', url: privacy),
              if (terms.isNotEmpty)
                ProfileExternalRow(label: 'Terms', url: terms),
              if (refund.isNotEmpty)
                ProfileExternalRow(label: 'Refund Policy', url: refund),
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.info,
                  color: AppColors.navy,
                ),
                title: Text('App version', style: AppTextStyles.body(context)),
                trailing: Text(
                  _version.isEmpty ? '—' : _version,
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _confirmSignOut,
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/profile/delete-account'),
            child: Text(
              'Delete account',
              style: AppTextStyles.body(context, color: AppColors.adminRed),
            ),
          ),
        ],
      ),
    );
  }
}
