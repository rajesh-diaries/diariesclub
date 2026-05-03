# Session 6 — Gamification + Hero Traits + Reflection

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-5 + 5b complete.

---

## Session Header

```
I am building Diaries Club. Database, RPCs, foundation, auth, home, profile all done.
This session: build the gamification system — Hero Recap card, reflection ritual,
trait stage system, and stage-transition reveal experiences.

Estimated time: 5-6 hours
What to build:
  - Hero Recap Card generation (server + client display)
  - Reflection screen with 12-card grid (3 per trait)
  - Trait stage transition reveals (cinematic animation, anywhere)
  - "1-session-away" push notification trigger
  - Trait-progress visualisation (4 hero strips with stage indicators)
  - Stage transition history (mini timeline per child)
  - Auto-split fallback flow (24h after session, no reflection)
  - Hero card unboxing flow (Healthy Bite distribution → reveal animation)
  - Reflection-skipped UX (gentle re-prompt, never punitive)

What NOT to build:
  - Adventure tab full layout (Session 8 — that uses these widgets)
  - Workshop attendance XP (Session 7)
  - Birthday-host XP bonus (Session 9)
  - Reflection auto-split cron (Session 13)

Output expected:
  - Hero Recap card visible on Home post-session-completion
  - Reflection screen functional, calls reflection_submit RPC
  - Stage transitions trigger Lottie animation overlays
  - All 12 reflection cards configurable from database (3 per trait)
  - Trait progress widgets reusable across Adventure tab + Profile

Acceptance:
  - Complete a session → Hero Recap card appears on Home within 30s
  - Tap recap → reflection screen, 12 cards visible (3 per trait)
  - Tap 3-5 cards → "Continue" → XP split via reflection_submit RPC
  - If reflection causes stage transition → cinematic plays after submit
  - Skip reflection (close screen) → returns to Home, recap still tappable
  - 24h later: cron fires reflection_auto_split → notification appears
  - Healthy Bite earned during session → unboxing animation when staff distributes
```

---

## 1. Gamification Architecture

### 1.1 The 4 traits + 4 heroes

Locked decision (from earlier sessions):
- **Rafi** = Brave, coral red
- **Ellie** = Kind, sky blue
- **Gerry** = Curious, amber
- **Zena** = Creative, green

Each child has independent XP for each trait (`xp_rafi`, `xp_ellie`, `xp_gerry`, `xp_zena`). Each trait progresses through 5 stages:

1. Seedling (0 XP)
2. Explorer (50 XP)
3. Adventurer (150 XP)
4. Champion (350 XP)
5. Legend (700 XP)

Overall level (1-20) is computed from total XP across all 4 traits, mapped via `venue_config.level_thresholds`.

### 1.2 The reflection ritual

Locked decision: 12 cards visible per recap (3 per trait), parent taps the moments that felt true, those weights determine XP split.

The 24-card pool (6 per trait) lives in `reflection_moments` table. Each recap shows 12 randomly selected (3 per trait, no repetition within a single recap).

### 1.3 Why this matters

This is the magic moment of the app. The session ends, the recap appears, the parent reflects on what their child did, and the heroes "earn" XP based on those moments. It transforms a play visit into a story the parent participates in writing.

If this ritual doesn't land, the rest of the gamification system feels hollow.

---

## 2. Schema Adjustments

The seed data in Session 1 had 8 reflection moments. Need to expand to 24 (6 per trait):

