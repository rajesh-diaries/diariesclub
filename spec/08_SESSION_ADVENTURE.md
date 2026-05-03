# Session 8 — Adventure Tab

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-7 + 5b complete.

---

## Session Header

```
I am building Diaries Club. Database, RPCs, foundation, auth, home, profile,
gamification, club all done. This session: build the Adventure tab — the place
where the per-child journey lives.

Estimated time: 5-6 hours
What to build:
  - Adventure tab with per-child selector landing
  - Per-child Adventure dashboard:
    - Diaries World Map (4 territories, hero positions)
    - Trait progress strip (4 heroes, current stage + XP toward next)
    - Hero card collection (full grid: earned + locked silhouettes)
    - Stage transition history (timeline)
    - Recent achievements feed
    - Streak tracker
  - Wall of Legends sub-screen (anonymised social proof)
  - Cafe-only state (no children yet) — dignified empty state
  - Hero card detail screen (tap a card → fullscreen view + share)
  - Stats screen (lifetime XP per trait, sessions, hero card count, etc.)

What NOT to build:
  - Hero Recap card (already in Session 6)
  - Card unboxing flow (already in Session 6)
  - Reflection screen (already in Session 6)

Output expected:
  - Adventure tab fully functional
  - Per-child switching is smooth (drawer or top selector)
  - Hero card grid renders with locked silhouettes for unearned cards
  - Wall of Legends populates from wall_of_legends_daily table
  - Empty states for cafe-only families

Acceptance:
  - Tap Adventure tab → child selector visible
  - Pick child → world map + trait strip + cards visible
  - Earned hero card appears in correct slot, unearned shows silhouette
  - Switch child → all content updates to new child
  - Tap "Wall of Legends" → sub-screen with daily highlights
  - Cafe-only family sees empty state with "Add a child" CTA
```

---

## 1. Adventure Tab Architecture

### 1.1 Landing — child selector

Per locked decision, the entry point is "Which child?" before showing the adventure.

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ Adventure          [Wall of Legends]│
├─────────────────────────────────────┤
│                                     │
│ "Whose adventure?"                  │
│                                     │
│ ┌──────────┐  ┌──────────┐          │
│ │  AVATAR  │  │  AVATAR  │          │
│ │  Aarav   │  │  Riya    │          │
│ │  Lvl 12  │  │  Lvl 8   │          │
│ │ [Champion]│  │[Adventurer]        │
│ └──────────┘  └──────────┘          │
│                                     │
└─────────────────────────────────────┘
```

If only one child: skip selector entirely, jump straight to that child's dashboard.

If cafe-only (no children): empty state.

### 1.2 Persistent selection

Once a child is picked, persist the selection so coming back to Adventure tab returns to that child by default. Top of dashboard has a small avatar + "Tap to switch" affordance.

```dart
@riverpod
class SelectedAdventureChildId extends _$SelectedAdventureChildId {
  @override
  String? build() {
    // Restore from SharedPreferences if any, else pick first child
    SharedPreferences.getInstance().then((p) {
      final stored = p.getString('selected_adventure_child');
      if (stored != null) state = stored;
    });
    return null;
  }

  Future<void> select(String childId) async {
    state = childId;
    final p = await SharedPreferences.getInstance();
    await p.setString('selected_adventure_child', childId);
  }

  Future<void> clear() async {
    state = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('selected_adventure_child');
  }
}
```

### 1.3 Dashboard structure (post-selection)

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [< switch] Aarav's adventure        │
│                       [Wall, Stats] │
├─────────────────────────────────────┤
│                                     │
│ DIARIES WORLD MAP (~280 high)       │
│ Hero positions on 4 territories     │
│                                     │
├─────────────────────────────────────┤
│ TRAIT PROGRESS STRIP                │
│ ┌──────┬──────┬──────┬──────┐       │
│ │ Rafi │Ellie │Gerry │ Zena │       │
│ │ 240  │ 180  │ 95   │ 320  │       │
│ │[bar] │[bar] │[bar] │[bar] │       │
│ │ Adv  │ Exp  │ Exp  │ Cham │       │
│ └──────┴──────┴──────┴──────┘       │
├─────────────────────────────────────┤
│ STREAK TRACKER                      │
│ 🔥 3 weeks · keep it up!            │
├─────────────────────────────────────┤
│ HERO CARD COLLECTION (preview)      │
│ "12 of 40 collected"  [See all →]   │
│ [3-card horizontal preview]         │
├─────────────────────────────────────┤
│ RECENT ACHIEVEMENTS                 │
│ • Rafi reached Adventurer  Mar 28   │
│ • Earned a rare card       Mar 25   │
│ • Hit 3-week streak        Mar 20   │
├─────────────────────────────────────┤
│ STAGE TRANSITION HISTORY            │
│ [Mini timeline of all transitions]  │
└─────────────────────────────────────┘
```

