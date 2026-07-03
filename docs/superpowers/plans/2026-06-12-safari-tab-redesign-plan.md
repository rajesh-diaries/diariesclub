# Safari Club Tab Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the Safari tab into a story-first information + interest-capture page that explains The Safari Method and collects waitlist sign-ups.

**Architecture:** Reuse existing widgets where possible, update copy/layout inside them, and keep the existing `safari_waitlist` table. Add one new widget for the typical-morning timeline. Wire a scroll-to-form action from the hero CTA.

**Tech Stack:** Flutter, Riverpod, Phosphor icons, Supabase client.

---

## Files to touch

| File | Responsibility |
|------|----------------|
| `lib/features/safari/safari_screen.dart` | Page layout/order of sections; add scroll-to-form key |
| `lib/features/safari/widgets/safari_hero_banner.dart` | Hero copy, CTA button, scroll-to-form |
| `lib/features/safari/widgets/safari_announcement_card.dart` | Fallback banner copy |
| `lib/features/safari/widgets/safari_what_it_is.dart` | Rewrite to paragraph intro + Safari Method |
| `lib/features/safari/widgets/safari_philosophy_card.dart` | Replace content with 3 benefit cards |
| `lib/features/safari/widgets/safari_typical_morning.dart` | **New** timeline widget |
| `lib/features/safari/widgets/safari_trait_card.dart` | No change (reused) |
| `lib/features/safari/widgets/safari_faq_section.dart` | New FAQ copy |
| `lib/features/safari/widgets/safari_waitlist_form.dart` | Form title, button label, success copy |

---

## Task 1: Update announcement banner fallback copy

**Files:**
- Modify: `lib/features/safari/widgets/safari_announcement_card.dart`

- [ ] **Step 1: Locate the fallback/default banner text**

- [ ] **Step 2: Replace it with**

```dart
const Text('Safari Club — a morning club where little explorers build Brave, Curious, Kind & Creative traits through play. Coming soon.')
```

- [ ] **Step 3: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_announcement_card.dart`
Expected: no issues.

---

## Task 2: Update hero subtitle and add CTA

**Files:**
- Modify: `lib/features/safari/widgets/safari_hero_banner.dart`

- [ ] **Step 1: Change subtitle text**

Find:
```dart
Text(
  'A club for little explorers.',
  ...
)
```

Replace with:
```dart
Text(
  'A morning club',
  style: AppTextStyles.bodyLarge(
    context,
    color: Colors.white70,
  ),
)
```

- [ ] **Step 2: Add a CTA button that scrolls to the form**

Add a `VoidCallback? onInterested` parameter to `SafariHeroBanner`.

At the bottom of the hero `Column`, add:

```dart
const SizedBox(height: 24),
ElevatedButton.icon(
  onPressed: onInterested,
  icon: const Icon(PhosphorIconsRegular.rocketLaunch),
  label: const Text('I\'m interested'),
  style: ElevatedButton.styleFrom(
    foregroundColor: SafariColors.jungleGreen,
    backgroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    textStyle: AppTextStyles.bodyLarge(context).copyWith(
      fontWeight: FontWeight.w700,
    ),
  ),
)
```

- [ ] **Step 3: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_hero_banner.dart`
Expected: no issues.

---

## Task 3: Wire scroll-to-form in `SafariScreen`

**Files:**
- Modify: `lib/features/safari/safari_screen.dart`

- [ ] **Step 1: Add a GlobalKey for the form section**

```dart
class SafariScreen extends StatefulWidget {
  const SafariScreen({super.key});

  @override
  State<SafariScreen> createState() => _SafariScreenState();
}

class _SafariScreenState extends State<SafariScreen> {
  final _formKey = GlobalKey();

  void _scrollToForm() {
    final ctx = _formKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafariColors.softCream,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SafariAnnouncementCard(),
          SafariHeroBanner(onInterested: _scrollToForm),
          const SizedBox(height: 32),
          const SafariWhatItIs(),
          const SizedBox(height: 32),
          const SafariPhilosophyCard(),
          const SizedBox(height: 32),
          const SafariTypicalMorning(),
          const SizedBox(height: 32),
          const _FourTraitsSection(),
          const SizedBox(height: 32),
          const SafariFaqSection(),
          const SizedBox(height: 32),
          KeyedSubtree(
            key: _formKey,
            child: const SafariWaitlistForm(),
          ),
          const SizedBox(height: 32),
          const _Footer(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/safari_screen.dart`
