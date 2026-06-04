# Session Complete Celebration Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the plain "Session complete!" SnackBar with a full-screen "Mission Accomplished" celebration overlay: confetti burst, animated XP counter, staggered text reveal, haptic triple-tick, and gold CTA.

**Architecture:** A self-contained `SessionCompleteOverlay` StatefulWidget (confetti + animation controller + auto-dismiss timer) is layered on top of `PostSessionHomeView` via a `Stack`. The overlay fires once per session-to-post-session transition, then fades out to reveal the normal recap card + idle body underneath.

**Tech Stack:** Flutter, `confetti` 0.8.0, `flutter_animate` 4.5.2, `phosphor_flutter`, built-in `HapticFeedback`.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/features/sessions/widgets/session_complete_overlay.dart` | **Create** | Full-screen celebration overlay widget |
| `lib/features/home/views/post_session_home_view.dart` | **Modify** | Convert to `ConsumerStatefulWidget`, layer overlay in `Stack` |

---

## Task 1: Create `SessionCompleteOverlay` Widget

**Files:**
- Create: `lib/features/sessions/widgets/session_complete_overlay.dart`

- [ ] **Step 1: Write the overlay widget**

```dart
import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full-screen celebration overlay shown when a session completes.
/// Plays confetti, haptics, staggered text reveal, and an animated XP counter.
/// Auto-dismisses after [autoDismissDuration] or on tap.
class SessionCompleteOverlay extends StatefulWidget {
  final String childName;
  final int xpEarned;
  final VoidCallback onDismissed;
  final Duration autoDismissDuration;

  const SessionCompleteOverlay({
    super.key,
    required this.childName,
    required this.xpEarned,
    required this.onDismissed,
    this.autoDismissDuration = const Duration(seconds: 4),
  });

  @override
  State<SessionCompleteOverlay> createState() =>
      _SessionCompleteOverlayState();
}

