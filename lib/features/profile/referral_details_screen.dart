import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/referral_stats_provider.dart';
import '../../core/providers/venue_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';

/// "Show details" screen behind the referral card. How-it-works (3 steps),
/// monthly cap progress, total earned. Numbers come from venue_config so
/// the founder can re-tune the funnel without an app update.
class ReferralDetailsScreen extends ConsumerWidget {
  const ReferralDetailsScreen({super.key});

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(currentFamilyProvider).valueOrNull ?? const {};
    final cfg = ref.watch(venueConfigProvider).valueOrNull ?? const {};
    final statsAsync = ref.watch(referralStatsProvider);

    final code = (family['referral_code'] as String?) ?? '';
    final gifter = (cfg['referral_gifter_credit_paise'] as int?) ?? 20000;
    final newFamily =
        (cfg['referral_new_family_credit_paise'] as int?) ?? 10000;
    final monthlyCapPaise =
        (cfg['referral_monthly_cap_paise'] as int?) ?? 100000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referral details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (code.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightSurface,
                    border: Border.all(color: AppColors.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          code,
                          style: AppTextStyles.h2(context).copyWith(
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _copy(context, code),
                        icon: const Icon(PhosphorIconsRegular.copy),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text('How it works', style: AppTextStyles.h3(context)),
              const SizedBox(height: 12),
              const _Step(
                index: 1,
                title: 'Share your code',
                subtitle: 'Send your code to a friend via WhatsApp.',
              ),
              _Step(
                index: 2,
                title: 'They sign up + play',
                subtitle:
                    'When they play their first session, they get '
                    '${Money.fromPaise(newFamily)} and you get '
                    '${Money.fromPaise(gifter)} — both credits land the same moment.',
              ),
              const _Step(
                index: 3,
                title: 'Credits land in your wallet',
                subtitle: 'Use them on play, café, or workshops.',
              ),
              const SizedBox(height: 24),
              statsAsync.when(
                data: (s) => _StatsBlock(
                  stats: s,
                  monthlyCapPaise: monthlyCapPaise,
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Monthly cap: up to ${Money.fromPaise(monthlyCapPaise)} in '
                  'referral rewards per month, to keep things fair.',
                  style: AppTextStyles.caption(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  const _Step({
    required this.index,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: AppTextStyles.caption(context, color: AppColors.navy),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyLarge(context)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.body(
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

class _StatsBlock extends StatelessWidget {
  final ReferralStats stats;
  final int monthlyCapPaise;
  const _StatsBlock({required this.stats, required this.monthlyCapPaise});

  @override
  Widget build(BuildContext context) {
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
          Text('Your referrals', style: AppTextStyles.bodyLarge(context)),
          const SizedBox(height: 12),
          _Stat(label: 'Total referrals', value: '${stats.totalReferrals}'),
          _Stat(label: 'This month', value: '${stats.thisMonthReferrals}'),
          _Stat(
            label: 'Total earned',
            value: Money.fromPaise(stats.totalEarnedPaise),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          Text(value, style: AppTextStyles.bodyLarge(context)),
        ],
      ),
    );
  }
}
