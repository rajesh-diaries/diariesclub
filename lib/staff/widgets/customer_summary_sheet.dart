import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';

/// Bottom sheet that renders everything a staff member should know about a
/// family at a glance: visits, spend, top food, wallet, XP, tier. Called
/// from Active Sessions row taps, KDS order-card ⓘ chips, Manual Session
/// phone-match preview, Healthy Bite rows, Walk-in POS, Refund, and
/// Redeem perk header chips.
///
/// Data comes from a single SECURITY DEFINER RPC `staff_customer_summary`
/// (migration `staff_customer_summary_rpc`, 2026-05-21). The RPC is venue-
/// scoped via the caller's tablet_devices row, so a single staff phone
/// only ever sees its own venue's data.
///
/// Pass a non-null [actions] list to render a one-tap action footer (e.g.
/// Extend, Add food order, Mark left). Read-only contexts (POS, refund,
/// redeem perk) leave [actions] null and the footer is hidden.
class CustomerSummarySheet extends ConsumerStatefulWidget {
  final String familyId;
  final List<CustomerSheetAction<dynamic>>? actions;

  const CustomerSummarySheet({
    super.key,
    required this.familyId,
    this.actions,
  });

  /// Helper to open the sheet from anywhere. Returns the value of the
  /// action the user tapped (the action's [CustomerSheetAction.value]),
  /// or null if dismissed without choosing.
  static Future<T?> show<T>(
    BuildContext context, {
    required String familyId,
    List<CustomerSheetAction<T>>? actions,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerSummarySheet(
        familyId: familyId,
        actions: actions,
      ),
    );
  }

  @override
  ConsumerState<CustomerSummarySheet> createState() =>
      _CustomerSummarySheetState();
}