```sql
-- Migration: 0003_reflection_moments_expanded.sql

-- Clear existing seed (idempotent)
DELETE FROM reflection_moments;

INSERT INTO reflection_moments (tag, display_text, primary_trait, sort_order, icon) VALUES
  -- Rafi (Brave) — 6 cards
  ('tried_something_new',     'Tried something new',          'rafi',  10, 'rocket'),
  ('took_a_leap',             'Took a leap',                  'rafi',  20, 'arrow_fat_up'),
  ('faced_a_fear',            'Faced something they feared',  'rafi',  30, 'shield_check'),
  ('led_the_way',             'Led the way',                  'rafi',  40, 'flag'),
  ('kept_trying',             'Kept trying after stumbling',  'rafi',  50, 'arrow_clockwise'),
  ('went_first',              'Went first when others paused','rafi',  60, 'star'),

  -- Ellie (Kind) — 6 cards
  ('shared_with_friend',      'Shared with a friend',         'ellie', 110, 'gift'),
  ('helped_a_friend',          'Helped a friend',              'ellie', 120, 'hand_heart'),
  ('checked_on_someone',       'Checked on someone upset',     'ellie', 130, 'smiley'),
  ('included_someone_new',     'Included someone new',         'ellie', 140, 'users'),
  ('said_thank_you',           'Said thank you on their own',  'ellie', 150, 'heart'),
  ('gave_a_compliment',        'Gave a compliment',            'ellie', 160, 'sparkle'),

  -- Gerry (Curious) — 6 cards
  ('asked_questions',          'Asked lots of questions',      'gerry', 210, 'question'),
  ('explored_new_corner',      'Explored a new corner',        'gerry', 220, 'compass'),
  ('figured_it_out',           'Figured something out',        'gerry', 230, 'lightbulb'),
  ('observed_carefully',       'Watched carefully before doing','gerry',240, 'eye'),
  ('connected_two_things',     'Connected two ideas',          'gerry', 250, 'graph'),
  ('learned_a_word',           'Learned a new word or phrase', 'gerry', 260, 'book_open'),

  -- Zena (Creative) — 6 cards
  ('made_up_a_game',           'Made up a game',               'zena',  310, 'puzzle_piece'),
  ('drew_or_built',            'Drew or built something',      'zena',  320, 'palette'),
  ('imagined_a_story',         'Imagined a story',             'zena',  330, 'feather'),
  ('mixed_things_unusually',   'Mixed things in a new way',    'zena',  340, 'shuffle'),
  ('performed_for_others',     'Performed or showed off art',  'zena',  350, 'microphone'),
  ('reused_something',         'Used something for a new purpose','zena',360, 'recycle')
;
```

### 2.1 Random-12 selection RPC

Recap-time selection is server-side to avoid client tampering:

```sql
CREATE OR REPLACE FUNCTION reflection_moments_for_recap(p_recap_id UUID)
RETURNS TABLE(id UUID, tag TEXT, display_text TEXT, primary_trait TEXT, icon TEXT, xp_weight DECIMAL)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  -- For each trait, pick 3 random cards
  RETURN QUERY
  WITH ranked AS (
    SELECT
      id, tag, display_text, primary_trait, icon, xp_weight,
      ROW_NUMBER() OVER (
        PARTITION BY primary_trait
        ORDER BY md5(p_recap_id::text || tag) -- deterministic random per recap
      ) as rn
    FROM reflection_moments
    WHERE is_active = true
  )
  SELECT id, tag, display_text, primary_trait, icon, xp_weight
  FROM ranked
  WHERE rn <= 3
  ORDER BY primary_trait, sort_order;
END $$;

GRANT EXECUTE ON FUNCTION reflection_moments_for_recap TO authenticated, service_role;
```

**Why deterministic random per recap?** If the parent opens the recap, then closes the app, then opens it again, the same 12 cards must appear (otherwise their progress through reflection is lost). Hashing the recap_id + tag gives a stable random ordering per recap.

---

## 3. Hero Recap Card Generation

### 3.1 When recap is created

Triggered automatically by session completion (Edge Function in Session 13). For now, the spec describes the flow; build the client-side display + reflection submission.

