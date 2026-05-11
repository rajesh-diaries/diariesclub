import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/hero_recap_provider.dart';
import '../../core/providers/reflection_moments_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/error_screen.dart';
import '../../core/widgets/primary_button.dart';
import 'widgets/split_summary_sheet.dart';
import 'widgets/stage_transition_overlay.dart';
import 'widgets/trait_section.dart';

/// The reflection ritual. 12 cards in 4 trait sections, sticky bottom bar
/// with the count + Continue + "I'll do this later". On submit, plays the
/// stage-transition cinematic (if any), then the split-summary sheet.
class ReflectionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ReflectionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  final Set<String> _selected = <String>{};
  bool _submitting = false;
  String? _errorText;

  void _toggle(String tag) {
    setState(() {
      if (!_selected.add(tag)) _selected.remove(tag);
      _errorText = null;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_selected.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save your reflection?'),
        content: Text(
          "You've tapped ${_selected.length} moment${_selected.length == 1 ? '' : 's'}. "
          'Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.adminRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _close() async {
    final ok = await _confirmDiscard();
    if (!ok || !mounted) return;
    context.go('/home');
  }

  Future<void> _submit({required String childName, required String childId}) async {
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    Map<String, dynamic> result;
    try {
      result = await Supabase.instance.client.rpc<Map<String, dynamic>>(
        'reflection_submit',
        params: {
          'p_session_id': widget.sessionId,
          'p_moment_tags': _selected.toList(),
        },
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = _mapError(e.message);
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = "Couldn't save reflection. Please try again.";
      });
      return;
    }

    if (!mounted) return;

    final transitionsJson =
        (result['transitions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final transitions =
        transitionsJson.map(StageTransition.fromJson).toList();
    final split = (result['split'] as Map?)?.cast<String, dynamic>() ?? const {};
    final intSplit = <String, int>{
      for (final t in const ['rafi', 'ellie', 'gerry', 'zena'])
        t: (split[t] as int?) ?? 0,
    };

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (transitions.isNotEmpty && !reduceMotion) {
      // Push the cinematic as a transparent route. When it completes,
      // we pop it then show the summary sheet.
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (_, __, ___) => StageTransitionOverlay(
            transitions: transitions,
            childName: childName,
            onComplete: () =>
                Navigator.of(context, rootNavigator: true).maybePop(),
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => SplitSummarySheet(
        split: intSplit,
        childName: childName,
        childId: childId,
      ),
    );
  }

  String _mapError(String msg) {
    if (msg.contains('reflection_already_done')) {
      return 'This reflection was already saved.';
    }
    if (msg.contains('reflection_window_expired')) {
      return 'The reflection window has closed.';
    }
    if (msg.contains('recap_not_ready')) {
      return "Recap isn't ready yet. Try again in a moment.";
    }
    return "Couldn't save reflection. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    final recapAsync = ref.watch(heroRecapBySessionProvider(widget.sessionId));
    final momentsAsync = ref.watch(reflectionMomentsProvider(widget.sessionId));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: recapAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => FriendlyErrorScreen(
            code: 'E-RFL',
            userMessage: "Couldn't load reflection",
            technicalDetails: e.toString(),
          ),
          data: (recap) {
            if (recap == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("This recap doesn't exist anymore."),
                ),
              );
            }
            final childName =
                ((recap['children'] as Map?)?['name'] as String?) ?? 'Today';
            final childId = recap['child_id'] as String;

            return momentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => FriendlyErrorScreen(
                code: 'E-RFL-2',
                userMessage: "Couldn't load reflection moments",
                technicalDetails: e.toString(),
              ),
              data: (moments) => _Body(
                childName: childName,
                moments: moments,
                selected: _selected,
                onToggle: _toggle,
                errorText: _errorText,
                bottomBar: _BottomBar(
                  selectedCount: _selected.length,
                  submitting: _submitting,
                  onSubmit: () => _submit(
                    childName: childName,
                    childId: childId,
                  ),
                  onLater: _close,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String childName;
  final List<dynamic> moments;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? errorText;
  final Widget bottomBar;

  const _Body({
    required this.childName,
    required this.moments,
    required this.selected,
    required this.onToggle,
    required this.errorText,
    required this.bottomBar,
  });

  @override
  Widget build(BuildContext context) {
    final byTrait = <String, List<dynamic>>{};
    for (final m in moments) {
      byTrait.putIfAbsent(m.primaryTrait as String, () => []).add(m);
    }
    const order = ['rafi', 'ellie', 'gerry', 'zena'];

    // crossAxisAlignment.stretch is load-bearing here: bottomBar contains
    // a SizedBox(width: double.infinity) wrapping PrimaryButton. Without
    // stretch, children get loose horizontal constraints and the infinite
    // width propagates → "BoxConstraints forces an infinite width" on web,
    // blanking the screen with no recoverable AppBar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How was $childName today?',
                          style: AppTextStyles.h1(context)),
                      const SizedBox(height: 6),
                      Text(
                        'Tap moments that felt true. We split XP across the '
                        'four characters based on what you tap.',
                        style: AppTextStyles.body(
                          context,
                          color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final trait in order)
                  TraitSection(
                    trait: trait,
                    cards: (byTrait[trait] ?? const []).cast(),
                    selectedTags: selected,
                    onToggle: onToggle,
                  ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      errorText!,
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.adminRed,
                      ),
                    ),
                  ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
        bottomBar,
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int selectedCount;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onLater;

  const _BottomBar({
    required this.selectedCount,
    required this.submitting,
    required this.onSubmit,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.lightBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selectedCount == 0
                  ? 'Tap any moments that felt true'
                  : "$selectedCount moment${selectedCount == 1 ? '' : 's'} tapped",
              style: AppTextStyles.caption(
                context,
                color: AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: selectedCount == 0
                    ? 'Skip and split equally'
                    : 'Continue',
                onPressed: submitting ? null : onSubmit,
                loading: submitting,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: submitting ? null : onLater,
              child: Text(
                "I'll do this later",
                style: AppTextStyles.caption(
                  context,
                  color: AppColors.lightTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
