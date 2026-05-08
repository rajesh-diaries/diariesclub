import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/venue_config_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/currency.dart';

/// Promoted "Invite a friend" card at the top of Profile. Pulls credit
/// amounts from venue_config so admin can tune without an app update.
/// Branch deep-link generation is stubbed for v1 — the share text just
/// includes the referral code; Session 12 wires Branch links.
class ReferralCard extends ConsumerWidget {
  const ReferralCard({super.key});

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code copied: $code'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _share(
    String code,
    int gifterPaise,
    int newFamilyPaise,
  ) async {
    final text = 'Hey! I love Diaries Club for the kids. '
        'Use my code $code when you sign up — both of us get a wallet credit '
        '(${Money.fromPaise(newFamilyPaise)} for you, '
        '${Money.fromPaise(gifterPaise)} for me) once you play your first session.';
    // TODO(session-12): generate Branch deep link and append.
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(currentFamilyProvider).valueOrNull ??
        const <String, dynamic>{};
    final cfg = ref.watch(venueConfigProvider).valueOrNull ??
        const <String, dynamic>{};

    final code = (family['referral_code'] as String?) ?? '';
    final gifterPaise =
        (cfg['referral_gifter_credit_paise'] as int?) ?? 20000;
    final newFamilyPaise =
        (cfg['referral_new_family_credit_paise'] as int?) ?? 10000;

    if (code.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A4A8B), AppColors.navy],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  PhosphorIconsFill.sparkle,
                  color: AppColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Invite a friend',
                  style: AppTextStyles.h3(context, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Friends who join with your code get '
              '${Money.fromPaise(newFamilyPaise)} after their first session. '
              'You get ${Money.fromPaise(gifterPaise)} when they play.',
              style: AppTextStyles.body(context, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: AppTextStyles.h3(context, color: Colors.white)
                          .copyWith(letterSpacing: 1.2),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _copy(context, code),
                    child: Text(
                      'Copy',
                      style: AppTextStyles.button(
                        context,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _share(code, gifterPaise, newFamilyPaise),
                icon: const Icon(
                  PhosphorIconsRegular.whatsappLogo,
                  color: Colors.white,
                ),
                label: const Text('Share via WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.activeGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => context.push('/profile/referral-details'),
                child: Text(
                  'Show details',
                  style: AppTextStyles.caption(
                    context,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
