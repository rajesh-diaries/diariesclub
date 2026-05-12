import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/parent_log_moments_data.dart';

/// Standalone parent-log sheet on the Adventure tab — "My kid did this".
///
/// Model mirrors the post-session reflection: ONE pool of XP gets split
/// across whatever the parent picks. Multi-select chips per character,
/// optional free-text per character, "Log it" submits the whole pool in
/// one server call (log_parent_moments_pool RPC).
///
/// Daily cap is 1 pool submission per kid per day.
class ParentLogMomentSheet extends ConsumerStatefulWidget {
  final String childId;
  final String childName;
  const ParentLogMomentSheet({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  ConsumerState<ParentLogMomentSheet> createState() =>
      _ParentLogMomentSheetState();
}

class _ParentLogMomentSheetState
    extends ConsumerState<ParentLogMomentSheet> {
  // Selections per trait: preset texts that are ticked + free-text adds
  final Map<String, Set<String>> _selected = {
    'rafi': <String>{},
    'ellie': <String>{},
    'gerry': <String>{},
    'zena': <String>{},
  };
  final Map<String, TextEditingController> _customCtrls = {
    'rafi': TextEditingController(),
    'ellie': TextEditingController(),
    'gerry': TextEditingController(),
    'zena': TextEditingController(),
  };
  final Map<String, bool> _expanded = {
    'rafi': true,
    'ellie': true,
    'gerry': true,
    'zena': true,
  };
  bool _submitting = false;
  String? _error;

  static const _traits = ['rafi', 'ellie', 'gerry', 'zena'];

  @override
  void dispose() {
    for (final c in _customCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _totalSelected =>
      _selected.values.fold<int>(0, (s, e) => s + e.length);

  void _toggle(String trait, String text) {
    HapticFeedback.lightImpact();
    setState(() {
      final set = _selected[trait]!;
      if (!set.add(text)) set.remove(text);
      _error = null;
    });
  }

  void _addCustom(String trait) {
    final txt = _customCtrls[trait]!.text.trim();
    if (txt.isEmpty || txt.length > 280) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selected[trait]!.add(txt);
      _customCtrls[trait]!.clear();
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_totalSelected == 0) {
      setState(() => _error = 'Tap a moment first, or write your own.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final payload = <Map<String, String>>[];
    _selected.forEach((trait, texts) {
      for (final t in texts) {
        payload.add({'trait': trait, 'text': t, 'source': 'pool'});
      }
    });

    try {
      final res = await Supabase.instance.client
          .rpc<Map<String, dynamic>>('log_parent_moments_pool', params: {
        'p_child_id': widget.childId,
        'p_moments': payload,
      });
      if (!mounted) return;
      final split = (res['split'] as Map?)?.cast<String, dynamic>() ?? const {};
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.activeGreen,
          content: Text(
            'Logged ${payload.length} moment${payload.length == 1 ? '' : 's'} · '
            '+${split['rafi'] ?? 0} Rafi · +${split['ellie'] ?? 0} Ellie · '
            '+${split['gerry'] ?? 0} Gerry · +${split['zena'] ?? 0} Zena',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (e.message.contains('daily_pool_cap_reached')) {
          _error =
              "You've already logged today's pool. Come back tomorrow or "
              'visit Diaries Club for more XP.';
        } else if (e.message.contains('invalid_text_length')) {
          _error = 'One of the moments is too long (max 280 chars).';
        } else if (e.message.contains('empty_submission')) {
          _error = 'Tap a moment first, or write your own.';
        } else {
          _error = "Couldn't log: ${e.message}";
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't log: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
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
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What did ${widget.childName} do today?',
                            style: AppTextStyles.h2(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap moments across all 4 characters. We split '
                            '50 XP across whatever you pick.',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  children: [
                    for (final trait in _traits)
                      _TraitGroup(
                        trait: trait,
                        selected: _selected[trait]!,
                        onToggle: (text) => _toggle(trait, text),
                        customCtrl: _customCtrls[trait]!,
                        onAddCustom: () => _addCustom(trait),
                        expanded: _expanded[trait] ?? true,
                        onToggleExpanded: () => setState(() {
                          _expanded[trait] = !(_expanded[trait] ?? true);
                        }),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.adminRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _error!,
                          style: AppTextStyles.body(
                            context,
                            color: AppColors.adminRed,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      "One pool per kid per day. The pool's 50 XP, split "
                      'proportionally across the characters you tapped.',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            _totalSelected == 0
                                ? 'Log it · 50 XP pool'
                                : 'Log it · $_totalSelected moment'
                                    '${_totalSelected == 1 ? '' : 's'} '
                                    '· 50 XP split',
                          ),
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

class _TraitGroup extends StatelessWidget {
  final String trait;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final TextEditingController customCtrl;
  final VoidCallback onAddCustom;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const _TraitGroup({
    required this.trait,
    required this.selected,
    required this.onToggle,
    required this.customCtrl,
    required this.onAddCustom,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _traitColor(trait);
    final pool = HeroMomentPool.topPicks[trait] ?? const [];
    final extras = HeroMomentPool.allFor(trait).where((m) => !pool.contains(m)).toList();
    final customs = selected.where((s) => !pool.contains(s) && !extras.contains(s)).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.18),
                    ),
                    child: Icon(_traitIcon(trait), color: accent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _traitName(trait).toUpperCase(),
                    style: AppTextStyles.caption(context, color: accent)
                        .copyWith(
                            letterSpacing: 1.4, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${_traitLabel(trait)}',
                    style: AppTextStyles.caption(
                      context,
                      color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (selected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${selected.length}',
                        style: AppTextStyles.caption(context, color: accent)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? PhosphorIconsRegular.caretUp
                        : PhosphorIconsRegular.caretDown,
                    color: AppColors.lightTextSecondary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            for (final m in pool)
              _Tile(
                text: m,
                accent: accent,
                selected: selected.contains(m),
                onTap: () => onToggle(m),
              ),
            ...[
              for (final m in extras)
                _Tile(
                  text: m,
                  accent: accent,
                  selected: selected.contains(m),
                  onTap: () => onToggle(m),
                ),
            ],
            for (final c in customs)
              _Tile(
                text: c,
                accent: accent,
                selected: true,
                onTap: () => onToggle(c),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.lightBorder),
              ),
              child: TextField(
                controller: customCtrl,
                maxLength: 280,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Or write your own ${_traitName(trait)} moment',
                  border: InputBorder.none,
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Add',
                    icon: const Icon(PhosphorIconsRegular.plusCircle),
                    onPressed: onAddCustom,
                  ),
                ),
                onSubmitted: (_) => onAddCustom(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String text;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _Tile({
    required this.text,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : AppColors.lightBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? accent : AppColors.lightBorder,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.body(context).copyWith(
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
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

// ---------------------------------------------------------------------------

String _traitName(String t) => switch (t) {
      'rafi' => 'Rafi',
      'ellie' => 'Ellie',
      'gerry' => 'Gerry',
      'zena' => 'Zena',
      _ => '',
    };

String _traitLabel(String t) => switch (t) {
      'rafi' => 'Brave',
      'ellie' => 'Kind',
      'gerry' => 'Curious',
      'zena' => 'Creative',
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
      _ => PhosphorIconsFill.star,
    };
