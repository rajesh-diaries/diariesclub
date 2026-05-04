import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/marketing_consent_visibility_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Soft-prompt card that asks for marketing consent. Only renders when
/// `marketingConsentVisibleProvider` returns true. "Yes" flips the family's
/// `marketing_consent` to true; "No thanks" silently dismisses (forever,
/// per spec).
class MarketingConsentCard extends ConsumerStatefulWidget {
  const MarketingConsentCard({super.key});

  @override
  ConsumerState<MarketingConsentCard> createState() =>
      _MarketingConsentCardState();
}

class _MarketingConsentCardState
    extends ConsumerState<MarketingConsentCard> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    final familyId = ref.read(currentFamilyIdProvider);
    if (familyId != null) {
      try {
        await Supabase.instance.client
            .from('families')
            .update({'marketing_consent': true}).eq('id', familyId);
        ref.invalidate(currentFamilyProvider);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't save. Please try again.")),
          );
        }
        setState(() => _busy = false);
        return;
      }
    }
    await dismissMarketingConsent(ref);
  }

  Future<void> _decline() async => dismissMarketingConsent(ref);

  @override
  Widget build(BuildContext context) {
    final visible =
        ref.watch(marketingConsentVisibleProvider).valueOrNull ?? false;
    if (!visible) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        border: Border.all(color: AppColors.lightBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.envelope,
                color: AppColors.navy,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text('Stay in the loop', style: AppTextStyles.h3(context)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Get birthday tips, party ideas, and special offers from Diaries.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _accept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('Yes, send me updates'),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _busy ? null : _decline,
                child: const Text('No thanks'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