---

## 2. Adventure Screen — `lib/features/adventure/adventure_screen.dart`

### 2.1 Top-level routing

```dart
class AdventureScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final children = ref.watch(familyChildrenProvider);
    final selectedId = ref.watch(selectedAdventureChildIdProvider);

    return children.when(
      data: (kids) {
        if (kids.isEmpty) return const _CafeOnlyEmptyState();
        if (kids.length == 1) {
          // Auto-select single child
          if (selectedId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(selectedAdventureChildIdProvider.notifier).select(kids.first.id);
            });
          }
          return _ChildAdventureDashboard(childId: kids.first.id);
        }

        // Multi-child: show selector or dashboard based on selection
        if (selectedId == null) {
          return _ChildSelectorScreen(children: kids);
        }
        return _ChildAdventureDashboard(childId: selectedId);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => FriendlyErrorScreen(code: 'E-ADV', userMessage: 'Couldn\'t load adventure'),
    );
  }
}
```

### 2.2 Cafe-only empty state

```dart
class _CafeOnlyEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text("Adventure")),
    body: SafeArea(child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/heroes_idle_group.png', height: 180),
            const SizedBox(height: 32),
            Text(
              "Adventures await!",
              style: AppTextStyles.h1(c),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Add a child to your family to start their journey with Rafi, "
              "Ellie, Gerry, and Zena.",
              style: AppTextStyles.body(c, color: AppColors.lightTextSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: "Add a child",
              onPressed: () => context.push('/profile/add-child'),
            ),
          ],
        ),
      ),
    )),
  );
}
```

### 2.3 Child selector screen

```dart
class _ChildSelectorScreen extends ConsumerWidget {
  final List<Child> children;
  const _ChildSelectorScreen({required this.children});

  @override
  Widget build(BuildContext c, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text("Adventure"),
      actions: [
        TextButton(
          onPressed: () => context.push('/adventure/wall-of-legends'),
          child: Text("Wall of Legends",
            style: AppTextStyles.caption(c, color: AppColors.gold)),
        ),
      ],
    ),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Whose adventure?", style: AppTextStyles.h1(c)),
          const SizedBox(height: 8),
          Text("Pick a hero to follow today.",
            style: AppTextStyles.body(c, color: AppColors.lightTextSecondary)),
          const SizedBox(height: 32),

          Expanded(
            child: GridView.count(
              crossAxisCount: children.length == 1 ? 1 : 2,
              crossAxisSpacing: 16, mainAxisSpacing: 16,
              children: children.map((child) =>
                _ChildSelectCard(
                  child: child,
                  onTap: () {
                    ref.read(selectedAdventureChildIdProvider.notifier).select(child.id);
                  },
                ),
              ).toList(),
            ),
          ),
        ],
      ),
    )),
  );
}

class _ChildSelectCard extends ConsumerWidget {
  final Child child;
  final VoidCallback onTap;
  const _ChildSelectCard({required this.child, required this.onTap});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(c).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withOpacity(0.3), width: 2),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar with hero ring
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _heroColor(child.favouriteHero),
                  width: 3,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                radius: 48,
                backgroundImage: child.photoUrl != null
                  ? CachedNetworkImageProvider(child.photoUrl!) as ImageProvider
                  : null,
                child: child.photoUrl == null
                  ? Text(child.name[0],
                      style: AppTextStyles.h2(c, color: Colors.white))
                  : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(child.name, style: AppTextStyles.h3(c)),
            const SizedBox(height: 4),
            Text("Level ${child.currentLevel}",
              style: AppTextStyles.caption(c)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _stageLabel(child.currentOverallStage),
                style: AppTextStyles.caption(c, color: AppColors.gold)
                  .copyWith(letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 3. Per-Child Dashboard — `lib/features/adventure/child_adventure_dashboard.dart`

### 3.1 Top app bar with switcher

```dart
class _ChildAdventureDashboard extends ConsumerWidget {
  final String childId;
  const _ChildAdventureDashboard({required this.childId});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final child = ref.watch(childByIdProvider(childId));
    final children = ref.watch(familyChildrenProvider).valueOrNull ?? [];
    final canSwitch = children.length > 1;