The recap row is created in `hero_recaps` table when a session moves to `completed` status. It includes:
- `total_xp_pool`: total XP this session earned (e.g., 60 for a 1hr session at 1 XP/min, plus bonuses)
- `image_url`: generated PNG by Edge Function (visual recap with child's name + duration + traits earned)
- `reflection_status = 'pending'`
- `reflection_deadline`: completed_at + 24h (configurable)

### 3.2 Recap card on Home

Already referenced in Session 5 as the "post_session" Home state. Now, the actual card:

```dart
class HeroRecapCardWidget extends ConsumerWidget {
  final HeroRecap recap;
  const HeroRecapCardWidget({super.key, required this.recap});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final child = ref.watch(childByIdProvider(recap.childId)).valueOrNull;

    return GestureDetector(
      onTap: () => context.push('/reflection/${recap.sessionId}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A4A8B), AppColors.navy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle confetti pattern background
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Opacity(
                  opacity: 0.06,
                  child: Image.asset(
                    'assets/images/confetti_pattern.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PhosphorIcon(PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                        color: AppColors.gold, size: 22),
                      const SizedBox(width: 8),
                      Text("Hero Recap",
                        style: AppTextStyles.caption(c, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${child?.name ?? 'Your hero'} had an adventure!",
                    style: AppTextStyles.h2(c, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Tap to see what they earned",
                    style: AppTextStyles.body(c, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),

                  // XP earned chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      "+${recap.totalXpPool} XP to share",
                      style: AppTextStyles.caption(c, color: AppColors.gold),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // CTA
                  Row(
                    children: [
                      Text(
                        "Reflect on the session",
                        style: AppTextStyles.button(c, color: AppColors.gold),
                      ),
                      const SizedBox(width: 4),
                      PhosphorIcon(PhosphorIcons.arrowRight(), color: AppColors.gold, size: 18),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Time-pressure caption
                  if (_hoursUntilDeadline(recap.reflectionDeadline) < 6)
                    Text(
                      "Reflection closes in ${_hoursUntilDeadline(recap.reflectionDeadline)}h",
                      style: AppTextStyles.caption(c, color: AppColors.warningYellow),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _hoursUntilDeadline(DateTime deadline) {
    final diff = deadline.difference(DateTime.now()).inHours;
    return diff < 0 ? 0 : diff;
  }
}
```

### 3.3 Recap on Home: visibility rules

- Show if user has `hero_recaps` rows where `reflection_status = 'pending'` AND `reflection_deadline > now()`
- Multiple pending recaps: show most recent only on Home, with a "+2 more recaps" link below if there are others
- After reflection or auto-split: card disappears from Home; viewable from Profile → Past Sessions

---

## 4. Reflection Screen — `lib/features/gamification/reflection_screen.dart`

This is THE screen.

### 4.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [✕]                                  │
│ (no title — keep it focused)        │
├─────────────────────────────────────┤
│ HEADER                              │
│ "How was Aarav today?"              │
│ "Tap moments that felt true."       │
├─────────────────────────────────────┤
│ TRAIT SECTION HEADERS               │
│                                     │
│ [Rafi avatar] BRAVE                 │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ 🚀   │ │ 🛡    │ │ ⭐   │          │
│ │Tried │ │Faced │ │Went  │          │
│ │new   │ │fear  │ │first │          │
│ └──────┘ └──────┘ └──────┘          │
│                                     │
│ [Ellie avatar] KIND                 │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ 🎁   │ │ ❤    │ │ ✨   │          │
│ │Shared│ │Said  │ │Comp- │          │
│ │      │ │thanks│ │liment│          │
│ └──────┘ └──────┘ └──────┘          │
│                                     │
│ [Gerry avatar] CURIOUS              │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ ❓   │ │ 💡   │ │ 📖   │          │
│ │Asked │ │Fig-  │ │Lear- │          │
│ │qs    │ │ured  │ │ned   │          │
│ └──────┘ └──────┘ └──────┘          │
│                                     │
│ [Zena avatar] CREATIVE              │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ 🧩   │ │ 🎨   │ │ ♻    │          │
│ │Game  │ │Drew  │ │Reuse │          │
│ │      │ │built │ │      │          │
│ └──────┘ └──────┘ └──────┘          │
├─────────────────────────────────────┤
│ STICKY BOTTOM BAR                   │
│ "3 moments tapped"                  │
│ [Continue] PRIMARY (gold)           │
│                                     │
│ [I'll do this later]  text link     │
└─────────────────────────────────────┘
```

### 4.2 Card states

Each card has 3 visual states:
- **Untapped**: white background, soft border, gentle icon color
- **Tapped**: trait color background (coral/blue/amber/green), white text, bouncing animation on tap
- **Disabled**: only after submit succeeds, briefly shown before navigation

### 4.3 Implementation

```dart
class ReflectionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const ReflectionScreen({super.key, required this.sessionId});
  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  final Set<String> _selectedTags = {};
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext c) {
    final moments = ref.watch(reflectionMomentsProvider(widget.sessionId));
    final recap = ref.watch(heroRecapBySessionProvider(widget.sessionId));
    final child = recap.valueOrNull?.childId != null
      ? ref.watch(childByIdProvider(recap.value!.childId))
      : null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmSkip(c),
        ),
        elevation: 0,
        backgroundColor: Theme.of(c).scaffoldBackgroundColor,
      ),
      body: moments.when(
        data: (cards) => CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "How was ${child?.value?.name ?? 'today'}?",
                      style: AppTextStyles.h1(c),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tap moments that felt true.",
                      style: AppTextStyles.body(c,
                        color: AppColors.lightTextSecondary),
                    ),
                  ],
                ),
              ),
            ),

            // Group by trait
            ..._buildTraitSections(c, cards),

            // Bottom padding for sticky bar
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-RFL', userMessage: 'Couldn\'t load reflection'),
      ),
      bottomSheet: _buildBottomBar(c),
    );
  }

  List<Widget> _buildTraitSections(BuildContext c, List<ReflectionMoment> cards) {
    final byTrait = groupBy(cards, (m) => m.primaryTrait);
    final order = ['rafi', 'ellie', 'gerry', 'zena'];

    return order.map((trait) {
      final traitCards = byTrait[trait] ?? [];
      return SliverToBoxAdapter(child: _TraitSection(
        trait: trait,
        cards: traitCards,
        selectedTags: _selectedTags,
        onTap: (tag) => setState(() {
          if (_selectedTags.contains(tag)) {
            _selectedTags.remove(tag);
          } else {
            _selectedTags.add(tag);
          }
          HapticFeedback.lightImpact();
        }),
      ));
    }).toList();
  }

  Widget _buildBottomBar(BuildContext c) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(c).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(c).scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selectedTags.isEmpty
              ? "Tap any moments that felt true"
              : "${_selectedTags.length} moment${_selectedTags.length == 1 ? '' : 's'} tapped",
            style: AppTextStyles.caption(c),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _selectedTags.isEmpty ? "Skip and split equally" : "Continue",
            onPressed: _isSubmitting ? null : _submit,
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmSkip(c),
            child: Text("I'll do this later",
              style: AppTextStyles.caption(c)),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final result = await Supabase.instance.client.rpc(
        'reflection_submit',
        params: {
          'p_session_id': widget.sessionId,
          'p_moment_tags': _selectedTags.toList(),
        },
      );

      // Check for stage transitions in result
      final transitions = (result['transitions'] as List?) ?? [];

      if (mounted) {
        if (transitions.isNotEmpty) {
          // Show stage transition cinematic
          await _playStageTransition(transitions);
        }

        // Show split summary
        await _showSplitSummary(result['split']);

        // Return to home
        if (mounted) context.go('/home');
      }
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      setState(() => _isSubmitting = false);
      _showError(c, "Couldn't save reflection. Please try again.");
    }
  }

  void _confirmSkip(BuildContext c) async {
    if (_selectedTags.isEmpty) {
      // Nothing tapped, no confirmation needed
      Navigator.pop(c);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text("Save your reflection?"),
        content: Text(
          "You've tapped ${_selectedTags.length} moments. "
          "Continue without saving?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Continue")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Discard")),
        ],
      ),
    );

    if (confirmed == true && mounted) Navigator.pop(c);
  }
}
```

### 4.4 Trait section + card widgets

```dart
class _TraitSection extends StatelessWidget {
  final String trait;
  final List<ReflectionMoment> cards;
  final Set<String> selectedTags;
  final void Function(String) onTap;

