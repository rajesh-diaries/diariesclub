# Safari Club Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Safari Club" bottom tab to the Play Diaries app with a coming-soon explainer screen, waitlist form, and admin panel view.

**Architecture:** Single scrollable screen with 8 sections. Reuses existing hero assets and announcements system. One new Supabase table for waitlist entries. Admin waitlist screen in existing web admin panel.

**Tech Stack:** Flutter, Riverpod, GoRouter, Supabase, Phosphor Icons

---

## File Structure

### New Files
- `lib/features/safari/safari_screen.dart` — Main scrollable screen
- `lib/features/safari/widgets/safari_hero_banner.dart` — Jungle gradient hero
- `lib/features/safari/widgets/safari_announcement_card.dart` — Dynamic announcement
- `lib/features/safari/widgets/safari_philosophy_card.dart` — Program description
- `lib/features/safari/widgets/safari_trait_card.dart` — Individual trait card
- `lib/features/safari/widgets/safari_what_it_is.dart` — Checklist section
- `lib/features/safari/widgets/safari_faq_section.dart` — FAQ accordion
- `lib/features/safari/widgets/safari_waitlist_form.dart` — Express Interest form
- `lib/features/safari/widgets/safari_colors.dart` — Color constants
- `lib/admin/safari_waitlist/safari_waitlist_screen.dart` — Admin waitlist view
- `supabase/migrations/0175_safari_waitlist.sql` — Database schema

### Modified Files
- `lib/core/router/app_router.dart` — Add `/safari` route branch
- `lib/core/router/app_shell.dart` — Add 5th BottomNavigationBarItem
- `lib/admin/admin_router.dart` — Add `/admin/safari-waitlist` route
- `lib/admin/widgets/admin_sidebar.dart` — Add nav item

---

### Task 1: Database Migration

**Files:**
- Create: `supabase/migrations/0175_safari_waitlist.sql`

- [ ] **Step 1: Write migration**

```sql
-- Safari Club waitlist table
CREATE TABLE public.safari_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid REFERENCES public.families(id) ON DELETE SET NULL,
  parent_name text NOT NULL,
  phone text NOT NULL,
  child_name text NOT NULL,
  child_age int NOT NULL CHECK (child_age IN (2, 3, 4)),
  source text DEFAULT 'app' CHECK (source IN ('app', 'walkin', 'whatsapp')),
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'contacted', 'enrolled', 'declined')),
  admin_notes text,
  created_at timestamptz DEFAULT now(),
  contacted_at timestamptz
);

CREATE INDEX idx_safari_waitlist_phone ON public.safari_waitlist(phone);
CREATE INDEX idx_safari_waitlist_status ON public.safari_waitlist(status);
CREATE INDEX idx_safari_waitlist_created ON public.safari_waitlist(created_at DESC);

-- RLS
ALTER TABLE public.safari_waitlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can join waitlist"
  ON public.safari_waitlist FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Admins can view waitlist"
  ON public.safari_waitlist FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = auth.uid() AND is_active = true
  ));

CREATE POLICY "Admins can update waitlist"
  ON public.safari_waitlist FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = auth.uid() AND is_active = true
  ));
```

- [ ] **Step 2: Apply migration locally**

```bash
supabase migration up
```

Expected: Migration applies successfully.

- [ ] **Step 3: Verify table exists**

```bash
supabase db dump --data-only --table safari_waitlist
```

Expected: Empty table structure shown.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0175_safari_waitlist.sql
git commit -m "feat(safari): add safari_waitlist table with RLS"
```

---

### Task 2: Safari Color Constants

**Files:**
- Create: `lib/features/safari/widgets/safari_colors.dart`

- [ ] **Step 1: Create color constants file**

```dart
import 'package:flutter/material.dart';