    return Scaffold(
      appBar: AppBar(
        leading: canSwitch
          ? IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ref.read(selectedAdventureChildIdProvider.notifier).clear(),
            )
          : null,
        title: child.when(
          data: (c) => Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _heroColor(c.favouriteHero),
                backgroundImage: c.photoUrl != null
                  ? CachedNetworkImageProvider(c.photoUrl!) as ImageProvider
                  : null,
              ),
              const SizedBox(width: 8),
              Text("${c.name}'s adventure"),
            ],
          ),
          loading: () => const Text("Adventure"),
          error: (_, __) => const Text("Adventure"),
        ),
        actions: [
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.chartBar()),
            onPressed: () => context.push('/adventure/stats?childId=$childId'),
          ),
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.trophy()),
            onPressed: () => context.push('/adventure/wall-of-legends'),
          ),
        ],
      ),
      body: child.when(
        data: (c) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DiariesWorldMap(child: c),
              const SizedBox(height: 16),
              TraitProgressStrip(child: c),
              const SizedBox(height: 16),
              StreakTrackerWidget(childId: c.id),
              const SizedBox(height: 16),
              HeroCardCollectionPreview(childId: c.id),
              const SizedBox(height: 16),
              RecentAchievements(childId: c.id),
              const SizedBox(height: 16),
              StageHistoryTimeline(childId: c.id),
              const SizedBox(height: 24),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-DASH', userMessage: 'Couldn\'t load'),
      ),
    );
  }
}
```

---

## 4. Diaries World Map — `lib/features/adventure/widgets/diaries_world_map.dart`

The hero visual element of the Adventure tab.

### 4.1 Layout

```
┌─────────────────────────────────────┐
│                                     │
│  [Top-down map illustration]        │
│                                     │
│   🏔 Rafi's Mountain                │
│        [hero icon at stage]         │
│                                     │
│   🌳 Gerry's Forest                 │
│        [hero icon]                  │
│                                     │
│   🌸 Ellie's Meadow                 │
│        [hero icon]                  │
│                                     │
│   🎨 Zena's Studio                  │
│        [hero icon]                  │
│                                     │
└─────────────────────────────────────┘
```

The map is a single SVG/PNG illustration (asset 2.3 from pre-launch checklist). Each hero's icon is positioned over their territory at the visual representation of their current stage.

### 4.2 Implementation

```dart
class DiariesWorldMap extends StatelessWidget {
  final Child child;
  const DiariesWorldMap({super.key, required this.child});

  @override
  Widget build(BuildContext c) {
    return AspectRatio(
      aspectRatio: 1.4, // wide map
      child: Stack(
        children: [
          // Background map
          Positioned.fill(
            child: Image.asset(
              'assets/images/diaries_world_map.png',
              fit: BoxFit.cover,
            ),
          ),

          // Hero at Rafi's territory (top-left)
          _HeroOnMap(
            hero: 'rafi',
            stage: child.stageRafi,
            xp: child.xpRafi,
            position: const Alignment(-0.6, -0.6),
          ),

          // Ellie's territory (top-right)
          _HeroOnMap(
            hero: 'ellie',
            stage: child.stageEllie,
            xp: child.xpEllie,
            position: const Alignment(0.6, -0.6),
          ),

          // Gerry's territory (bottom-left)
          _HeroOnMap(
            hero: 'gerry',
            stage: child.stageGerry,
            xp: child.xpGerry,
            position: const Alignment(-0.6, 0.6),
          ),

          // Zena's territory (bottom-right)
          _HeroOnMap(
            hero: 'zena',
            stage: child.stageZena,
            xp: child.xpZena,
            position: const Alignment(0.6, 0.6),
          ),
        ],
      ),
    );
  }
}

