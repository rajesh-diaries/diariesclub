import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/providers/reflection_moments_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Multi-select sheet opened from the reflection screen's "+ More moments"
/// tile. Lets the parent pick extra preset moments from the wider pool
/// or write their own, then returns the selections back to the
/// reflection screen so they contribute to the SAME 50 XP pool split
/// (each custom moment counts as 1.0 weight on its trait, same as a
/// preset reflection moment with weight 1.0).
///
/// Visual model is multi-select: tap toggles selection, selected items
/// fill with the trait color so the parent can see what's in.
class ReflectionMoreMomentsSheet extends ConsumerStatefulWidget {
  final String trait;
  final Set<String> initialSelections;
  const ReflectionMoreMomentsSheet({
    super.key,
    required this.trait,
    required this.initialSelections,
  });

  @override
  ConsumerState<ReflectionMoreMomentsSheet> createState() =>
      _ReflectionMoreMomentsSheetState();
}

class _ReflectionMoreMomentsSheetState
    extends ConsumerState<ReflectionMoreMomentsSheet> {
  late final Set<String> _selected = {...widget.initialSelections};
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _toggle(String text) {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_selected.add(text)) _selected.remove(text);
    });
  }

  void _addCustom() {
    final txt = _customCtrl.text.trim();
    if (txt.isEmpty || txt.length > 280) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selected.add(txt);
      _customCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = _traitColor(widget.trait);
    final asyncPool = ref.watch(
      extendedReflectionMomentsProvider(widget.trait),
    );
    final pool = asyncPool.maybeWhen(
      data: (rows) => rows.map((r) => r.displayText).toList(),
      orElse: () => const <String>[],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
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
                            'More ${_traitName(widget.trait)} moments',
                            style: AppTextStyles.h2(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap as many as fit. They split the same XP pool.',
                            style: AppTextStyles.caption(
                              context,
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(null),
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
                    for (final m in pool)
                      _MultiSelectTile(
                        text: m,
                        accent: accent,
                        selected: _selected.contains(m),
                        onTap: () => _toggle(m),
                      ),
                    const SizedBox(height: 14),
                    _CustomEntry(
                      controller: _customCtrl,
                      accent: accent,
                      onSubmit: _addCustom,
                    ),
                    if (_selected.where((s) => !pool.contains(s)).isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Your custom moments',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      for (final s in _selected.where((s) => !pool.contains(s)))
                        _MultiSelectTile(
                          text: s,
                          accent: accent,
                          selected: true,
                          onTap: () => _toggle(s),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? 'Done'
                          : 'Add ${_selected.length} moment'
                              '${_selected.length == 1 ? '' : 's'}',
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

class _MultiSelectTile extends StatelessWidget {
  final String text;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;
  const _MultiSelectTile({
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
            color:
                selected ? accent.withValues(alpha: 0.14) : AppColors.lightSurface,
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
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _CustomEntry extends StatelessWidget {
  final TextEditingController controller;
  final Color accent;
  final VoidCallback onSubmit;
  const _CustomEntry({
    required this.controller,
    required this.accent,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Or write your own',
            style: AppTextStyles.caption(
              context,
              color: AppColors.lightTextSecondary,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLength: 280,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What did they do?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: accent, width: 2),
              ),
              suffixIcon: IconButton(
                tooltip: 'Add',
                icon: const Icon(PhosphorIconsRegular.plusCircle),
                onPressed: onSubmit,
              ),
            ),
          ),
        ],
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
      _ => AppColors.navy,
    };