/// Safari Club color palette.
/// These are purpose-specific aliases — the underlying values
/// match the design tokens but are scoped here for clarity.
abstract class SafariColors {
  static const Color jungleGreen = Color(0xFF2D5016);
  static const Color jungleDark = Color(0xFF1A3009);
  static const Color safariGold = Color(0xFFF4A261);
  static const Color softCream = Color(0xFFFFF8E7);
  static const Color traitCreative = Color(0xFF6B8E23);
  static const Color traitKind = Color(0xFF8B7355);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_colors.dart
git commit -m "feat(safari): add safari color constants"
```

---

### Task 3: Safari Hero Banner Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_hero_banner.dart`

- [ ] **Step 1: Create hero banner widget**

```dart
import 'package:flutter/material.dart';
import 'safari_colors.dart';

class SafariHeroBanner extends StatelessWidget {
  const SafariHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SafariColors.jungleGreen, SafariColors.jungleDark],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 36),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative orbs
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: SafariColors.safariGold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: SafariColors.safariGold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Content
          Column(
            children: [
              // Character images
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _charImage('assets/hero/rafi.png', 0),
                  _charImage('assets/hero/gerry.png', -12),
                  _charImage('assets/hero/ellie.png', 0),
                  _charImage('assets/hero/zena.png', -12),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Safari Club',
                style: TextStyle(
                  color: SafariColors.softCream,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A club for little explorers.',
                style: TextStyle(
                  color: SafariColors.safariGold,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ages 2–4 · Mon–Fri · 9:30 AM – 12:30 PM',
                style: TextStyle(
                  color: SafariColors.softCream.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _charImage(String path, double offsetY) {
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Container(
        width: 72,
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: SafariColors.softCream,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.image_not_supported, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_hero_banner.dart
git commit -m "feat(safari): add hero banner widget"
```

---

### Task 4: Safari Announcement Card Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_announcement_card.dart`

- [ ] **Step 1: Create announcement card widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'safari_colors.dart';

final safariAnnouncementProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final rows = await Supabase.instance.client
      .from('announcements')
      .select('title, body, created_at')
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(1);
  
  if (rows.isEmpty) return null;
  return rows.first as Map<String, dynamic>;
});

class SafariAnnouncementCard extends ConsumerWidget {
  const SafariAnnouncementCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(safariAnnouncementProvider);