class _CustomerSummarySheetState extends ConsumerState<CustomerSummarySheet> {
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final raw = await Supabase.instance.client.rpc<dynamic>(
      'staff_customer_summary',
      params: {'p_family_id': widget.familyId},
    );
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.lightBackground,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.lightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _ErrorState(error: snap.error.toString());
                    }
                    final data = snap.data ?? const <String, dynamic>{};
                    return _Body(
                      data: data,
                      scrollController: scrollController,
                    );
                  },
                ),
              ),
              if (widget.actions != null && widget.actions!.isNotEmpty)
                _ActionFooter(actions: widget.actions!),
            ],
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> data;
  final ScrollController scrollController;
  const _Body({required this.data, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final guardianName = (data['guardian_name'] as String?) ?? 'Customer';
    final guardianPhone = (data['guardian_phone'] as String?) ?? '';
    final childNames = ((data['child_names'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final isWalkIn = (data['is_walk_in'] as bool?) ?? false;
    final visitCount = (data['visit_count'] as int?) ?? 0;
    final lastVisitAt = data['last_visit_at'] as String?;
    final avgMinutes = (data['avg_session_length_minutes'] as int?) ?? 0;
    final lifetime = (data['lifetime_spend_paise'] as int?) ?? 0;
    final foodSpend = (data['food_spend_paise'] as int?) ?? 0;
    final sessionSpend = (data['session_spend_paise'] as int?) ?? 0;
    final workshopSpend = (data['workshop_spend_paise'] as int?) ?? 0;
    final birthdaySpend = (data['birthday_spend_paise'] as int?) ?? 0;
    final topItems = ((data['top_food_items'] as List?) ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .toList();
    final walletBalance = (data['wallet_balance_paise'] as int?) ?? 0;
    final coins = (data['coins_balance'] as int?) ?? 0;
    final totalXp = (data['total_xp'] as int?) ?? 0;
    final tier = data['member_tier'] as String?;
    final signal = _SignalLabel.forFamily(
      visitCount: visitCount,
      lifetimePaise: lifetime,
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        _Header(
          guardianName: guardianName,
          guardianPhone: guardianPhone,
          childNames: childNames,
          isWalkIn: isWalkIn,
          signal: signal,
          tier: tier,
        ),
        const SizedBox(height: 16),
        _StatGrid(
          visitCount: visitCount,
          lastVisitAt: lastVisitAt,
          avgMinutes: avgMinutes,
          lifetime: lifetime,
        ),
        const SizedBox(height: 16),
        _SpendBreakdown(
          food: foodSpend,
          sessions: sessionSpend,
          workshops: workshopSpend,
          birthdays: birthdaySpend,
        ),
        const SizedBox(height: 16),
        _TopFoodCard(items: topItems),
        const SizedBox(height: 16),
        _WalletXpRow(
          walletPaise: walletBalance,
          coins: coins,
          totalXp: totalXp,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String guardianName;
  final String guardianPhone;
  final List<String> childNames;
  final bool isWalkIn;
  final _SignalLabel signal;
  final String? tier;

  const _Header({
    required this.guardianName,
    required this.guardianPhone,
    required this.childNames,
    required this.isWalkIn,
    required this.signal,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    final childLabel = childNames.isEmpty
        ? (isWalkIn ? 'Walk-in customer' : 'No children registered')
        : childNames.length == 1
            ? childNames.first
            : '${childNames.first} +${childNames.length - 1}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: signal.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                signal.label,
                style: AppTextStyles.caption(context, color: signal.color)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (tier != null && tier!.isNotEmpty)
                _TierChip(tier: tier!),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            childLabel,
            style: AppTextStyles.h3(context),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            guardianName,
            style: AppTextStyles.body(context),
          ),
          if (guardianPhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              guardianPhone,
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalLabel {
  final String label;
  final Color color;
  const _SignalLabel(this.label, this.color);

  /// Lightweight heuristics — no admin config yet. Founder can tune
  /// thresholds in a follow-up if these don't match floor intuition.
  static _SignalLabel forFamily({
    required int visitCount,
    required int lifetimePaise,
  }) {
    if (lifetimePaise >= 1500000) {
      return const _SignalLabel('VIP · top spender', AppColors.gold);
    }
    if (visitCount >= 10) {
      return const _SignalLabel('Regular', AppColors.fitGreen);
    }
    if (visitCount <= 2) {
      return const _SignalLabel('New', AppColors.navy);
    }
    return _SignalLabel('Returning', AppColors.lightTextSecondary);
  }
}

class _TierChip extends StatelessWidget {
  final String tier;
  const _TierChip({required this.tier});

  @override
  Widget build(BuildContext context) {
    final color = switch (tier) {
      'legend' => AppColors.gold,
      'champion' => AppColors.rafiCoral,
      'adventurer' => AppColors.gerryAmber,
      'explorer' => AppColors.ellieBlue,
      _ => AppColors.fitGreen,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        tier[0].toUpperCase() + tier.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final int visitCount;
  final String? lastVisitAt;
  final int avgMinutes;
  final int lifetime;
  const _StatGrid({
    required this.visitCount,
    required this.lastVisitAt,
    required this.avgMinutes,
    required this.lifetime,
  });

  @override
  Widget build(BuildContext context) {
    final lastVisit = _formatRelative(lastVisitAt);
    return Row(
      children: [
        Expanded(child: _StatTile(
          icon: PhosphorIconsFill.calendarCheck,
          value: '$visitCount',
          label: visitCount == 1 ? 'visit' : 'visits',
          accent: AppColors.navy,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatTile(
          icon: PhosphorIconsFill.clock,
          value: lastVisit,
          label: 'last seen',
          accent: AppColors.navy,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatTile(
          icon: PhosphorIconsFill.hourglass,
          value: avgMinutes > 0 ? '${avgMinutes}m' : '—',
          label: 'avg stay',
          accent: AppColors.navy,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatTile(
          icon: PhosphorIconsFill.coins,
          value: Money.fromPaise(lifetime),
          label: 'lifetime',
          accent: AppColors.gold,
        )),
      ],
    );
  }

  /// Compact relative time: "today", "2d", "3w", "5mo". Returns "—" if
  /// the input is null/unparseable. Keeps the tile under 80dp so it
  /// doesn't overflow on narrow phones.
  static String _formatRelative(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inDays == 0) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
    return '${(diff.inDays / 365).floor()}y';
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.body(context, color: accent)
                .copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _SpendBreakdown extends StatelessWidget {
  final int food;
  final int sessions;
  final int workshops;
  final int birthdays;
  const _SpendBreakdown({
    required this.food,
    required this.sessions,
    required this.workshops,
    required this.birthdays,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(String, int, IconData)>[
      ('Sessions', sessions, PhosphorIconsRegular.gameController),
      ('Food & drinks', food, PhosphorIconsRegular.coffee),
      ('Workshops', workshops, PhosphorIconsRegular.palette),
      ('Birthdays', birthdays, PhosphorIconsRegular.cake),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where they spend',
            style: AppTextStyles.bodyLarge(context)
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final r in rows) ...[
            Row(
              children: [
                Icon(r.$3, size: 16, color: AppColors.lightTextSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.$1, style: AppTextStyles.body(context)),
                ),
                Text(
                  Money.fromPaise(r.$2),
                  style: AppTextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (r != rows.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _TopFoodCard extends StatelessWidget {
  final List<Map<dynamic, dynamic>> items;
  const _TopFoodCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.heart,
                  size: 16, color: AppColors.rafiCoral),
              const SizedBox(width: 8),
              Text(
                'What they love',
                style: AppTextStyles.bodyLarge(context)
                    .copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'No food orders yet.',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            )
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('${i + 1}.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (items[i]['name'] as String?) ?? '—',
                        style: AppTextStyles.body(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '×${items[i]['count'] ?? 0}',
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

class _WalletXpRow extends StatelessWidget {
  final int walletPaise;
  final int coins;
  final int totalXp;
  const _WalletXpRow({
    required this.walletPaise,
    required this.coins,
    required this.totalXp,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Chip(
          icon: PhosphorIconsFill.wallet,
          accent: AppColors.fitGreen,
          big: Money.fromPaise(walletPaise),
          small: 'wallet',
        )),
        const SizedBox(width: 8),
        Expanded(child: _Chip(
          icon: PhosphorIconsFill.coin,
          accent: AppColors.gold,
          big: '$coins',
          small: 'coins',
        )),
        const SizedBox(width: 8),
        Expanded(child: _Chip(
          icon: PhosphorIconsFill.star,
          accent: AppColors.rafiCoral,
          big: '$totalXp',
          small: 'XP',
        )),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String big;
  final String small;
  const _Chip({
    required this.icon,
    required this.accent,
    required this.big,
    required this.small,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  big,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(context, color: accent)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  small,
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

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    String friendly;
    if (error.contains('tablet_not_authorised')) {
      friendly = 'This phone is no longer registered. Sign in again.';
    } else if (error.contains('family_deleted')) {
      friendly = 'Customer account is closed.';
    } else if (error.contains('family_not_found')) {
      friendly = 'Customer not found.';
    } else {
      friendly = "Couldn't load customer details.\n$error";
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsRegular.warning,
                size: 36, color: AppColors.adminRed),
            const SizedBox(height: 12),
            Text(
              friendly,
              style: AppTextStyles.body(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the action footer of [CustomerSummarySheet]. Pop the sheet
/// returning this action's [value] when tapped; the caller decides what
/// to do (extend session, open POS prefilled, etc.).
class CustomerSheetAction<T> {
  final String label;
  final IconData icon;
  final T value;
  final Color? accent;
  final bool destructive;
  const CustomerSheetAction({
    required this.label,
    required this.icon,
    required this.value,
    this.accent,
    this.destructive = false,
  });
}

class _ActionFooter extends StatelessWidget {
  final List<CustomerSheetAction<dynamic>> actions;
  const _ActionFooter({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(
          top: BorderSide(color: AppColors.lightBorder),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            Expanded(child: _ActionButton(action: actions[i])),
            if (i < actions.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final CustomerSheetAction<dynamic> action;
  const _ActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? AppColors.adminRed
        : (action.accent ?? AppColors.navy);
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).pop(action.value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                action.label,
                style: AppTextStyles.caption(context, color: color)
                    .copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
