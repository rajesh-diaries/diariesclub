import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/current_family_provider.dart';
import '../../core/providers/onboarding_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/progress_dots.dart';

/// Onboarding step 4 — pick favourite hero.
///
/// Locked product decision: this is cosmetic only. All four heroes earn XP
/// regardless of which one is favourited. We update the existing children
/// row (created on the previous screen) and complete onboarding.
class HeroPickScreen extends ConsumerStatefulWidget {
  const HeroPickScreen({super.key});

  @override
  ConsumerState<HeroPickScreen> createState() => _HeroPickScreenState();
}

class _HeroPickScreenState extends ConsumerState<HeroPickScreen> {
  String? _selectedHero;
  bool _isLoading = false;
  String? _errorText;

  static const _heroes = <_Hero>[
    _Hero('rafi', 'Rafi', 'Brave', AppColors.rafiCoral, PhosphorIconsFill.shieldStar),
    _Hero('ellie', 'Ellie', 'Kind', AppColors.ellieBlue, PhosphorIconsFill.heart),
    _Hero('gerry', 'Gerry', 'Curious', AppColors.gerryAmber, PhosphorIconsFill.magnifyingGlass),
    _Hero('zena', 'Zena', 'Creative', AppColors.zenaGreen, PhosphorIconsFill.palette),
  ];

  Future<void> _submit() async {
    if (_selectedHero == null) return;
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final childId =
          await ref.read(currentOnboardingChildIdProvider.future);
      if (childId == null) {
        throw StateError('no child id stored');
      }

      // children_family RLS allows the family owner to UPDATE — no RPC needed.
      await Supabase.instance.client
          .from('children')
          .update({'favourite_hero': _selectedHero})
          .eq('id', childId);

      // Onboarding complete.
      await ref
          .read(onboardingStepProvider.notifier)
          .setStep(OnboardingStep.complete);
      await ref.read(currentOnboardingChildIdProvider.notifier).set(null);
      ref.invalidate(currentFamilyProvider);

      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      setState(() {
        _errorText = "Couldn't save. Please try again.";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const ProgressDots(currentStep: 4),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await ref
                .read(onboardingStepProvider.notifier)
                .setStep(OnboardingStep.childDetails);
            if (!context.mounted) return;
            context.go('/onboarding/child-details');
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Pick a favourite character', style: AppTextStyles.h1(context)),
              const SizedBox(height: 8),
              Text(
                "They'll all be along for the adventure — pick the one your kid loves the most.",
                style: AppTextStyles.body(context,
                    color: AppColors.lightTextSecondary),
              ),
              const SizedBox(height: 24),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.78,
                children: _heroes.map((h) {
                  final selected = _selectedHero == h.id;
                  return _HeroCard(
                    hero: h,
                    selected: selected,
                    onTap: _isLoading
                        ? null
                        : () => setState(() => _selectedHero = h.id),
                  );
                }).toList(),
              ),

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorText!,
                    style: AppTextStyles.caption(context,
                        color: AppColors.adminRed),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Start the adventure!',
                  onPressed:
                      _selectedHero != null && !_isLoading ? _submit : null,
                  loading: _isLoading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero {
  final String id;
  final String name;
  final String trait;
  final Color color;
  final IconData icon;
  const _Hero(this.id, this.name, this.trait, this.color, this.icon);
}

class _HeroCard extends StatelessWidget {
  final _Hero hero;
  final bool selected;
  final VoidCallback? onTap;

  const _HeroCard({
    required this.hero,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: hero.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? hero.color : AppColors.lightBorder,
                width: selected ? 3 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: hero.color.withValues(alpha: 0.20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(hero.icon, color: hero.color, size: 40),
                ),
                const SizedBox(height: 12),
                Text(hero.name, style: AppTextStyles.h3(context)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hero.color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hero.trait,
                    style: AppTextStyles.caption(context, color: hero.color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