Expected: no issues.

---

## Task 4: Rewrite "What is it?" paragraph

**Files:**
- Modify: `lib/features/safari/widgets/safari_what_it_is.dart`

- [ ] **Step 1: Replace the entire file body with a paragraph + optional mini-info row**

Keep the heading `"What is it?"`. Replace the 4 `_InfoCard`s with a paragraph block:

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'What is it?',
        style: AppTextStyles.h3(
          context,
          color: SafariColors.jungleGreen,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Safari Club is not a school, not a Montessori, and not an activity class.\n\n'
        'It is a trait-first play space for 2–5 year olds inside Play Diaries.\n\n'
        'It follows The Safari Method — a play-first approach where children grow the four life traits they need most: Brave, Curious, Kind, and Creative.\n\n'
        'In a world where knowledge is one click away, we believe children need relationships, confidence, and character far more than another worksheet.',
        style: AppTextStyles.body(
          context,
          color: SafariColors.slate,
        ),
      ),
    ],
  ),
)
```

- [ ] **Step 2: Remove unused `_InfoCard` class**

- [ ] **Step 3: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_what_it_is.dart`
Expected: no issues.

---

## Task 5: Replace philosophy card with "Why Safari Club?" benefit cards

**Files:**
- Modify: `lib/features/safari/widgets/safari_philosophy_card.dart`

- [ ] **Step 1: Change heading and items**

Heading: `"Why Safari Club?"`

Three `_PhilosophyItem`s with these icons/texts:

```dart
const _PhilosophyItem(
  icon: PhosphorIconsRegular.star,
  text:
      'Built around four life traits — Every session grows Brave, Curious, Kind, and Creative through guided play.',
),
const _PhilosophyItem(
  icon: PhosphorIconsRegular.users,
  text:
      'Real-world skills through play — Sharing, communication, routines, independence, and empathy learned naturally.',
),
const _PhilosophyItem(
  icon: PhosphorIconsRegular.heart,
  text:
      'Real skills for life — traits they keep forever — Growth and abilities that stay with children long after they leave the classroom.',
),
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_philosophy_card.dart`
Expected: no issues.

---

## Task 6: Create typical morning timeline widget

**Files:**
- Create: `lib/features/safari/widgets/safari_typical_morning.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import 'safari_colors.dart';

class SafariTypicalMorning extends StatelessWidget {
  const SafariTypicalMorning({super.key});

  final List<Map<String, String>> _slots = const [
    {'time': '9:30 AM', 'label': 'Arrival & free play'},
    {'time': '10:00 AM', 'label': 'Guided play activity (sensory, creative, or social)'},
    {'time': '11:00 AM', 'label': 'Snack & story circle'},
    {'time': '11:30 AM', 'label': 'Movement & character-trait games'},
    {'time': '12:15 PM', 'label': 'Wind-down'},
    {'time': '12:30 PM', 'label': 'Pickup'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A typical morning',
            style: AppTextStyles.h3(
              context,
              color: SafariColors.jungleGreen,
            ),
          ),
          const SizedBox(height: 20),
          ..._slots.map((slot) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIconsRegular.clock,
                      color: SafariColors.warmAmber,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      slot['time']!,
                      style: AppTextStyles.body(
                        context,
                        color: SafariColors.jungleGreen,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        slot['label']!,
                        style: AppTextStyles.body(
                          context,
                          color: SafariColors.slate,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_typical_morning.dart`
Expected: no issues.

---

## Task 7: Update four-trait descriptions

**Files:**
- Modify: `lib/features/safari/safari_screen.dart`

- [ ] **Step 1: Update `_FourTraitsSection` `_traits` list**

