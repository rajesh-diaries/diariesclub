import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_theme_mode_provider.dart';
import '../../core/providers/auth_provider.dart';
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

        ProfileSectionHeader(title: 'Adventure perks'),
        _HeroPerksSection(),

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
//  Hero perks section — stage transitions auto-generate redemption codes
// ---------------------------------------------------------------------------
class _HeroPerksSection extends ConsumerWidget {
  const _HeroPerksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(unredeemedHeroPerksProvider);
    return async.when(
      loading: () => const ProfileSectionCard(children: [
        ListTile(
          leading: SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Loading…'),
        ),
      ]),
      error: (_, __) => ProfileSectionCard(
        children: [
          ListTile(
            leading: const Icon(
              PhosphorIconsRegular.warningCircle,
              color: AppColors.lightTextSecondary,
            ),
            title: Text(
              "Couldn't load perks. Pull to retry.",
              style: AppTextStyles.body(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return ProfileSectionCard(
            children: [
              ListTile(
                leading: const Icon(
                  PhosphorIconsRegular.gift,
                  color: AppColors.lightTextSecondary,
                ),
                title: Text(
                  'No perks waiting',
                  style: AppTextStyles.body(context),
                ),
                subtitle: Text(
                  'Reach a new stage to unlock real-world rewards.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ],
          );
        }
        return ProfileSectionCard(
          children: [
            for (final r in rows) _PerkRow(row: r),
          ],
        );
      },
    );
  }
}

class _PerkRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PerkRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final perkId = row['perk_id'] as String?;
    if (perkId == null) {
      return _UnchosenPerkRow(row: row);
    }
    return _PickedPerkRow(row: row);
  }
}

class _PickedPerkRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PickedPerkRow({required this.row});

  String _stageTitle(String s) =>
      s.isEmpty ? '?' : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final code = (row['code'] as String?) ?? '';
    final label = (row['perk_label'] as String?) ?? 'Perk';
    final stage = (row['stage'] as String?) ?? '';
    final trait = (row['trait'] as String?) ?? '';
    final childName = (row['child_name'] as String?) ?? '';
    final expiresAt =
        DateTime.tryParse((row['expires_at'] as String?) ?? '');
    final daysLeft = expiresAt == null
        ? null
        : expiresAt.difference(DateTime.now()).inDays;
    final traitColor = _traitColor(trait);
    final traitName = _traitName(trait);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: traitColor.withValues(alpha: 0.20),
        ),
        child: Icon(
          _traitIcon(trait),
          color: traitColor,
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w800),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              traitName.isEmpty
                  ? '${childName.isEmpty ? 'Your kid' : childName} · ${_stageTitle(stage)}'
                  : '${childName.isEmpty ? 'Your kid' : childName} · $traitName · ${_stageTitle(stage)}',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    PhosphorIconsRegular.ticket,
                    color: AppColors.navy,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
            if (daysLeft != null) ...[
              const SizedBox(height: 4),
              Text(
                daysLeft <= 0
                    ? 'Expires today'
                    : 'Show at counter · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
                style: AppTextStyles.caption(
                  context,
                  color: daysLeft <= 3
                      ? AppColors.adminRed
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy_outlined),
        tooltip: 'Copy code',
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied $code to clipboard')),
          );
        },
      ),
    );
  }
}

String _traitName(String t) => switch (t) {
      'rafi' => 'Rafi',
      'ellie' => 'Ellie',
      'gerry' => 'Gerry',
      'zena' => 'Zena',
      _ => '',
    };

Color _traitColor(String t) => switch (t) {
      'rafi' => AppColors.rafiCoral,
      'ellie' => AppColors.ellieBlue,
      'gerry' => AppColors.gerryAmber,
      'zena' => AppColors.zenaGreen,
      _ => AppColors.gold,
    };

IconData _traitIcon(String t) => switch (t) {
      'rafi' => PhosphorIconsFill.shieldStar,
      'ellie' => PhosphorIconsFill.heart,
      'gerry' => PhosphorIconsFill.magnifyingGlass,
      'zena' => PhosphorIconsFill.palette,
      _ => PhosphorIconsFill.gift,
    };

class _UnchosenPerkRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> row;
  const _UnchosenPerkRow({required this.row});

  @override
  ConsumerState<_UnchosenPerkRow> createState() => _UnchosenPerkRowState();
}

class _UnchosenPerkRowState extends ConsumerState<_UnchosenPerkRow> {
  bool _busy = false;

  String _stageTitle(String s) =>
      s.isEmpty ? '?' : '${s[0].toUpperCase()}${s.substring(1)}';