  const _TraitSection({
    required this.trait,
    required this.cards,
    required this.selectedTags,
    required this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trait header
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _traitColor(trait),
                child: Text(_heroName(trait)[0],
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Text(_traitName(trait),
                style: AppTextStyles.caption(c).copyWith(letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),

          // Cards (3 per trait, 3-column grid)
          Row(
            children: cards.map((card) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ReflectionCard(
                  card: card,
                  isSelected: selectedTags.contains(card.tag),
                  onTap: () => onTap(card.tag),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  String _heroName(String t) => switch (t) {
    'rafi' => 'Rafi', 'ellie' => 'Ellie',
    'gerry' => 'Gerry', 'zena' => 'Zena', _ => '?',
  };
  String _traitName(String t) => switch (t) {
    'rafi' => 'BRAVE', 'ellie' => 'KIND',
    'gerry' => 'CURIOUS', 'zena' => 'CREATIVE', _ => '',
  };
  Color _traitColor(String t) => switch (t) {
    'rafi' => AppColors.rafiCoral,
    'ellie' => AppColors.ellieBlue,
    'gerry' => AppColors.gerryAmber,
    'zena' => AppColors.zenaGreen,
    _ => Colors.grey,
  };
}

class _ReflectionCard extends StatelessWidget {
  final ReflectionMoment card;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final color = _traitColor(card.primaryTrait);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Material(
        color: isSelected ? color : Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : AppColors.lightBorder,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: PhosphorIcon(
                    _iconForName(card.icon),
                    size: 36,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  card.displayText,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(c,
                    color: isSelected ? Colors.white : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### 4.5 Reflection moments provider

```dart
@riverpod
Future<List<ReflectionMoment>> reflectionMoments(
  ReflectionMomentsRef ref, String sessionId,
) async {
  // Get the recap row to find recap_id
  final recap = await Supabase.instance.client
    .from('hero_recaps')
    .select()
    .eq('session_id', sessionId)
    .single();

  // Fetch the deterministic 12 cards for this recap
  final response = await Supabase.instance.client.rpc(
    'reflection_moments_for_recap',
    params: {'p_recap_id': recap['id']},
  );

  return (response as List).map((r) => ReflectionMoment.fromJson(r)).toList();
}
```

---

## 5. Stage Transition Cinematic

When `reflection_submit` returns a non-empty `transitions` array (e.g., Rafi crossed from Explorer → Adventurer), we play a Lottie animation overlay BEFORE returning to Home.

### 5.1 Transition reveal flow

```
1. Reflection submitted, RPC returns transitions: [{trait: 'rafi', from: 'explorer', to: 'adventurer'}]
2. Show full-screen overlay (Hero animation hero, transitions = list of stage changes)
3. For each transition (one at a time):
   - Lottie animation plays (~3-5 seconds, branded celebratory)
   - Hero illustration scales up
   - "Rafi grew up" text + "Now: Adventurer" badge
   - Auto-advance after 3 seconds OR tap to continue
4. After all transitions done → Show split summary → Home
```

### 5.2 Implementation

```dart
class StageTransitionOverlay extends StatefulWidget {
  final List<StageTransition> transitions;
  final VoidCallback onComplete;

  @override
  State<StageTransitionOverlay> createState() => _StageTransitionOverlayState();
}

class _StageTransitionOverlayState extends State<StageTransitionOverlay>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..forward().whenComplete(_advance);
  }

  void _advance() {
    if (!mounted) return;
    if (_currentIndex < widget.transitions.length - 1) {
      setState(() => _currentIndex++);
      _controller.reset();
      _controller.forward().whenComplete(_advance);
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext c) {
    final t = widget.transitions[_currentIndex];
    final hero = t.trait;

    return GestureDetector(
      onTap: _advance,
      child: Container(
        color: Colors.black.withOpacity(0.92),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),

              // Lottie celebration animation
              SizedBox(
                width: 240, height: 240,
                child: Lottie.asset(
                  'assets/lottie/stage_transition_${hero}.json',
                  controller: _controller,
                ),
              ),

              const SizedBox(height: 32),

              // Hero name
              Text(_heroName(hero) + " grew up!",
                style: AppTextStyles.h1(c, color: Colors.white)),

              const SizedBox(height: 12),

              // Stage transition
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _traitColor(hero).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _traitColor(hero), width: 2),
                ),
                child: Text(
                  "${_stageLabel(t.from)} → ${_stageLabel(t.to)}",
                  style: AppTextStyles.body(c, color: Colors.white),
                ),
              ),

              const Spacer(),

              // Counter
              if (widget.transitions.length > 1)
                Text(
                  "${_currentIndex + 1} of ${widget.transitions.length}",
                  style: AppTextStyles.caption(c, color: Colors.white54),
                ),

              const SizedBox(height: 12),
              Text("Tap to continue",
                style: AppTextStyles.caption(c, color: Colors.white38)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 5.3 The "1-session-away" notification

When XP credit (any source) brings a child within 50 XP of the next stage, fire a push notification:

```sql
-- In xp_credit_with_split, after applying XP, check thresholds:
-- If new trait XP is >= (next_stage_threshold - 50) and < next_stage_threshold,
-- AND no notification already sent for this near-stage,
-- INSERT into notifications:

INSERT INTO notifications (
  family_id, type, title, body, deep_link, reference_id
) VALUES (
  v_family_id, 'stage_transition_imminent',
  v_child_name || ' is close to a milestone',
  _heroName(v_trait) || ' is one good session away from ' || _next_stage_name || '!',
  '/adventure',
  v_child_id
);
```

This nudge gets parents back to the venue. The ACTUAL stage transition reveal happens during the next reflection.

---

## 6. Split Summary Screen

After reflection_submit succeeds, show a brief summary of the XP split (no transition involved).

### 6.1 Layout

```
┌─────────────────────────────────────┐
│         [✕]                          │
│                                     │
│    ✨ Saved!                        │
│                                     │
│    Aarav earned:                    │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [Rafi avatar]    +24 XP     │   │
│  │ Brave                       │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [Ellie avatar]   +12 XP     │   │
│  │ Kind                        │   │
│  └─────────────────────────────┘   │
│                                     │
│    +0 XP for Gerry (untapped)       │
│    +0 XP for Zena (untapped)        │
│                                     │
│    [See Aarav's adventure →]        │
└─────────────────────────────────────┘
```

This screen lasts ~5 seconds before auto-dismissing to Home, OR the parent can tap "See Aarav's adventure" to navigate to Adventure tab (Session 8).

---

## 7. Auto-Split Notification (24h Later)

If parent doesn't reflect within 24h, the cron `reflection_auto_split` (Session 13 Edge Function) runs and splits XP equally across all 4 traits.

When this happens, a notification appears:

```dart
// notifications row inserted by reflection_auto_split RPC
{
  'family_id': v_family_id,
  'type': 'reflection_auto_split',
  'title': 'XP shared across all four heroes',
  'body': 'You didn\'t reflect on the session, so we split XP equally.',
  'deep_link': '/adventure',
  'reference_id': v_recap.session_id,
}
```

**Tone is non-punitive.** Never make the parent feel bad for missing it.

The Hero Recap card on Home disappears once `reflection_status` flips to `auto_split`. From Profile → Past Sessions, the user can still see the recap (read-only — moments not tappable anymore).

---

## 8. Hero Card Unboxing Flow (Healthy Bite)

When staff distributes a Healthy Bite (via Staff app, Session 10), the `healthy_bite_distribute` RPC creates a hero_card_collection row. The parent gets a notification, opens the app, and sees:

### 8.1 Unboxing screen — `/cards/unbox/:cardId`

```dart
class CardUnboxingScreen extends ConsumerStatefulWidget {
  final String cardId;
  // ...
}
```

Layout:
```
┌─────────────────────────────────────┐
│ DARK GRADIENT BACKGROUND            │
│                                     │
│         "A new card!"               │
│                                     │
│       [Animated card back]          │
│       (gold rays radiating)         │
│                                     │
│       [Tap to reveal]               │
│                                     │
└─────────────────────────────────────┘
```

On tap:
1. Card flip animation (Rive or Flutter native AnimatedSwitcher with rotation)
2. Reveals card front
3. If RARE: extra confetti + golden glow + haptic feedback
4. Card name + description appears below
5. "Add to collection ✓" auto-marks
6. CTA at bottom: "See all cards" → `/adventure/cards`

### 8.2 Common vs Rare differentiation

| Property | Common | Rare |
|---|---|---|
| Reveal animation | 1.5s flip | 3s flip with delay + sparkles |
| Background | Soft glow | Gold rays, particle effect |
| Haptic | Light impact | Heavy impact + repeated medium |
| Sound (optional) | Soft ding | Trumpet flourish |

Don't oversell rare cards (shouldn't feel like gambling). 10% draw rate per the locked decision is honest.

---

## 9. Trait Progress Widgets

Reusable across Adventure tab and Profile. Two main widgets:

### 9.1 `TraitProgressBar` — single trait

```dart
class TraitProgressBar extends StatelessWidget {
  final String trait;            // 'rafi' | 'ellie' | 'gerry' | 'zena'
  final int currentXp;
  final String currentStage;
  final List<int> stageThresholds;
  final bool compact;

  @override
  Widget build(BuildContext c) {
    final nextThreshold = _nextThreshold();
    final progress = _progressTowardNext();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(radius: compact ? 14 : 18, backgroundColor: _color()),
            const SizedBox(width: 8),
            Text(_heroName(), style: compact ? AppTextStyles.caption(c) : AppTextStyles.body(c)),
            const Spacer(),
            Text("$currentXp XP", style: AppTextStyles.caption(c)),
          ],
        ),
        const SizedBox(height: 4),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.lightBorder,
            valueColor: AlwaysStoppedAnimation(_color()),
            minHeight: compact ? 6 : 10,
          ),
        ),

        if (!compact) ...[
          const SizedBox(height: 4),
          Text(
            "Stage: ${_stageLabel(currentStage)}"
            "${nextThreshold != null ? ' • Next at ${nextThreshold} XP' : ' • Max stage'}",
            style: AppTextStyles.caption(c),
          ),
        ],
      ],
    );
  }
}
```

### 9.2 `TraitProgressGrid` — all 4 traits, compact 2x2

```dart
class TraitProgressGrid extends ConsumerWidget {
  final Child child;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: TraitProgressBar(trait: 'rafi', ...)),
          const SizedBox(width: 8),
          Expanded(child: TraitProgressBar(trait: 'ellie', ...)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TraitProgressBar(trait: 'gerry', ...)),
          const SizedBox(width: 8),
          Expanded(child: TraitProgressBar(trait: 'zena', ...)),
        ]),
      ],
    );
  }
}
```

---

## 10. Stage Transition History (Per Child)

Mini-timeline for the Adventure tab profile view (Session 8). Builds on `xp_events` table, looking for entries where stage changed.

```dart
@riverpod
Future<List<StageTransitionEntry>> childStageHistory(
  ChildStageHistoryRef ref, String childId,
) async {
  // Query xp_events that resulted in stage transitions (denormalised in metadata)
  final response = await Supabase.instance.client
    .from('xp_events')
    .select()
    .eq('child_id', childId)
    .not('metadata->stage_transitions', 'is', null)
    .order('created_at', ascending: true);

  return (response as List)
    .expand((row) => _extractTransitions(row))
    .toList();
}
```

Visual: vertical timeline, each entry shows date + "Rafi: Explorer → Adventurer" + small icon.

---

## 11. Files to Create

```
lib/
└── features/
    └── gamification/
        ├── reflection_screen.dart
        ├── widgets/
        │   ├── hero_recap_card_widget.dart
        │   ├── reflection_card.dart
        │   ├── trait_section.dart
        │   ├── trait_progress_bar.dart
        │   ├── trait_progress_grid.dart
        │   ├── stage_transition_overlay.dart
        │   ├── split_summary_sheet.dart
        │   └── stage_history_timeline.dart
        ├── card_unboxing_screen.dart
        └── providers/
            ├── reflection_moments_provider.dart
            ├── hero_recap_provider.dart
            ├── pending_recaps_provider.dart
            └── child_stage_history_provider.dart
