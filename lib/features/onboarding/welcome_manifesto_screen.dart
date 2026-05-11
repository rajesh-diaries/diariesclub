import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/onboarding_state_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The "Brave. Kind. Curious. Creative." welcome manifesto. Shown once
/// to every new family right after OTP verify, before the family-name
/// onboarding form. Also reachable anytime via the Adventure tab's
/// "About" pill — in that mode the CTA just pops back rather than
/// advancing the onboarding step.
class WelcomeManifestoScreen extends ConsumerStatefulWidget {
  /// When true (Adventure tab re-visit), the CTA pops instead of
  /// advancing the onboarding flow. Heroes are revealed immediately
  /// (no fade stagger) so re-readers don't wait.
  final bool isRevisit;
  const WelcomeManifestoScreen({super.key, this.isRevisit = false});

  @override
  ConsumerState<WelcomeManifestoScreen> createState() =>
      _WelcomeManifestoScreenState();
}

class _WelcomeManifestoScreenState
    extends ConsumerState<WelcomeManifestoScreen> {
  bool _revealComplete = false;

  @override
  void initState() {
    super.initState();
    if (widget.isRevisit) {
      _revealComplete = true;
    } else {
      // Enable CTA only after the staggered reveal finishes (~6.5s).
      Future<void>.delayed(const Duration(milliseconds: 6500), () {
        if (mounted) setState(() => _revealComplete = true);
      });
    }
  }

  Future<void> _continue() async {
    if (widget.isRevisit) {
      Navigator.of(context).pop();
      return;
    }
    await ref.read(hasSeenWelcomeManifestoProvider.notifier).markSeen();
    if (!mounted) return;
    context.go(OnboardingStep.familyName.route);
  }

  @override
  Widget build(BuildContext context) {
    final stagger = widget.isRevisit;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: widget.isRevisit
          ? AppBar(
              backgroundColor: AppColors.lightBackground,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FadeInBlock(
                      delay: Duration.zero,
                      skipAnimation: stagger,
                      child: const _Headline(),
                    ),
                    const SizedBox(height: 36),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 1200),
                      skipAnimation: stagger,
                      child: Text(
                        'MEET THE HEROES',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ).copyWith(
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 1500),
                      skipAnimation: stagger,
                      child: const _HeroCard(
                        emoji: '🛡️',
                        name: 'Rafi the Brave',
                        tagline:
                            'Some moments ask a little courage. Rafi grows in every one of them.',
                        kidLine:
                            '"That slide you skipped last time? You can try it now. We\'ll be here."',
                        parentLine:
                            'Every time your child tries the thing they were afraid of, Rafi grows. So does the kid you\'re raising.',
                        moments: [
                          'Tries the slide they used to skip',
                          'Joins a workshop on their own',
                          'Asks a question to a grown-up they don\'t know',
                          'Goes first when no one else will',
                        ],
                        accent: AppColors.rafiCoral,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 2100),
                      skipAnimation: stagger,
                      child: const _HeroCard(
                        emoji: '❤️',
                        name: 'Ellie the Kind',
                        tagline:
                            'Kindness isn\'t a lesson. It\'s a thousand small choices a day.',
                        kidLine:
                            '"When a friend looks sad, sit with them. When a friend is hungry, share. That\'s how kindness grows."',
                        parentLine:
                            'The world has enough clever children. Ellie is for the kind ones — the ones who notice, who care, who make other people feel seen.',
                        moments: [
                          'Shares their Healthy Bite with a friend',
                          'Includes a kid who was playing alone',
                          'Cheers when a friend wins',
                          'Says sorry without being asked',
                        ],
                        accent: AppColors.ellieBlue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 2700),
                      skipAnimation: stagger,
                      child: const _HeroCard(
                        emoji: '🔍',
                        name: 'Gerry the Curious',
                        tagline: 'A curious child never stops growing.',
                        kidLine:
                            '"Ask why. Ask how. Try the thing you\'ve never tried. Curiosity will take you everywhere."',
                        parentLine:
                            'Curious kids become curious adults — and curious adults change the world. Gerry grows in every question your child asks.',
                        moments: [
                          'Picks a workshop they\'ve never tried',
                          'Asks "why?" or "how?" to a grown-up',
                          'Tastes a new flavor or ingredient',
                          'Goes deeper into something they love',
                        ],
                        accent: AppColors.gerryAmber,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 3300),
                      skipAnimation: stagger,
                      child: const _HeroCard(
                        emoji: '🎨',
                        name: 'Zena the Creative',
                        tagline:
                            'Creativity is your child saying — "this didn\'t exist, until I made it."',
                        kidLine:
                            '"Paint it. Build it. Tell its story. The world needs what only you can make."',
                        parentLine:
                            'Whether it\'s a drawing, a custom meal, or a wild story at bedtime — Zena grows every time your child puts something new into the world.',
                        moments: [
                          'Makes something at an art workshop',
                          'Builds their own FIT meal combo',
                          'Tells a story at a reflection moment',
                          'Invents a new game with friends',
                        ],
                        accent: AppColors.zenaGreen,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 3900),
                      skipAnimation: stagger,
                      child: const _HowItWorks(),
                    ),
                    const SizedBox(height: 24),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 4500),
                      skipAnimation: stagger,
                      child: const _Stages(),
                    ),
                    const SizedBox(height: 24),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 5500),
                      skipAnimation: stagger,
                      child: const _RewardsPromise(),
                    ),
                    const SizedBox(height: 24),
                    _FadeInBlock(
                      delay: const Duration(milliseconds: 6000),
                      skipAnimation: stagger,
                      child: const _HeroWithin(),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            _CTA(
              enabled: _revealComplete,
              isRevisit: widget.isRevisit,
              onPressed: _continue,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Section widgets
// ---------------------------------------------------------------------------

class _Headline extends StatelessWidget {
  const _Headline();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The things that matter most',
          style: AppTextStyles.h1(context, color: AppColors.navy),
        ),
        Text(
          "can't be graded.",
          style: AppTextStyles.h1(context, color: AppColors.navy),
        ),
        const SizedBox(height: 20),
        const Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _TraitWord('Brave.', AppColors.rafiCoral),
            _TraitWord('Kind.', AppColors.ellieBlue),
            _TraitWord('Curious.', AppColors.gerryAmber),
            _TraitWord('Creative.', AppColors.zenaGreen),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'These are the four traits your child will carry into every classroom, every friendship, every chapter of their life.',
          style: AppTextStyles.body(context),
        ),
        const SizedBox(height: 8),
        Text(
          'Diaries Club is where we help them grow.',
          style: AppTextStyles.body(context).copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _TraitWord extends StatelessWidget {
  final String text;
  final Color color;
  const _TraitWord(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.h2(context, color: color).copyWith(
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String tagline;
  final String kidLine;
  final String parentLine;
  final List<String> moments;
  final Color accent;
  const _HeroCard({
    required this.emoji,
    required this.name,
    required this.tagline,
    required this.kidLine,
    required this.parentLine,
    required this.moments,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: AppTextStyles.h3(context, color: accent).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tagline,
            style: AppTextStyles.body(context).copyWith(
              fontStyle: FontStyle.italic,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _Framing(label: 'For your child', body: kidLine, accent: accent),
          const SizedBox(height: 8),
          _Framing(label: 'For you', body: parentLine, accent: accent),
          const SizedBox(height: 14),
          for (final m in moments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(child: Text(m, style: AppTextStyles.body(context))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Framing extends StatelessWidget {
  final String label;
  final String body;
  final Color accent;
  const _Framing({
    required this.label,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.caption(context, color: accent).copyWith(
            letterSpacing: 1.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(body, style: AppTextStyles.body(context)),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How we hold their growth',
          style: AppTextStyles.h3(context, color: AppColors.navy),
        ),
        const SizedBox(height: 8),
        Text(
          'Every visit, every meal, every moment your child chooses well — we notice. We give it a name. We keep it.',
          style: AppTextStyles.body(context),
        ),
        const SizedBox(height: 12),
        const _GrowthLine(
            label: 'Trying the slide grows',
            heroName: 'Rafi',
            color: AppColors.rafiCoral),
        const _GrowthLine(
            label: 'Sharing a snack grows',
            heroName: 'Ellie',
            color: AppColors.ellieBlue),
        const _GrowthLine(
            label: 'Trying a new flavor grows',
            heroName: 'Gerry',
            color: AppColors.gerryAmber),
        const _GrowthLine(
            label: 'Making something grows',
            heroName: 'Zena',
            color: AppColors.zenaGreen),
        const SizedBox(height: 12),
        Text(
          "It's not a game. It's a record of who they're becoming.",
          style: AppTextStyles.body(context).copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _GrowthLine extends StatelessWidget {
  final String label;
  final String heroName;
  final Color color;
  const _GrowthLine({
    required this.label,
    required this.heroName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.body(context),
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: heroName,
              style: AppTextStyles.body(context, color: color).copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stages extends StatelessWidget {
  const _Stages();

  @override
  Widget build(BuildContext context) {
    const stages = [
      ('🌱', 'Seedling', 'the start'),
      ('🧭', 'Explorer', 'finding their feet'),
      ('🏞', 'Adventurer', 'confident now'),
      ('🏆', 'Champion', 'strong and steady'),
      ('⭐', 'Legend', 'fully themselves'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Five stages of growth',
          style: AppTextStyles.h3(context, color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          "Real growth doesn't happen in a day.",
          style: AppTextStyles.body(
            context,
            color: AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 14),
        for (final s in stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(s.$1, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Text(
                  s.$2,
                  style: AppTextStyles.bodyLarge(context).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '— ${s.$3}',
                  style: AppTextStyles.body(
                    context,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Every stage takes time. Every stage is worth celebrating.',
          style: AppTextStyles.body(context),
        ),
      ],
    );
  }
}

class _RewardsPromise extends StatelessWidget {
  const _RewardsPromise();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A real reward, every time',
            style: AppTextStyles.h3(context, color: AppColors.navy),
          ),
          const SizedBox(height: 10),
          Text(
            "When your child reaches a new stage, they don't get a notification.",
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 6),
          Text(
            'They get something they can hold.',
            style: AppTextStyles.body(context).copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'A favorite treat. A sticker for their wall. A free upgrade on something they love. A one-of-a-kind hero card that\'s theirs forever.',
            style: AppTextStyles.body(context),
          ),
          const SizedBox(height: 10),
          Text(
            'Because growing up deserves to be celebrated — in the real world, not on a screen.',
            style: AppTextStyles.body(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

class _HeroWithin extends StatelessWidget {
  const _HeroWithin();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'And one day —',
            style: AppTextStyles.body(context).copyWith(
              color: AppColors.gold,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'when your child reaches Legend in all four traits, something rare happens.',
            style: AppTextStyles.body(context).copyWith(color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            'They become a Hero Within of Diaries Club.',
            style: AppTextStyles.h3(context).copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The highest honor we give. And our promise to your family:',
            style: AppTextStyles.body(context).copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          const _HeroWithinRow(
            emoji: '🎁',
            text: 'A birthday gift from us, every year, for the next 5 years',
          ),
          const _HeroWithinRow(
            emoji: '🏛',
            text: 'Their name on the Hall of Heroes at our venue — forever',
          ),
          const _HeroWithinRow(
            emoji: '✨',
            text: 'A small ceremony, with us, the day they unlock it',
          ),
          const SizedBox(height: 14),
          Text(
            'When a child grows up beautifully in our hands, we don\'t just say goodbye. We stay in their story.',
            style: AppTextStyles.body(context).copyWith(
              color: Colors.white,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroWithinRow extends StatelessWidget {
  final String emoji;
  final String text;
  const _HeroWithinRow({required this.emoji, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(context).copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CTA extends StatelessWidget {
  final bool enabled;
  final bool isRevisit;
  final VoidCallback onPressed;
  const _CTA({
    required this.enabled,
    required this.isRevisit,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.lightBackground,
        border: Border(
          top: BorderSide(color: AppColors.lightBorder),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                isRevisit ? 'Got it' : "Let's begin their story",
                style: AppTextStyles.bodyLarge(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (!isRevisit) ...[
            const SizedBox(height: 6),
            Text(
              'You can come back to this anytime — Adventure tab → About',
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Stagger helper — fades + slides a block in after `delay` since mount.
// ---------------------------------------------------------------------------

class _FadeInBlock extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final bool skipAnimation;
  const _FadeInBlock({
    required this.child,
    required this.delay,
    this.skipAnimation = false,
  });

  @override
  State<_FadeInBlock> createState() => _FadeInBlockState();
}

class _FadeInBlockState extends State<_FadeInBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.skipAnimation) {
      _ctrl.value = 1.0;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _ctrl.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _ctrl.value) * 16),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
