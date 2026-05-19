import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/error_screen.dart';

/// Look up one hero_card_collection row joined with its definition. Used
/// by the unbox screen to drive the front of the card after the flip.
final cardUnboxDataProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, collectionId) async {
  final row = await Supabase.instance.client
      .from('hero_card_collection')
      .select('id, earned_at, hero_card_definitions(*)')
      .eq('id', collectionId)
      .maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
});

/// Card unboxing — card-back → tap to flip → reveal front. Rare cards get
/// extra sparkles + heavy haptic. Reduced-motion bypasses the flip and
/// shows the front immediately.
class CardUnboxingScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const CardUnboxingScreen({super.key, required this.collectionId});

  @override
  ConsumerState<CardUnboxingScreen> createState() =>
      _CardUnboxingScreenState();
}

class _CardUnboxingScreenState extends ConsumerState<CardUnboxingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _reveal({required bool isRare}) async {
    if (_revealed) return;
    setState(() => _revealed = true);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (isRare) {
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    // mounted-guard the AnimationController calls — if the user closes
    // the sheet during the 80ms haptic delay the controller is disposed
    // and .forward() / value= throw an AssertionError.
    if (!mounted) return;
    if (reduceMotion) {
      _flip.value = 1.0;
      return;
    }
    await _flip.forward();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cardUnboxDataProvider(widget.collectionId));

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/adventure'),
        ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          error: (e, _) => FriendlyErrorScreen(
            code: 'E-CARD',
            userMessage: "Couldn't load this card",
            technicalDetails: e.toString(),
          ),
          data: (row) {
            if (row == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "This card isn't in your collection.",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              );
            }
            final card =
                (row['hero_card_definitions'] as Map?)?.cast<String, dynamic>() ??
                    const {};
            final isRare = card['is_rare'] == true;
            return _Body(
              card: card,
              isRare: isRare,
              flip: _flip,
              revealed: _revealed,
              onReveal: () => _reveal(isRare: isRare),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool isRare;
  final AnimationController flip;
  final bool revealed;
  final VoidCallback onReveal;

  const _Body({
    required this.card,
    required this.isRare,
    required this.flip,
    required this.revealed,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final hero = (card['hero'] as String?) ?? 'rafi';
    final heroColor = _heroColor(hero);

    // Bounded-height column wouldn't fit the card + reveal container on
    // shorter phones (caused a 200+px overflow). Make the whole layout
    // scrollable as a fallback, and replace the two flexible Spacers
    // with fixed gaps since SingleChildScrollView gives an unbounded
    // vertical extent (Spacer needs bounded constraints).
    return SingleChildScrollView(
      child: Column(
      children: [
        const SizedBox(height: 32),
        Text(
          revealed ? 'A new card!' : 'A new card!',
          style: AppTextStyles.h2(context, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          revealed ? 'Tap below for details' : 'Tap to reveal',
          style: AppTextStyles.body(context, color: Colors.white70),
        ),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: revealed ? null : onReveal,
            child: AnimatedBuilder(
              animation: flip,
              builder: (_, __) {
                final t = flip.value;
                final angle = t * math.pi;
                final showFront = t >= 0.5;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isRare && revealed) const _Rays(color: AppColors.gold),
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      child: showFront
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _CardFront(
                                card: card,
                                heroColor: heroColor,
                                isRare: isRare,
                              ),
                            )
                          : _CardBack(heroColor: heroColor, isRare: isRare),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (revealed) ...[
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      (card['name'] as String?) ?? 'Character card',
                      style: AppTextStyles.h3(context, color: Colors.white),
                    ),
                    const Spacer(),
                    if (isRare)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'RARE',
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.navy,
                          ).copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                  ],
                ),
                if ((card['description'] as String?) != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    card['description'] as String,
                    style: AppTextStyles.body(context, color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      PhosphorIconsFill.checkCircle,
                      color: AppColors.activeGreen,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Added to collection',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.activeGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go('/adventure'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white60),
                    ),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.go('/adventure'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.navy,
                    ),
                    child: const Text('See all cards'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    ));
  }

  static Color _heroColor(String t) => switch (t) {
        'rafi' => AppColors.rafiCoral,
        'ellie' => AppColors.ellieBlue,
        'gerry' => AppColors.gerryAmber,
        'zena' => AppColors.zenaGreen,
        _ => AppColors.gold,
      };
}

class _CardBack extends StatelessWidget {
  final Color heroColor;
  final bool isRare;
  const _CardBack({required this.heroColor, required this.isRare});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 308,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [heroColor.withValues(alpha: 0.30), AppColors.navy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRare ? AppColors.gold : Colors.white24,
          width: isRare ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: heroColor.withValues(alpha: 0.30),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(
        PhosphorIconsFill.sparkle,
        color: AppColors.gold,
        size: 64,
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  final Map<String, dynamic> card;
  final Color heroColor;
  final bool isRare;
  const _CardFront({
    required this.card,
    required this.heroColor,
    required this.isRare,
  });

  @override
  Widget build(BuildContext context) {
    final image = card['image_url'] as String?;
    return Container(
      width: 220,
      height: 308,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRare ? AppColors.gold : heroColor,
          width: isRare ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: heroColor.withValues(alpha: 0.30),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Container(color: heroColor.withValues(alpha: 0.20))
          : CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: heroColor.withValues(alpha: 0.20),
              ),
              errorWidget: (_, __, ___) => Container(
                color: heroColor.withValues(alpha: 0.20),
                alignment: Alignment.center,
                child: Icon(PhosphorIconsFill.sparkle,
                    color: heroColor, size: 48),
              ),
            ),
    );
  }
}

/// Static gold rays behind a rare card. Six segments rendered with
/// rotated containers — keeps total particle count well under the 30-cap.
class _Rays extends StatelessWidget {
  final Color color;
  const _Rays({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Transform.rotate(
              angle: (i * math.pi) / 6,
              child: Container(
                width: 360,
                height: 8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      color.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