  Future<void> _pick(String perkId, String label) async {
    if (_busy) return;
    final grantId = widget.row['id'] as String;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc<dynamic>(
        'stage_perk_pick',
        params: {
          'p_grant_id': grantId,
          'p_perk_id': perkId,
        },
      );
      ref.invalidate(unredeemedHeroPerksProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Locked in: $label')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't lock that reward: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = (widget.row['stage'] as String?) ?? '';
    final trait = widget.row['trait'] as String?;
    final childName = (widget.row['child_name'] as String?) ?? '';
    final traitName = _traitName(trait ?? '');
    final traitColor = _traitColor(trait ?? '');
    final options = ref.watch(
      stagePerkOptionsProvider((stage: stage, trait: trait)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: traitColor.withValues(alpha: 0.20),
                ),
                child: Icon(
                  _traitIcon(trait ?? ''),
                  color: traitColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      traitName.isEmpty
                          ? 'Pick your ${_stageTitle(stage)} reward'
                          : 'Pick your $traitName ${_stageTitle(stage)} reward',
                      style: AppTextStyles.body(context)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (childName.isNotEmpty)
                      Text(
                        '$childName · choose one — locked once picked',
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
          const SizedBox(height: 12),
          options.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => Text(
              "Couldn't load reward options.",
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            data: (opts) {
              if (opts.isEmpty) {
                return Text(
                  'No reward options configured yet. Check back soon!',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                );
              }
              return Column(
                children: [
                  for (final o in opts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PerkOptionCard(
                        label: (o['perk_label'] as String?) ?? 'Reward',
                        description: o['perk_description'] as String?,
                        busy: _busy,
                        onPick: () => _pick(
                          o['id'] as String,
                          (o['perk_label'] as String?) ?? 'Reward',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PerkOptionCard extends StatelessWidget {
  final String label;
  final String? description;
  final bool busy;
  final VoidCallback onPick;

  const _PerkOptionCard({
    required this.label,
    required this.description,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body(context)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (description != null && description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    PhosphorIconsRegular.caretRight,
                    color: AppColors.navy,
                    size: 18,
                  ),
          ],
        ),
      ),
    );
  }
}

/// Live stream of unredeemed perk slots for the family. Two shapes per row:
///   * Picked  → perk_id + code + expires_at set; render the existing card
///   * Unchosen → perk_id is NULL; render a "pick one of N rewards" card.
/// RLS scopes by family.
///
/// Realtime: stage_perk_grants is in the supabase_realtime publication
/// (added in migration 0141), so when staff calls stage_perk_redeem the
/// redeemed_at flip flows here within ~1s and the card disappears
/// without needing an app restart. PostgREST's `.stream()` doesn't
/// support joins, so we use the realtime change as a trigger to re-run
/// the joined SELECT.
final unredeemedHeroPerksProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final familyId = ref.watch(currentFamilyIdProvider);
  if (familyId == null) {
    yield const [];
    return;
  }

  Future<List<Map<String, dynamic>>> fetchJoined() async {
    final rows = await Supabase.instance.client
        .from('stage_perk_grants')
        .select(
          'id, code, stage, trait, granted_at, expires_at, perk_id, '
          'children!inner(name), '
          'stage_perks(perk_label, perk_description, is_active)',
        )
        .eq('family_id', familyId)
        .isFilter('redeemed_at', null)
        .order('granted_at', ascending: false);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final children = m['children'] as Map?;
      final perk = m['stage_perks'] as Map?;
      return {
        ...m,
        'child_name': children?['name'],
        'perk_label': perk?['perk_label'],
        'perk_description': perk?['perk_description'],
        'perk_is_active': perk?['is_active'],
      };
    }).where((m) {
      if (m['perk_id'] != null && m['perk_is_active'] == false) {
        return false;
      }
      final exp = m['expires_at'] as String?;
      if (exp == null) return true;
      return exp.compareTo(nowIso) >= 0;
    }).toList();
  }

  // Initial emission so the card renders on first build.
  yield await fetchJoined();

  // Realtime trigger: any insert/update/delete on this family's
  // stage_perk_grants rows re-runs the joined select.
  final stream = Supabase.instance.client
      .from('stage_perk_grants')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId);
  await for (final _ in stream) {
    yield await fetchJoined();
  }
});

/// The live admin-configured options for a (stage, trait). Used to
/// render the pick UI when a customer opens an unchosen perk slot.
/// Welcome stage uses trait NULL; other stages filter by the grant's
/// trait so Rafi options don't show up on an Ellie slot.
final stagePerkOptionsProvider = FutureProvider.family<
    List<Map<String, dynamic>>, ({String stage, String? trait})>(
  (ref, key) async {
    final q = Supabase.instance.client
        .from('stage_perks')
        .select('id, perk_label, perk_description, validity_days')
        .eq('stage', key.stage)
        .eq('is_active', true);
    final filtered = key.stage == 'welcome' || key.trait == null
        ? q.isFilter('trait', null)
        : q.eq('trait', key.trait!);
    final rows = await filtered.order('perk_label');
    return List<Map<String, dynamic>>.from(rows);
  },
);

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