```

---

## 12. Acceptance Tests

```
TEST 1 — Recap appears on Home
  1. Complete a session (or manually update sessions row to status='completed')
  2. hero_recaps row exists with reflection_status='pending'
  3. Home tab reloads → Hero Recap card visible
  4. Tap → /reflection/:sessionId

TEST 2 — Reflection screen layout
  1. Open reflection screen
  2. 4 trait sections visible (Rafi, Ellie, Gerry, Zena)
  3. Each section has 3 cards (12 total)
  4. Cards loaded from reflection_moments_for_recap RPC
  5. Reopening shows same 12 cards (deterministic)

TEST 3 — Tapping cards
  1. Tap a Rafi card → background turns coral, white text, haptic
  2. Counter updates: "1 moment tapped"
  3. Tap another → counter "2 moments tapped"
  4. Untap one → counter back to "1"

TEST 4 — Submit reflection
  1. Tap 4 cards (2 Rafi + 2 Ellie)
  2. Tap Continue → submit RPC fires
  3. Result: rafi gets ~50%, ellie gets ~50% of total_xp_pool
  4. Returns to Home, recap card gone

TEST 5 — Skip reflection (empty)
  1. Open reflection, don't tap anything
  2. Tap "Continue" or "Skip and split equally"
  3. Equal 25% split applied to all 4 traits