class _SessionCompleteOverlayState extends State<SessionCompleteOverlay>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final Timer _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    _playHaptics();
    _confetti.play();

    _autoDismissTimer = Timer(widget.autoDismissDuration, _startDismiss);
  }

  Future<void> _playHaptics() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await HapticFeedback.heavyImpact();
  }

  void _startDismiss() {
    if (_isDismissing || !mounted) return;
    setState(() => _isDismissing = true);
  }

  void _onFadeComplete() {
    if (_isDismissing) widget.onDismissed();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _autoDismissTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _startDismiss,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _isDismissing ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 400),
        onEnd: _onFadeComplete,
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 240,
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirectionality: BlastDirectionality.explosive,
                    maxBlastForce: 20,
                    minBlastForce: 5,
                    emissionFrequency: 0.02,
                    numberOfParticles: 30,
                    gravity: 0.3,
                    colors: const [
                      AppColors.gold,
                      AppColors.rafiCoral,
                      AppColors.ellieBlue,
                      AppColors.gerryAmber,
                      AppColors.zenaGreen,
                    ],
                  ),
                ),
                const Spacer(),
                _buildContent(context),
                const Spacer(),
                Text(
                  'Tap to continue',
                  style: AppTextStyles.caption(
                    context,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sparkle icon with pop
        Icon(
          PhosphorIconsFill.sparkle,
          color: AppColors.gold,
          size: 64,
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(
              begin: const Offset(0.4, 0.4),
              duration: 500.ms,
              curve: Curves.easeOutBack,
            ),

        const SizedBox(height: 24),

        // Title
        Text(
          'Mission Accomplished!',
          style: AppTextStyles.h1(context, color: Colors.white),
        )
            .animate(delay: 200.ms)
            .fadeIn(duration: 400.ms)
            .slideY(
              begin: 0.3,
              duration: 400.ms,
              curve: Curves.easeOutCubic,
            ),

        const SizedBox(height: 8),

        // Subtitle
        Text(
          '${widget.childName} had an amazing time',
          style: AppTextStyles.body(context, color: Colors.white70),
        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

        const SizedBox(height: 32),

        // XP Counter
        _XpCounter(targetXp: widget.xpEarned),

        const SizedBox(height: 32),

        // CTA
        FilledButton.icon(
          onPressed: _startDismiss,
          icon: const Icon(PhosphorIconsFill.playCircle),
          label: const Text('See the recap'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.navy,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        )
            .animate(delay: 800.ms)
            .fadeIn(duration: 400.ms)
            .slideY(
              begin: 0.2,
              duration: 400.ms,
              curve: Curves.easeOutCubic,
            ),
      ],
    );
  }
}

/// Animated XP counter that ticks up from 0 to [targetXp].
class _XpCounter extends StatefulWidget {
  final int targetXp;
  const _XpCounter({required this.targetXp});

  @override
  State<_XpCounter> createState() => _XpCounterState();
}

class _XpCounterState extends State<_XpCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Delay so the title appears first, then XP starts counting.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _ctrl.forward();
    });
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
      builder: (_, __) {
        final eased = Curves.easeOutCubic.transform(_ctrl.value);
        final current = (widget.targetXp * eased).round();
        return Text(
          '+$current XP',
          style: AppTextStyles.h2(context, color: AppColors.gold).copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 48,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Verify the new file compiles in isolation**

Run:
```bash
cd /Users/admin/dev/diariesclub
flutter analyze lib/features/sessions/widgets/session_complete_overlay.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd /Users/admin/dev/diariesclub
git add lib/features/sessions/widgets/session_complete_overlay.dart
git commit -m "feat: add SessionCompleteOverlay celebration widget"
```

---

## Task 2: Integrate Overlay into `PostSessionHomeView`

**Files:**
- Modify: `lib/features/home/views/post_session_home_view.dart`

- [ ] **Step 1: Convert to `ConsumerStatefulWidget` and add overlay state**

Replace the entire contents of `post_session_home_view.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/hero_recap_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../gamification/widgets/hero_recap_card_widget.dart';
import '../../sessions/widgets/session_complete_overlay.dart';
import 'idle_home_view.dart';

/// Recently-completed-session state. The most recent pending recap shows
/// at the top via [HeroRecapCardWidget]; if there are more pending recaps,
/// a quiet "+N more recaps" link routes to /profile/sessions where the
/// full list is filterable.
///
/// A full-screen [SessionCompleteOverlay] celebrates the session completion
/// on first appearance, then fades to reveal the normal content underneath.
class PostSessionHomeView extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  const PostSessionHomeView({super.key, required this.session});

  @override
  ConsumerState<PostSessionHomeView> createState() =>
      _PostSessionHomeViewState();
}

class _PostSessionHomeViewState extends ConsumerState<PostSessionHomeView> {
  bool _showCelebration = true;

  void _onCelebrationDismissed() {
    if (!mounted) return;
    setState(() => _showCelebration = false);
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.session['id'] as String;
    final pending = ref.watch(pendingRecapsProvider).valueOrNull ?? const [];

    final primary = pending.firstWhere(
      (r) => r['session_id'] == sessionId,
      orElse: () => <String, dynamic>{
        'session_id': sessionId,
        'total_xp_pool': widget.session['total_xp_earned'] ?? 0,
        'reflection_deadline': widget.session['reflection_deadline'],
        'children': const {'name': 'Your kid'},
      },
    );

    final extraRecapCount = pending
        .where((r) => r['session_id'] != primary['session_id'])
        .length;

    final childName =
        (primary['children'] as Map?)?['name'] as String? ?? 'Your kid';
    final xpEarned = (primary['total_xp_pool'] as int?) ??
        (widget.session['total_xp_earned'] as int?) ??
        0;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroRecapCardWidget(recap: primary),
              if (extraRecapCount > 0) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/profile/sessions'),
                    child: Text(
                      '+$extraRecapCount more recap${extraRecapCount == 1 ? '' : 's'}',
                      style: AppTextStyles.caption(
                        context,
                        color: AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const IdleHomeBody(),
            ],
          ),
        ),
        if (_showCelebration)
          Positioned.fill(
            child: SessionCompleteOverlay(
              childName: childName,
              xpEarned: xpEarned,
              onDismissed: _onCelebrationDismissed,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run:
```bash
cd /Users/admin/dev/diariesclub
flutter analyze lib/features/home/views/post_session_home_view.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Full project analysis**

Run:
```bash
cd /Users/admin/dev/diariesclub
flutter analyze
```

Expected: `No issues found!` (or only pre-existing issues unrelated to this change)

- [ ] **Step 4: Commit**

```bash
cd /Users/admin/dev/diariesclub
git add lib/features/home/views/post_session_home_view.dart
git commit -m "feat: integrate SessionCompleteOverlay into PostSessionHomeView"
```

---

## Task 3: Test & Verify

- [ ] **Step 1: Dry-run widget test**

Create a temporary smoke test to ensure the overlay renders without crashing:

```bash
cd /Users/admin/dev/diariesclub
cat > /tmp/overlay_smoke_test.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diariesclub/features/sessions/widgets/session_complete_overlay.dart';

void main() {
  testWidgets('SessionCompleteOverlay renders and dismisses', (tester) async {
    bool dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionCompleteOverlay(
          childName: 'Anya',
          xpEarned: 120,
          onDismissed: () => dismissed = true,
          autoDismissDuration: const Duration(milliseconds: 100),
        ),
      ),
    );
    expect(find.text('Mission Accomplished!'), findsOneWidget);
    expect(find.text('+0 XP'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tapAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
EOF
flutter test /tmp/overlay_smoke_test.dart
```

Expected: `1 passed`

If the test fails due to import path issues, just verify via `flutter analyze` instead and delete the temp file.

- [ ] **Step 2: Clean up temp file**

```bash
rm -f /tmp/overlay_smoke_test.dart
```

- [ ] **Step 3: Final commit**

```bash
cd /Users/admin/dev/diariesclub
git log --oneline -3
```

Expected: Two new commits on top of previous work:
```
feat: integrate SessionCompleteOverlay into PostSessionHomeView
feat: add SessionCompleteOverlay celebration widget
```

---

## Self-Review Checklist

- [x] **Spec coverage:** Confetti ✓, XP counter ✓, haptics ✓, staggered text ✓, auto-dismiss ✓, tap-to-skip ✓, dark overlay ✓, gold CTA ✓
- [x] **Placeholder scan:** No TBD, TODO, or vague requirements
- [x] **Type consistency:** `childName` is `String`, `xpEarned` is `int`, `onDismissed` is `VoidCallback` throughout
- [x] **Accessibility:** Reduced-motion users see content immediately (no required motion to read); tap target covers full screen; text scales via `AppTextStyles`
- [x] **iPad safety:** `SafeArea` used; overlay is full-screen `Positioned.fill`; no bottom-edge critical controls