    return async.when(
      data: (announcement) {
        if (announcement == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SafariColors.jungleGreen, Color(0xFF3A6B1E)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: SafariColors.safariGold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'LATEST UPDATE',
                  style: TextStyle(
                    color: SafariColors.jungleGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                announcement['body'] as String? ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.5,
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
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_announcement_card.dart
git commit -m "feat(safari): add announcement card widget"
```

---

### Task 5: Safari Philosophy Card Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_philosophy_card.dart`

- [ ] **Step 1: Create philosophy card widget**

```dart
import 'package:flutter/material.dart';

class SafariPhilosophyCard extends StatelessWidget {
  const SafariPhilosophyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D5016).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'Safari Club is a toddler activity program that goes beyond preschool and daycare. We believe in building character — through play, story, and hands-on discovery.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF4A4A4A),
          fontSize: 15,
          height: 1.7,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_philosophy_card.dart
git commit -m "feat(safari): add philosophy card widget"
```

---

### Task 6: Safari Trait Card Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_trait_card.dart`

- [ ] **Step 1: Create trait card widget**

```dart
import 'package:flutter/material.dart';
import 'safari_colors.dart';

class SafariTraitCard extends StatelessWidget {
  final String imagePath;
  final String title;
  final String description;

  const SafariTraitCard({
    super.key,
    required this.imagePath,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D5016).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.image_not_supported, size: 24, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: SafariColors.jungleGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 14,
                    height: 1.6,
                  ),
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

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_trait_card.dart
git commit -m "feat(safari): add trait card widget"
```

---

### Task 7: Safari "What It Is" Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_what_it_is.dart`

- [ ] **Step 1: Create checklist widget**

```dart
import 'package:flutter/material.dart';
import 'safari_colors.dart';

class SafariWhatItIs extends StatelessWidget {
  const SafariWhatItIs({super.key});

  final List<String> _items = const [
    'Character building through play & activities',
    'Small groups with dedicated guides',
    'Screen-free mornings of real play',
    'A calm, intentional morning routine',
    'A toddler activity program beyond preschool & daycare',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D5016).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'What Safari Club Is',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          ..._items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✓', style: TextStyle(color: Color(0xFF5BAD4E), fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Color(0xFF4A4A4A),
                      fontSize: 15,
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

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_what_it_is.dart
git commit -m "feat(safari): add what-it-is checklist widget"
```

---

### Task 8: Safari FAQ Section Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_faq_section.dart`

- [ ] **Step 1: Create FAQ widget**

```dart
import 'package:flutter/material.dart';
import 'safari_colors.dart';

class SafariFaqSection extends StatelessWidget {
  const SafariFaqSection({super.key});

  final List<Map<String, String>> _faqs = const [
    {
      'q': 'What will my child do each morning?',
      'a': 'Activities are designed around the four traits — creative exploration, collaborative play, sensory discovery, and confidence-building. The specific activities evolve as we learn what engages our little explorers best. No screens, ever.',
    },
    {
      'q': 'Can I stay during the session?',
      'a': 'We have a dedicated parent viewing area. You\'re also welcome to relax at our cafe with complimentary coffee while your explorer adventures.',
    },
    {
      'q': 'Is this a preschool?',
      'a': 'Safari Club is a toddler activity program that goes beyond preschool and daycare. We focus on character development through play — not academics, worksheets, or rankings.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Text(
            'Questions Parents Ask',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          ..._faqs.map((faq) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D5016).withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faq['q']!,
                  style: const TextStyle(
                    color: SafariColors.jungleGreen,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  faq['a']!,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 14,
                    height: 1.6,
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

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_faq_section.dart
git commit -m "feat(safari): add FAQ section widget"
```

---

### Task 9: Safari Waitlist Form Widget

**Files:**
- Create: `lib/features/safari/widgets/safari_waitlist_form.dart`

- [ ] **Step 1: Create form widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/current_family_provider.dart';
import '../../../core/providers/family_children_provider.dart';
import 'safari_colors.dart';

class SafariWaitlistForm extends ConsumerStatefulWidget {
  const SafariWaitlistForm({super.key});

  @override
  ConsumerState<SafariWaitlistForm> createState() => _SafariWaitlistFormState();
}

class _SafariWaitlistFormState extends ConsumerState<SafariWaitlistForm> {
  final _parentNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _childNameController = TextEditingController();
  int? _selectedAge;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from family data if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final family = ref.read(currentFamilyProvider).valueOrNull;
      final children = ref.read(familyChildrenProvider).valueOrNull;
      if (family != null) {
        _phoneController.text = (family['phone'] as String?) ?? '';
      }
      if (children != null && children.isNotEmpty) {
        _childNameController.text = (children.first['name'] as String?) ?? '';
      }
    });
  }

  @override
  void dispose() {
    _parentNameController.dispose();
    _phoneController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  bool get _isValid {
    return _parentNameController.text.trim().length >= 2 &&
        _phoneController.text.trim().length >= 10 &&
        _childNameController.text.trim().length >= 2 &&
        _selectedAge != null;
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() => _submitting = true);

    try {
      final family = ref.read(currentFamilyProvider).valueOrNull;
      await Supabase.instance.client.from('safari_waitlist').insert({
        'family_id': family?['id'],
        'parent_name': _parentNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'child_name': _childNameController.text.trim(),
        'child_age': _selectedAge,
        'source': 'app',
      });

      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong. Please try again. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D5016).withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF5BAD4E), size: 48),
            const SizedBox(height: 16),
            const Text(
              'Thank you!',
              style: TextStyle(
                color: SafariColors.jungleGreen,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "We'll reach out when Safari Club opens.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF666666), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Text(
            'Express Interest',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Be the first to know when Safari Club opens.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF666666), fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D5016).withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildTextField('Your Name', _parentNameController),
                const SizedBox(height: 16),
                _buildTextField('Phone Number', _phoneController, keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                _buildTextField("Child's Name", _childNameController),
                const SizedBox(height: 16),
                _buildAgeSelector(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting || !_isValid ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SafariColors.jungleGreen,
                      foregroundColor: SafariColors.softCream,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Express Interest',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  "We'll reach out when enrollment opens.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SafariColors.jungleGreen,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Child's Age",
          style: TextStyle(
            color: SafariColors.jungleGreen,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [2, 3, 4].map((age) {
            final selected = _selectedAge == age;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: age < 4 ? 12 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedAge = age),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? SafariColors.jungleGreen : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$age years',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? SafariColors.softCream : const Color(0xFF999999),
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/widgets/safari_waitlist_form.dart
git commit -m "feat(safari): add waitlist form widget"
```

---

### Task 10: Main Safari Screen

**Files:**
- Create: `lib/features/safari/safari_screen.dart`

- [ ] **Step 1: Create main screen**

```dart
import 'package:flutter/material.dart';
import 'widgets/safari_announcement_card.dart';
import 'widgets/safari_colors.dart';
import 'widgets/safari_faq_section.dart';
import 'widgets/safari_hero_banner.dart';
import 'widgets/safari_philosophy_card.dart';
import 'widgets/safari_trait_card.dart';
import 'widgets/safari_waitlist_form.dart';
import 'widgets/safari_what_it_is.dart';

class SafariScreen extends StatelessWidget {
  const SafariScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafariColors.softCream,
      body: ListView(
        padding: EdgeInsets.zero,
        children: const [
          SafariAnnouncementCard(),
          SafariHeroBanner(),
          SizedBox(height: 32),
          SafariPhilosophyCard(),
          SizedBox(height: 32),
          _FourTraitsSection(),
          SizedBox(height: 32),
          SafariWhatItIs(),
          SizedBox(height: 32),
          SafariFaqSection(),
          SizedBox(height: 32),
          SafariWaitlistForm(),
          SizedBox(height: 32),
          _Footer(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FourTraitsSection extends StatelessWidget {
  const _FourTraitsSection();

  final List<Map<String, String>> _traits = const [
    {
      'image': 'assets/hero/rafi.png',
      'title': 'Brave like Rafi',
      'desc': 'The courage to try, fail, and try again. To speak up, stand tall, and explore the unknown without fear.',
    },
    {
      'image': 'assets/hero/gerry.png',
      'title': 'Curious like Gerry',
      'desc': 'The hunger to ask "why?" and "what if?" To look closer, reach higher, and never stop wondering about the world.',
    },
    {
      'image': 'assets/hero/ellie.png',
      'title': 'Kind like Ellie',
      'desc': 'The strength to care, share, and include others. True confidence comes from lifting people up, not putting them down.',
    },
    {
      'image': 'assets/hero/zena.png',
      'title': 'Creative like Zena',
      'desc': 'The ability to see what isn\'t there yet. To adapt, imagine, and build something new from the pieces around you.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Text(
            'The Four Traits',
            style: TextStyle(
              color: SafariColors.jungleGreen,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          ..._traits.map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SafariTraitCard(
              imagePath: t['image']!,
              title: t['title']!,
              description: t['desc']!,
            ),
          )),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Safari Club · Play Diaries',
        style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/safari/safari_screen.dart
git commit -m "feat(safari): add main safari screen"
```

---

### Task 11: Add Safari Route to App Router

**Files:**
- Modify: `lib/core/router/app_router.dart`

- [ ] **Step 1: Add import and route**

Add import at the top:
```dart
import '../../features/safari/safari_screen.dart';
```

Add new branch inside `StatefulShellRoute.indexedStack` branches list (after Adventure, before Profile):

```dart
StatefulShellBranch(
  routes: [
    GoRoute(
      path: '/safari',
      name: 'safari',
      builder: (context, state) => const SafariScreen(),
    ),
  ],
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(safari): add /safari route to app router"
```

---

### Task 12: Add Safari Tab to Bottom Navigation

**Files:**
- Modify: `lib/core/router/app_shell.dart`

- [ ] **Step 1: Add 5th navigation item**

Add inside `BottomNavigationBar` items list (after Adventure, before Profile):

```dart
BottomNavigationBarItem(
  icon: Icon(i == 3 ? PhosphorIconsFill.globeHemisphereWest : PhosphorIconsRegular.globeHemisphereWest),
  label: 'Safari',
),
```

Update the existing Profile item index from 3 to 4:
```dart
BottomNavigationBarItem(
  icon: Icon(i == 4 ? PhosphorIconsFill.user : PhosphorIconsRegular.user),
  label: 'Profile',
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/router/app_shell.dart
git commit -m "feat(safari): add safari tab to bottom navigation"
```

---

### Task 13: Admin Waitlist Screen

**Files:**
- Create: `lib/admin/safari_waitlist/safari_waitlist_screen.dart`

- [ ] **Step 1: Create admin waitlist screen**

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SafariWaitlistScreen extends StatefulWidget {
  const SafariWaitlistScreen({super.key});

  @override
  State<SafariWaitlistScreen> createState() => _SafariWaitlistScreenState();
}

class _SafariWaitlistScreenState extends State<SafariWaitlistScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final rows = await Supabase.instance.client
        .from('safari_waitlist')
        .select()
        .order('created_at', ascending: false);
    setState(() {
      _entries = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  Future<void> _updateStatus(String id, String status) async {
    await Supabase.instance.client
        .from('safari_waitlist')
        .update({'status': status, 'contacted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safari Waitlist')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No entries yet.'))
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text('${e['parent_name']} — ${e['child_name']} (${e['child_age']})'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phone: ${e['phone']}'),
                            Text('Status: ${e['status']}'),
                            Text('Date: ${e['created_at']}'),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (status) => _updateStatus(e['id'], status),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'pending', child: Text('Pending')),
                            const PopupMenuItem(value: 'contacted', child: Text('Contacted')),
                            const PopupMenuItem(value: 'enrolled', child: Text('Enrolled')),
                            const PopupMenuItem(value: 'declined', child: Text('Declined')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/admin/safari_waitlist/safari_waitlist_screen.dart
git commit -m "feat(admin): add safari waitlist admin screen"
```

---

### Task 14: Admin Router + Sidebar Updates

**Files:**
- Modify: `lib/admin/admin_router.dart`
- Modify: `lib/admin/widgets/admin_sidebar.dart`

- [ ] **Step 1: Add route to admin router**

Add import:
```dart
import '../safari_waitlist/safari_waitlist_screen.dart';
```

Add route inside ShellRoute:
```dart
GoRoute(
  path: '/admin/safari-waitlist',
  builder: (_, __) => const SafariWaitlistScreen(),
),
```

- [ ] **Step 2: Add nav item to admin sidebar**

Add to sidebar items list:
```dart
AdminNavItem(
  icon: PhosphorIconsRegular.treePalm,
  label: 'Safari Waitlist',
  route: '/admin/safari-waitlist',
),
```

- [ ] **Step 3: Commit**

```bash
git add lib/admin/admin_router.dart lib/admin/widgets/admin_sidebar.dart
git commit -m "feat(admin): wire up safari waitlist route and sidebar nav"
```

---

## Self-Review

**Spec coverage:**
- ✅ 8 UI sections — all implemented across Tasks 3-10
- ✅ Database schema — Task 1
- ✅ RLS policies — Task 1
- ✅ Form validation + pre-fill — Task 9
- ✅ Admin waitlist screen — Tasks 13-14
- ✅ Announcement integration — Task 4
- ✅ Bottom nav (5th tab) — Tasks 11-12
- ✅ Hero images from assets/hero/ — Task 3
- ✅ Error handling — Task 9 (try/catch + SnackBar)

**Placeholder scan:**
- ✅ No TBD/TODO/placeholders
- ✅ All code blocks contain complete implementations
- ✅ No "implement later" or "add validation" vagueness

**Type consistency:**
- ✅ `safari_waitlist` column names match between schema (Task 1) and insert (Task 9)
- ✅ `child_age` is `int` with CHECK (2,3,4) in schema and `_selectedAge` is `int?` in form
- ✅ Route paths consistent: `/safari` in router, `/admin/safari-waitlist` in admin router