TEST 6 — Skip with selections
  1. Tap 3 cards, then tap [✕] back
  2. Confirmation dialog: "Save your reflection?"
  3. "Discard" → returns home, recap still pending
  4. "Continue" → stays on reflection

TEST 7 — Stage transition cinematic
  1. Set up child where xp_rafi = 49 (threshold for Explorer = 50)
  2. Submit reflection that gives Rafi +5 XP
  3. RPC returns transitions: [{rafi: seedling → explorer}]
  4. Lottie overlay plays
  5. After 3s OR tap → split summary → home
  6. Adventure tab shows Rafi as Explorer

TEST 8 — Multiple stage transitions
  1. Reflection causes Rafi (Explorer→Adventurer) AND Ellie (Seedling→Explorer)
  2. Cinematic plays Rafi first, then Ellie
  3. Counter shows "1 of 2", "2 of 2"

TEST 9 — Auto-split notification
  1. Set hero_recaps.reflection_deadline to 1 minute ago
  2. Manually trigger reflection_auto_split RPC
  3. notification row created with type='reflection_auto_split'
  4. Bell badge updates
  5. Recap card disappears from Home

TEST 10 — Hero card unboxing
  1. Manually insert hero_card_collection row + notification
  2. Tap notification → /cards/unbox/:cardId
  3. Card back visible with "Tap to reveal"
  4. Tap → flip animation → card front shows
  5. If is_rare=true → extra animation + haptic
  6. "See all cards" → /adventure/cards