```dart
final List<Map<String, String>> _traits = const [
  {
    'image': 'assets/hero/rafi.png',
    'title': 'Brave like Rafi',
    'desc': 'Trying new things, speaking up, and bouncing back.',
  },
  {
    'image': 'assets/hero/gerry.png',
    'title': 'Curious like Gerry',
    'desc': 'Asking “why?”, exploring, and wondering.',
  },
  {
    'image': 'assets/hero/ellie.png',
    'title': 'Kind like Ellie',
    'desc': 'Sharing, including others, and caring.',
  },
  {
    'image': 'assets/hero/zena.png',
    'title': 'Creative like Zena',
    'desc': 'Imagining, building, and finding new ways.',
  },
];
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/safari_screen.dart`
Expected: no issues.

---

## Task 8: Update FAQ copy

**Files:**
- Modify: `lib/features/safari/widgets/safari_faq_section.dart`

- [ ] **Step 1: Replace `_faqs` list**

```dart
final List<Map<String, String>> _faqs = const [
  {
    'q': 'Is this a school or Montessori program?',
    'a': 'No. Safari Club is a play-based morning club using The Safari Method. We focus on character traits and life skills, not academics.',
  },
  {
    'q': 'How is this different from activity classes?',
    'a': 'Most activity classes teach one skill. Safari Club uses play to build the four traits that help in every part of life.',
  },
  {
    'q': 'What should my child bring?',
    'a': 'Just a water bottle and a small snack if needed. We handle the activities.',
  },
  {
    'q': 'Can we visit before enrolling?',
    'a': 'Yes. We’ll invite interested families for a visit once enrollment opens.',
  },
  {
    'q': 'When does Safari Club start?',
    'a': 'We’re preparing to launch soon. Tap “I’m interested” to be the first to know.',
  },
];
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_faq_section.dart`
Expected: no issues.

---

## Task 9: Update waitlist form labels and success copy

**Files:**
- Modify: `lib/features/safari/widgets/safari_waitlist_form.dart`

- [ ] **Step 1: Update form heading, subheading, button, and success text**

Heading:
```dart
Text(
  'Interested?',
  ...
)
```

Subheading:
```dart
Text(
  'Let us know and we’ll reach out when enrollment opens. No commitment required.',
  ...
)
```

Button label:
```dart
PrimaryButton(
  label: 'I\'m interested',
  ...
)
```

Success heading:
```dart
Text(
  'Thanks for your interest!',
  ...
)
```

Success body:
```dart
Text(
  'We’ll reach out when enrollment opens.',
  ...
)
```

- [ ] **Step 2: Build**

Run: `flutter analyze lib/features/safari/widgets/safari_waitlist_form.dart`
Expected: no issues.

---

## Task 10: Full-page build and visual check

**Files:**
- Modify: `lib/features/safari/safari_screen.dart` (final order check)

- [ ] **Step 1: Ensure section order is**

1. SafariAnnouncementCard
2. SafariHeroBanner
3. SafariWhatItIs
4. SafariPhilosophyCard
5. SafariTypicalMorning
6. _FourTraitsSection
7. SafariFaqSection
8. SafariWaitlistForm
9. _Footer

- [ ] **Step 2: Run full build**

Run: `flutter build ios --target lib/main_dev.dart --no-codesign --debug` (or `flutter build apk`)
Expected: build succeeds.

- [ ] **Step 3: Install and verify on device**

Run: `./scripts/run_ios_dev.sh <device-id>`
Expected: app launches; Safari tab shows new content, CTA scrolls to form, form submits successfully.

---

## Spec coverage check

| Spec section | Plan task |
|--------------|-----------|
| Admin banner | Task 1 |
| Hero subtitle + CTA | Task 2 + 3 |
| What is it? paragraph | Task 4 |
| Why Safari Club? 3 cards | Task 5 |
| A typical morning | Task 6 |
| Four Traits | Task 7 |
| FAQ | Task 8 |
| Interest form | Task 9 |
| Footer | unchanged |

No placeholders. No backend changes.