class _HeroOnMap extends StatelessWidget {
  final String hero;
  final String stage;
  final int xp;
  final Alignment position;

  @override
  Widget build(BuildContext c) {
    return Align(
      alignment: position,
      child: GestureDetector(
        onTap: () => _showHeroDetailSheet(c),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero illustration at current stage
            SizedBox(
              width: 64, height: 64,
              child: Image.asset(
                'assets/hero/${hero}_${stage}_idle.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(100),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Text(
                _stageLabel(stage),
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: _heroColor(hero),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHeroDetailSheet(BuildContext c) =>
    showModalBottomSheet(
      context: c,
      builder: (_) => HeroDetailSheet(hero: hero, stage: stage, xp: xp),
    );
}
```

### 4.3 Hero detail sheet (tap a hero on map)

```dart
class HeroDetailSheet extends StatelessWidget {
  final String hero;
  final String stage;
  final int xp;

  @override
  Widget build(BuildContext c) {
    final stages = ['seedling', 'explorer', 'adventurer', 'champion', 'legend'];
    final currentIndex = stages.indexOf(stage);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(c).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hero illustration big
          SizedBox(
            height: 160,
            child: Image.asset('assets/hero/${hero}_${stage}_idle.png'),
          ),
          const SizedBox(height: 16),
          Text(_heroName(hero),
            style: AppTextStyles.h1(c, color: _heroColor(hero))),
          const SizedBox(height: 4),
          Text(_traitName(hero),
            style: AppTextStyles.caption(c).copyWith(letterSpacing: 1.5)),
          const SizedBox(height: 16),

          // Stage progression visual
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: stages.asMap().entries.map((entry) {
              final isPast = entry.key < currentIndex;
              final isCurrent = entry.key == currentIndex;
              return Column(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPast || isCurrent
                        ? _heroColor(hero)
                        : AppColors.lightBorder,
                      border: isCurrent
                        ? Border.all(color: AppColors.gold, width: 3)
                        : null,
                    ),
                    alignment: Alignment.center,
                    child: Text("${entry.key + 1}",
                      style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 4),
                  Text(_stageLabel(entry.value),
                    style: AppTextStyles.caption(c).copyWith(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    )),
                ],
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          Text("Current: ${_stageLabel(stage)}",
            style: AppTextStyles.body(c)),
          Text("$xp XP earned",
            style: AppTextStyles.caption(c)),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
```

---

## 5. Trait Progress Strip

Reuses `TraitProgressGrid` component from Session 6, but in horizontal/strip layout:

```dart
class TraitProgressStrip extends StatelessWidget {
  final Child child;
  @override
  Widget build(BuildContext c) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Hero progress", style: AppTextStyles.bodyLarge(c)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _CompactTraitProgress(
                hero: 'rafi', xp: child.xpRafi, stage: child.stageRafi)),
              const SizedBox(width: 8),
              Expanded(child: _CompactTraitProgress(
                hero: 'ellie', xp: child.xpEllie, stage: child.stageEllie)),
              const SizedBox(width: 8),
              Expanded(child: _CompactTraitProgress(
                hero: 'gerry', xp: child.xpGerry, stage: child.stageGerry)),
              const SizedBox(width: 8),
              Expanded(child: _CompactTraitProgress(
                hero: 'zena', xp: child.xpZena, stage: child.stageZena)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactTraitProgress extends StatelessWidget {
  final String hero;
  final int xp;
  final String stage;

  @override
  Widget build(BuildContext c) {
    final progress = _calculateProgressToNext(stage, xp);

    return Column(
      children: [
        SizedBox(
          width: 56, height: 56,
          child: Image.asset('assets/hero/${hero}_${stage}_idle.png'),
        ),
        const SizedBox(height: 4),
        Text(_heroName(hero).toUpperCase(),
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold,
            color: _heroColor(hero),
          )),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.lightBorder,
            valueColor: AlwaysStoppedAnimation(_heroColor(hero)),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text("$xp XP",
          style: AppTextStyles.caption(c).copyWith(fontSize: 10)),
      ],
    );
  }
}
```

---

## 6. Streak Tracker Widget

```
┌─────────────────────────────────────┐
│ 🔥 Visit streak: 3 weeks            │
│ Keep it up! Visit again by Sunday   │
│ to extend your streak.              │
│                                     │
│ Best ever: 7 weeks                  │
└─────────────────────────────────────┘
```

```dart
class StreakTrackerWidget extends ConsumerWidget {
  final String childId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final streak = ref.watch(childStreakProvider(childId));

    return streak.when(
      data: (s) {
        if (s.currentStreakWeeks == 0) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB347), Color(0xFFE8524A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Text("🔥", style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${s.currentStreakWeeks} week${s.currentStreakWeeks == 1 ? '' : 's'} streak",
                      style: AppTextStyles.h3(c, color: Colors.white),
                    ),
                    Text(
                      _streakSubtext(s),
                      style: AppTextStyles.caption(c, color: Colors.white70),
                    ),
                    if (s.longestStreakWeeks > s.currentStreakWeeks) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Best ever: ${s.longestStreakWeeks} weeks",
                        style: AppTextStyles.caption(c, color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  String _streakSubtext(StreakRecord s) {
    final daysUntilEndOfWeek = 7 - DateTime.now().weekday;
    if (daysUntilEndOfWeek <= 2) {
      return "Keep it up! Visit by Sunday to extend.";
    }
    return "Streak is safe through this week.";
  }
}
```

---

## 7. Hero Card Collection Preview + Full Grid

### 7.1 Preview on dashboard

```dart
class HeroCardCollectionPreview extends ConsumerWidget {
  final String childId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final earned = ref.watch(earnedCardsProvider(childId));
    final total = ref.watch(totalCardCountProvider);

    return earned.when(
      data: (cards) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(c).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Hero card collection",
                        style: AppTextStyles.bodyLarge(c)),
                      Text("${cards.length} of ${total.value ?? 0} collected",
                        style: AppTextStyles.caption(c)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/adventure/cards?childId=$childId'),
                  child: Text("See all",
                    style: AppTextStyles.button(c, color: AppColors.navy)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Last 3 earned, horizontal
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: cards.length.clamp(0, 5),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _MiniCardThumbnail(card: cards[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

### 7.2 Full grid screen — `/adventure/cards`

```dart
class HeroCardCollectionScreen extends ConsumerWidget {
  final String childId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final allCards = ref.watch(allHeroCardDefinitionsProvider);
    final earnedCardIds = ref.watch(earnedCardIdsProvider(childId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hero card collection"),
        actions: [
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.funnel()),
            onPressed: () => _showFilterSheet(c),
          ),
        ],
      ),
      body: allCards.when(
        data: (cards) => CustomScrollView(
          slivers: [
            // Stats banner
            SliverToBoxAdapter(child: _CollectionStatsBanner(
              earned: earnedCardIds.value?.length ?? 0,
              total: cards.length,
            )),

            // Card grid
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 5/7, // standard trading-card ratio
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (c, i) {
                    final card = cards[i];
                    final isEarned = earnedCardIds.value?.contains(card.id) ?? false;
                    return _CardGridItem(
                      card: card,
                      isEarned: isEarned,
                      childId: childId,
                    );
                  },
                  childCount: cards.length,
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-CARDS', userMessage: 'Couldn\'t load cards'),
      ),
    );
  }
}

class _CardGridItem extends StatelessWidget {
  final HeroCardDefinition card;
  final bool isEarned;
  final String childId;

  @override
  Widget build(BuildContext c) {
    return GestureDetector(
      onTap: isEarned
        ? () => context.push('/adventure/card/${card.id}')
        : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: card.isRare && isEarned
              ? AppColors.gold
              : AppColors.lightBorder,
            width: card.isRare && isEarned ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Card image (with silhouette treatment if not earned)
              if (isEarned)
                CachedNetworkImage(
                  imageUrl: card.imageUrl,
                  fit: BoxFit.cover,
                )
              else
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0, 0, 0, 0, 30,    // R
                    0, 0, 0, 0, 30,    // G
                    0, 0, 0, 0, 50,    // B
                    0, 0, 0, 0.5, 0,   // A (50% opacity)
                  ]),
                  child: CachedNetworkImage(
                    imageUrl: card.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),

              // Locked overlay
              if (!isEarned)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    alignment: Alignment.center,
                    child: PhosphorIcon(
                      PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
                      color: Colors.white54, size: 32,
                    ),
                  ),
                ),

              // Rare indicator
              if (card.isRare && isEarned)
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                    child: PhosphorIcon(
                      PhosphorIcons.star(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 12,
                    ),
                  ),
                ),

              // Birthday-exclusive indicator
              if (card.isBirthdayExclusive && isEarned)
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.coral,
                      shape: BoxShape.circle,
                    ),
                    child: PhosphorIcon(
                      PhosphorIcons.cake(PhosphorIconsStyle.fill),
                      color: Colors.white, size: 12,
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
```

### 7.3 Card detail screen — `/adventure/card/:cardId`

Tap an earned card → fullscreen detail view.

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back]                       [share]│
├─────────────────────────────────────┤
│                                     │
│        [Large card image]           │
│        (zoomable, pinch-to-zoom)    │
│                                     │
├─────────────────────────────────────┤
│ Card name                           │
│ ⭐ Rare card                        │
│ 🎂 Birthday Edition                 │
├─────────────────────────────────────┤
│ Description                         │
│ Story / lore text about the card    │
├─────────────────────────────────────┤
│ EARNED ON                           │
│ Saturday, March 28                  │
│ During Aarav's 2-hour session       │
│                                     │
│ [Share this card]   PRIMARY          │
└─────────────────────────────────────┘
```

Share button generates a shareable image (composed by Edge Function — see Session 13) and opens system share sheet.

---

## 8. Recent Achievements Feed

Pulls from `xp_events`, `hero_card_collection`, `streak_records`, `gift_redemptions`. Limit 5, newest first.

```dart
class RecentAchievements extends ConsumerWidget {
  final String childId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final feed = ref.watch(achievementFeedProvider(childId));

    return feed.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(c).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Recent achievements", style: AppTextStyles.bodyLarge(c)),
              const SizedBox(height: 12),
              ...entries.take(5).map((e) => _AchievementRow(entry: e)),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final AchievementEntry entry;
  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _achievementColor(entry.type).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: PhosphorIcon(
              _achievementIcon(entry.type),
              color: _achievementColor(entry.type),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: AppTextStyles.body(c)),
                Text(
                  _formatTimeago(entry.timestamp),
                  style: AppTextStyles.caption(c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 9. Stage Transition History Timeline

A vertical timeline showing every stage transition for this child, oldest first.

```dart
class StageHistoryTimeline extends ConsumerWidget {
  final String childId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final history = ref.watch(childStageHistoryProvider(childId));

    return history.when(
      data: (transitions) {
        if (transitions.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(c).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Hero milestones", style: AppTextStyles.bodyLarge(c)),
              const SizedBox(height: 12),
              ...transitions.map((t) => _TimelineEntry(transition: t)),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

Each entry:
```
[hero icon] Rafi reached Adventurer
            March 28
```

---

## 10. Stats Screen — `/adventure/stats?childId=...`

Detailed per-child stats. More for parents who like data than for daily use.

### 10.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ Aarav's stats                       │
├─────────────────────────────────────┤
│ HERO SECTION                        │
│ Aarav · Level 12 · Champion         │
├─────────────────────────────────────┤
│ XP BREAKDOWN (per trait, bars)      │
│ Rafi   ████████░░░  240/350         │
│ Ellie  ████████████ 180/150 ✓       │
│ Gerry  ████░░░░░░░░  95/150         │
│ Zena   ████████████ 320/350         │
├─────────────────────────────────────┤
│ LIFETIME STATS                      │
│ Sessions completed:        18       │
│ Total play time:    36h 30min       │
│ Workshops attended:         5       │
│ Hero cards earned:    14 of 40      │
│ Rare cards:                 3       │
│ Birthdays celebrated:       2       │
│ Streak best:           7 weeks      │
│ Streak current:        3 weeks      │
├─────────────────────────────────────┤
│ FAVOURITE TIME OF WEEK              │
│ [bar chart of session days]         │
│ Saturdays are your favourite        │
└─────────────────────────────────────┘
```

### 10.2 Implementation note

Stats are computed from existing tables — no new schema needed. Provider:

```dart
@riverpod
Future<ChildStats> childStats(ChildStatsRef ref, String childId) async {
  final supabase = Supabase.instance.client;

  final sessionsCount = await supabase.from('sessions').select('id', const FetchOptions(count: CountOption.exact))
    .eq('child_id', childId).eq('status', 'completed');

  final totalMinutes = await supabase.from('sessions')
    .select('duration_minutes')
    .eq('child_id', childId).eq('status', 'completed');
  final sumMinutes = (totalMinutes as List).fold<int>(0, (s, r) => s + (r['duration_minutes'] as int));

  // ... etc

  return ChildStats(
    sessionsCompleted: sessionsCount.count ?? 0,
    totalMinutes: sumMinutes,
    // ...
  );
}
```

---

## 11. Wall of Legends — `/adventure/wall-of-legends`

Per locked decision: sub-screen inside Adventure tab. Anonymised social proof.

### 11.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ Wall of Legends                     │
│ Proud moments at Diaries Club       │
├─────────────────────────────────────┤
│ TODAY                               │
│ ⭐ A.'s Rafi reached Champion       │
│    2 hours ago                      │
│                                     │
│ 🎂 R. celebrated their birthday    │
│    4 hours ago                      │
│                                     │
│ 🔥 K. hit a 7-week streak           │
│    Today                            │
├─────────────────────────────────────┤
│ THIS WEEK                           │
│ ...                                 │
├─────────────────────────────────────┤
│ HALL OF FAME                        │
│ [Top performer mini-tiles]          │
│                                     │
│ Most birthdays: 3 (Diaries Club)    │
│ Longest streak: 12 weeks            │
└─────────────────────────────────────┘
```

### 11.2 Data source

```dart
@riverpod
Stream<List<WallEntry>> wallOfLegendsFeed(WallOfLegendsFeedRef ref) async* {
  await for (final rows in Supabase.instance.client
      .from('wall_of_legends_daily')
      .stream(primaryKey: ['id'])
      .order('ist_date', ascending: false)
      .limit(7)) {
    final allHighlights = rows
      .expand((r) => (r['highlights'] as List).map((h) => WallEntry.fromJson({
        ...h, 'date': r['ist_date'],
      })))
      .toList();
    yield allHighlights;
  }
}
```

The `wall_of_legends_daily` table is populated by a daily cron (Session 13) that aggregates yesterday's notable events:
- Stage transitions
- Birthdays
- Streak milestones
- Rare card earnings
- Workshop completions

Each highlight is anonymised: first letter of child's name only ("A." instead of "Aarav"). Anonymisation is configurable per `venue_config.wall_of_legends_anonymise = true` (already in schema).

### 11.3 Hall of Fame

Computed nightly:
- "Most birthdays celebrated" = max birthday_reservations per family
- "Longest streak" = max streak_records.longest_streak_weeks across all children
- "Most cards collected" = max(count(*)) from hero_card_collection

These are anonymised in the same way — first letter only.

---

## 12. Files to Create

```
lib/
└── features/
    └── adventure/
        ├── adventure_screen.dart
        ├── child_adventure_dashboard.dart
        ├── hero_card_collection_screen.dart
        ├── card_detail_screen.dart
        ├── stats_screen.dart
        ├── wall_of_legends_screen.dart
        ├── widgets/
        │   ├── child_select_card.dart
        │   ├── cafe_only_empty_state.dart
        │   ├── diaries_world_map.dart
        │   ├── hero_on_map.dart
        │   ├── hero_detail_sheet.dart
        │   ├── trait_progress_strip.dart
        │   ├── compact_trait_progress.dart
        │   ├── streak_tracker_widget.dart
        │   ├── hero_card_collection_preview.dart
        │   ├── mini_card_thumbnail.dart
        │   ├── card_grid_item.dart
        │   ├── recent_achievements.dart
        │   ├── achievement_row.dart
        │   ├── stage_history_timeline.dart
        │   ├── timeline_entry.dart
        │   ├── collection_stats_banner.dart
        │   ├── wall_entry_row.dart
        │   └── hall_of_fame_tile.dart
        └── providers/
            ├── selected_adventure_child_id_provider.dart
            ├── child_streak_provider.dart
            ├── earned_cards_provider.dart
            ├── earned_card_ids_provider.dart
            ├── all_hero_card_definitions_provider.dart
            ├── total_card_count_provider.dart
            ├── achievement_feed_provider.dart
            ├── child_stage_history_provider.dart
            ├── child_stats_provider.dart
            └── wall_of_legends_feed_provider.dart
```

---

## 13. Acceptance Tests

```
TEST 1 — Cafe-only empty state
  1. Family with is_cafe_only = true, no children
  2. Tap Adventure tab
  3. Empty state shows with "Add a child" CTA
  4. Tap → /profile/add-child

TEST 2 — Single child auto-select
  1. Family with one child
  2. Tap Adventure tab
  3. Skips selector, lands directly on dashboard

TEST 3 — Multi-child selector
  1. Family with 2 children
  2. Tap Adventure tab
  3. Both children visible as cards
  4. Tap one → dashboard for that child
  5. Tap back → selector again
  6. Re-open Adventure tab → goes to last selected child

TEST 4 — World map
  1. On dashboard, see map with 4 hero positions
  2. Each hero shows correct stage (Seedling for new, etc.)
  3. Tap a hero → detail sheet shows progression
  4. Earn XP that triggers stage change → map updates within 5s (Realtime)

TEST 5 — Trait progress strip
  1. 4 mini progress bars, one per trait
  2. Each shows current XP and progress to next stage
  3. Top stage (Legend) shows full bar, no "to next"

TEST 6 — Hero card collection grid
  1. Open /adventure/cards
  2. All ~40 cards in grid
  3. Earned cards full color
  4. Unearned cards: dark silhouette + lock icon overlay
  5. Tap earned → detail screen
  6. Tap unearned → no action (or tooltip "Earn this by playing")

TEST 7 — Card detail + share
  1. Tap an earned card → full detail screen
  2. Image zoomable
  3. "Earned on" date correct
  4. "Share this card" → opens share sheet with composed image

TEST 8 — Streak widget
  1. Child with current_streak_weeks > 0
  2. Widget shows streak count + flame
  3. Best ever shown if > current
  4. Subtext changes based on day of week

TEST 9 — Recent achievements
  1. Pull union of XP events, card earnings, transitions, streak milestones
  2. 5 most recent shown
  3. Each row tappable (navigates to relevant detail)

TEST 10 — Stats screen
  1. Open /adventure/stats?childId=...
  2. All numbers correct vs DB
  3. Trait XP bars per trait
  4. Sessions count, total minutes, etc. accurate

TEST 11 — Wall of Legends
  1. Tap Wall of Legends from app bar action
  2. Sub-screen loads with TODAY / THIS WEEK groups
  3. Each highlight shows first-letter name only
  4. Hall of Fame tiles render

TEST 12 — Realtime updates
  1. Adventure tab open on Aarav
  2. In another device/dashboard, update children.xp_rafi
  3. Trait strip updates within 5s
  4. World map hero updates if stage changed
```

---

## 14. Open Items for Founder

- [ ] Approve Diaries World Map illustration (asset 2.3 from pre-launch)
- [ ] Confirm hero territory naming: Mountain/Meadow/Forest/Studio (or alternate)
- [ ] Approve hero illustrations across 5 stages × 4 heroes (asset 2.1)
- [ ] Approve hero card artwork (40 cards, asset 2.4)
- [ ] Decide if Wall of Legends should also include "milestones from other venues" once multi-venue (deferred)
- [ ] Confirm what to show for cards across multiple children — currently per-child collection (each child has independent set)
- [ ] Approve "first-letter-only" anonymisation for Wall of Legends (e.g., "A." for "Aarav")

---

## What's NOT in this session

- Birthday flow (Session 9)
- Staff app (Session 10)
- Admin web (Session 11)
- Edge Functions for hero recap image, card share image generation (Session 13)
- Daily Wall of Legends aggregation cron (Session 13)