TEST 11 — Stage-imminent push
  1. Set xp_ellie = 100 (within 50 of explorer threshold 150 — ah wait, threshold is 150 per Session 1 schema)
  2. Wait, recheck: trait_stage_thresholds = [0, 50, 150, 350, 700]
     So if currentXp = 100, next threshold = 150, gap = 50 → triggers
  3. Earn any XP → notification fires "Ellie is one good session away..."
  4. No more pushes for same near-stage until passed

TEST 12 — 1-session-away push (correct setup)
  1. xp_rafi = 305 (threshold for Champion = 350, gap = 45, < 50)
  2. After any XP grant, push fires (if not already sent)
  3. Earn enough XP to cross 350 → Champion stage applied (no extra push)
  4. Cinematic plays at next reflection
```

---

## 13. Open Items for Founder

- [ ] Confirm 24 reflection moment cards (6 per trait) — review wording
- [ ] Approve Lottie animation files for stage transitions (assets/lottie/stage_transition_*.json)
- [ ] Approve Lottie/Rive for card unboxing (assets/lottie/card_unbox_common.json + card_unbox_rare.json)
- [ ] Sound effects: include for v1 or defer? (Default: silent for v1, configurable)
- [ ] Confirm "1-session-away" gap of 50 XP (currently a constant; could move to venue_config)
- [ ] Confirm split summary dwell time (currently 5s auto-dismiss)
- [ ] Confirm reflection deadline (currently 24h via venue_config.reflection_window_hours)

---

## What's NOT in this session

- Adventure tab full layout (Session 8)
- Hero card collection grid view (Session 8 — Adventure tab)
- Workshop XP attribution (Session 7)
- Birthday-host XP bonus (Session 9)
- Cron auto-split trigger (Session 13 Edge Function)
- Edge Function generate-hero-recap (Session 13 — generates the image_url)
