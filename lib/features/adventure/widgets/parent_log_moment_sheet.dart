import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/parent_log_moments_data.dart';

/// Bottom sheet flow for "My kid did this":
///   Step 1 — pick a hero (Rafi / Ellie / Gerry / Zena)
///   Step 2 — pick a moment (top 6 + "See more" + "+ My own moment")
///   Step 3 — confirmation toast handled by the caller via onLogged.
///
/// The XP credit + diary insertion happen server-side via the
/// `log_parent_moment` RPC. The sheet only routes the choices.
class ParentLogMomentSheet extends ConsumerStatefulWidget {
  final String childId;
  final String childName;
  /// When set, skips the hero picker step and opens directly to the moment
  /// list for this hero. The "Change character" back button is hidden in
  /// this mode — callers (e.g. the reflection screen's "+ More moments"
  /// tile) want a single-character flow.
  final String? initialHero;
  const ParentLogMomentSheet({
    super.key,
    required this.childId,
    required this.childName,
    this.initialHero,
  });

  @override
  ConsumerState<ParentLogMomentSheet> createState() =>
      _ParentLogMomentSheetState();
}

class _ParentLogMomentSheetState extends ConsumerState<ParentLogMomentSheet> {
  String? _hero;
  bool _showAll = false;
  bool _customMode = false;
  final _customCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialHero != null) {
      _hero = widget.initialHero;
    }
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit({required String text, required String source}) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('log_parent_moment', params: {
        'p_child_id': widget.childId,
        'p_hero': _hero,
        'p_moment_text': text,
        'p_source': source,
      });
      if (!mounted) return;
      final remaining = res['logs_remaining_today'] as int? ?? 0;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged for ${_heroEmoji(_hero!)} ${_heroName(_hero!)} — +5 XP'
            '${remaining > 0 ? '. $remaining more today.' : '.'}',
          ),
          backgroundColor: AppColors.activeGreen,
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (e.message.contains('daily_cap_reached')) {
          _error =
              'You\'ve logged 3 moments today. Come back tomorrow or visit Diaries Club for more XP.';
        } else if (e.message.contains('moment_text_too_long')) {
          _error = 'Moment is too long — keep it under 280 characters.';
        } else if (e.message.contains('empty_moment_text')) {
          _error = 'Please write something.';
        } else {
          _error = "Couldn't log this moment: ${e.message}";
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't log this moment: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.lightBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.lightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hero == null
                                ? 'What did ${widget.childName} do?'
                                : 'Tap the moment',
                            style: AppTextStyles.h2(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _hero == null
                                ? 'Pick the character that grows from this moment.'
                                : 'Or write your own at the bottom.',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _hero == null
                    ? _HeroPicker(
                        onPick: (h) =>
                            setState(() { _hero = h; _showAll = false; _customMode = false; }),
                        controller: controller,
                      )
                    : _MomentPicker(
                        hero: _hero!,
                        showAll: _showAll,
                        customMode: _customMode,
                        customCtrl: _customCtrl,
                        controller: controller,
                        submitting: _submitting,
                        error: _error,
                        lockedToHero: widget.initialHero != null,
                        onPickPreset: (text) =>
                            _submit(text: text, source: 'preset'),
                        onSeeMore: () => setState(() => _showAll = true),
                        onEnterCustom: () =>
                            setState(() => _customMode = true),
                        onSubmitCustom: () => _submit(
                          text: _customCtrl.text.trim(),
                          source: 'custom',
                        ),
                        onBack: () =>
                            setState(() { _hero = null; _customMode = false; _error = null; }),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Step 1 — hero picker
// ---------------------------------------------------------------------------

class _HeroPicker extends StatelessWidget {
  final ValueChanged<String> onPick;
  final ScrollController controller;
  const _HeroPicker({required this.onPick, required this.controller});

  @override
  Widget build(BuildContext context) {
    const heroes = [
      ('rafi', '🛡️', 'Rafi the Brave', 'Pushing past hesitation', AppColors.rafiCoral),
      ('ellie', '❤️', 'Ellie the Kind', 'Caring about other humans', AppColors.ellieBlue),
      ('gerry', '🔍', 'Gerry the Curious', 'Wanting to understand the world', AppColors.gerryAmber),
      ('zena', '🎨', 'Zena the Creative', 'Making something new exist', AppColors.zenaGreen),
    ];
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        for (final h in heroes) ...[
          InkWell(
            onTap: () => onPick(h.$1),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: h.$5.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: h.$5.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(h.$2, style: const TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.$3,
                          style: AppTextStyles.bodyLarge(context, color: h.$5)
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          h.$4,
                          style: AppTextStyles.caption(
                            context,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.lightTextSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  Step 2 — moment picker (top picks → see more → free text)
// ---------------------------------------------------------------------------

class _MomentPicker extends StatelessWidget {
  final String hero;
  final bool showAll;
  final bool customMode;
  final TextEditingController customCtrl;
  final ScrollController controller;
  final bool submitting;
  final String? error;
  final bool lockedToHero;
  final ValueChanged<String> onPickPreset;
  final VoidCallback onSeeMore;
  final VoidCallback onEnterCustom;
  final VoidCallback onSubmitCustom;
  final VoidCallback onBack;

  const _MomentPicker({
    required this.hero,
    required this.showAll,
    required this.customMode,
    required this.customCtrl,
    required this.controller,
    required this.submitting,
    required this.error,
    required this.lockedToHero,
    required this.onPickPreset,
    required this.onSeeMore,
    required this.onEnterCustom,
    required this.onSubmitCustom,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _heroColor(hero);
    final moments = showAll
        ? HeroMomentPool.allFor(hero)
        : HeroMomentPool.topPicks[hero] ?? const [];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              Row(
                children: [
                  if (!lockedToHero)
                    TextButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      label: const Text('Change character'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.lightTextSecondary,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  const Spacer(),
                  _HeroChip(hero: hero, accent: accent),
                ],
              ),
              const SizedBox(height: 8),
              for (final m in moments)
                _MomentTile(
                  text: m,
                  accent: accent,
                  onTap: submitting ? null : () => onPickPreset(m),
                ),
              if (!showAll) ...[
                const SizedBox(height: 6),
                Center(
                  child: TextButton.icon(
                    onPressed: onSeeMore,
                    icon: const Icon(PhosphorIconsRegular.caretDown),
                    label: const Text('See more moments'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (customMode)
                _CustomEntry(
                  controller: customCtrl,
                  accent: accent,
                  submitting: submitting,
                  onSubmit: onSubmitCustom,
                )
              else
                OutlinedButton.icon(
                  onPressed: submitting ? null : onEnterCustom,
                  icon: const Icon(PhosphorIconsRegular.pencilSimple),
                  label: const Text('Write our own moment'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.lightBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.adminRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    error!,
                    style: AppTextStyles.body(
                      context,
                      color: AppColors.adminRed,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Each logged moment is +5 XP for that character, and 3 logs per kid per day.',
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MomentTile extends StatelessWidget {
  final String text;
  final Color accent;
  final VoidCallback? onTap;
  const _MomentTile({
    required this.text,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.lightBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(child: Text(text, style: AppTextStyles.body(context))),
              const Icon(Icons.add_circle_outline,
                  color: AppColors.lightTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomEntry extends StatelessWidget {
  final TextEditingController controller;
  final Color accent;
  final bool submitting;
  final VoidCallback onSubmit;
  const _CustomEntry({
    required this.controller,
    required this.accent,
    required this.submitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLength: 280,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'What did they do? In your own words.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('Log it'),
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String hero;
  final Color accent;
  const _HeroChip({required this.hero, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_heroEmoji(hero), style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            _heroName(hero),
            style: AppTextStyles.caption(context, color: accent).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Helpers
// ---------------------------------------------------------------------------

String _heroEmoji(String hero) => switch (hero) {
      'rafi' => '🛡️',
      'ellie' => '❤️',
      'gerry' => '🔍',
      'zena' => '🎨',
      _ => '✨',
    };

String _heroName(String hero) => switch (hero) {
      'rafi' => 'Rafi',
      'ellie' => 'Ellie',
      'gerry' => 'Gerry',
      'zena' => 'Zena',
      _ => 'Hero',
    };

Color _heroColor(String hero) => switch (hero) {
      'rafi' => AppColors.rafiCoral,
      'ellie' => AppColors.ellieBlue,
      'gerry' => AppColors.gerryAmber,
      'zena' => AppColors.zenaGreen,
      _ => AppColors.navy,
    };
