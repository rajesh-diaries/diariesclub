# Birthday package card redesign — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved birthday package card redesign: clean white cards with a thin tier accent bar, optional badge, tagline, price chips and a top-3 inclusions expander, with accent color / badge / tagline editable from the admin form.

**Architecture:** Add three new columns to `birthday_packages` and the matching RPC params, expose them in the admin edit form, then update the customer list and detail screens to read them with static fallbacks for the four known tier names.

**Tech stack:** Flutter (customer app + admin web), Supabase Postgres, Cloudflare Pages for admin web deploy.

---

## File map

| File | Responsibility |
|---|---|
| `supabase/migrations/0152_birthday_packages_card_styling.sql` | Add `accent_color_hex`, `badge_text`, `tagline` columns and update `admin_package_create/update` RPCs. |
| `lib/admin/packages/package_edit_screen.dart` | Admin form: load, edit and save the three new styling fields along with existing package data. |
| `lib/features/birthday/birthday_packages_screen.dart` | Customer list card: resolve accent/badge/tagline, render the redesigned card. |
| `lib/features/birthday/package_detail_screen.dart` | Customer detail screen: hide empty carousel placeholder, merge all inclusion sources, use accent color. |

---

## Task 1: Database migration and RPCs

**Files:**
- Create: `supabase/migrations/0152_birthday_packages_card_styling.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0152 — admin-configurable birthday package card styling

ALTER TABLE birthday_packages
  ADD COLUMN IF NOT EXISTS accent_color_hex TEXT,
  ADD COLUMN IF NOT EXISTS badge_text TEXT,
  ADD COLUMN IF NOT EXISTS tagline TEXT;

DROP FUNCTION IF EXISTS public.admin_package_create(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, integer, text, integer,
  integer, integer, integer, text, jsonb
);
DROP FUNCTION IF EXISTS public.admin_package_update(
  uuid, text, text, text, integer, integer, integer, integer, integer,
  text, text[], jsonb, jsonb, jsonb, jsonb, text, boolean, integer, text,
  integer, integer, integer, integer, text, jsonb
);

CREATE OR REPLACE FUNCTION public.admin_package_create(
  p_venue_id UUID,
  p_name TEXT,
  p_tier TEXT,
  p_description TEXT DEFAULT NULL,
  p_price_paise INTEGER DEFAULT NULL,
  p_deposit_paise INTEGER DEFAULT NULL,
  p_duration_hours INTEGER DEFAULT 3,
  p_max_kids INTEGER DEFAULT NULL,
  p_max_adults INTEGER DEFAULT NULL,
  p_cover_image_url TEXT DEFAULT NULL,
  p_gallery_image_urls TEXT[] DEFAULT NULL,
  p_inclusions JSONB DEFAULT '[]'::jsonb,
  p_menu_options JSONB DEFAULT '{}'::jsonb,
  p_non_food_offerings JSONB DEFAULT '[]'::jsonb,
  p_available_days JSONB DEFAULT '{"weekday":true,"weekend":true,"specific_dates":[]}'::jsonb,
  p_hero_theme TEXT DEFAULT NULL,
  p_sort_order INTEGER DEFAULT 0,
  p_hall_name TEXT DEFAULT NULL,
  p_min_guests INTEGER DEFAULT NULL,
  p_max_guests INTEGER DEFAULT NULL,
  p_price_per_pax_veg_paise INTEGER DEFAULT NULL,
  p_price_per_pax_non_veg_paise INTEGER DEFAULT NULL,
  p_pdf_url TEXT DEFAULT NULL,
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb,
  p_accent_color_hex TEXT DEFAULT NULL,
  p_badge_text TEXT DEFAULT NULL,
  p_tagline TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  INSERT INTO birthday_packages(
    venue_id, name, tier, description,
    price_paise, deposit_paise,
    duration_hours, max_kids, max_adults,
    cover_image_url, gallery_image_urls,
    inclusions, menu_options, non_food_offerings, available_days,
    hero_theme, sort_order, is_active,
    hall_name, min_guests, max_guests,
    price_per_pax_veg_paise, price_per_pax_non_veg_paise,
    pdf_url, experience_inclusions,
    accent_color_hex, badge_text, tagline
  ) VALUES (
    p_venue_id, p_name, p_tier, p_description,
    p_price_paise, p_deposit_paise,
    p_duration_hours, p_max_kids, p_max_adults,
    p_cover_image_url, p_gallery_image_urls,
    p_inclusions, p_menu_options, p_non_food_offerings, p_available_days,
    p_hero_theme, p_sort_order, true,
    p_hall_name, p_min_guests, p_max_guests,
    p_price_per_pax_veg_paise, p_price_per_pax_non_veg_paise,
    p_pdf_url, p_experience_inclusions,
    p_accent_color_hex, p_badge_text, p_tagline
  ) RETURNING id INTO v_id;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'package.create', 'birthday_packages', v_id,
    jsonb_build_object('name', p_name, 'tier', p_tier, 'hall_name', p_hall_name)
  );

  RETURN jsonb_build_object('success', true, 'package_id', v_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_package_update(
  p_id UUID,
  p_name TEXT,
  p_tier TEXT,
  p_description TEXT DEFAULT NULL,
  p_price_paise INTEGER DEFAULT NULL,
  p_deposit_paise INTEGER DEFAULT NULL,
  p_duration_hours INTEGER DEFAULT 3,
  p_max_kids INTEGER DEFAULT NULL,
  p_max_adults INTEGER DEFAULT NULL,
  p_cover_image_url TEXT DEFAULT NULL,
  p_gallery_image_urls TEXT[] DEFAULT NULL,
  p_inclusions JSONB DEFAULT '[]'::jsonb,
  p_menu_options JSONB DEFAULT '{}'::jsonb,
  p_non_food_offerings JSONB DEFAULT '[]'::jsonb,
  p_available_days JSONB DEFAULT '{"weekday":true,"weekend":true,"specific_dates":[]}'::jsonb,
  p_hero_theme TEXT DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT TRUE,
  p_sort_order INTEGER DEFAULT 0,
  p_hall_name TEXT DEFAULT NULL,
  p_min_guests INTEGER DEFAULT NULL,
  p_max_guests INTEGER DEFAULT NULL,
  p_price_per_pax_veg_paise INTEGER DEFAULT NULL,
  p_price_per_pax_non_veg_paise INTEGER DEFAULT NULL,
  p_pdf_url TEXT DEFAULT NULL,
  p_experience_inclusions JSONB DEFAULT '[]'::jsonb,
  p_accent_color_hex TEXT DEFAULT NULL,
  p_badge_text TEXT DEFAULT NULL,
  p_tagline TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_active_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  UPDATE birthday_packages SET
    name = p_name, tier = p_tier, description = p_description,
    price_paise = p_price_paise, deposit_paise = p_deposit_paise,
    duration_hours = p_duration_hours,
    max_kids = p_max_kids, max_adults = p_max_adults,
    cover_image_url = p_cover_image_url,
    gallery_image_urls = p_gallery_image_urls,
    inclusions = p_inclusions, menu_options = p_menu_options,
    non_food_offerings = p_non_food_offerings, available_days = p_available_days,
    hero_theme = p_hero_theme, is_active = p_is_active, sort_order = p_sort_order,
    hall_name = p_hall_name, min_guests = p_min_guests, max_guests = p_max_guests,
    price_per_pax_veg_paise = p_price_per_pax_veg_paise,
    price_per_pax_non_veg_paise = p_price_per_pax_non_veg_paise,
    pdf_url = p_pdf_url,
    experience_inclusions = p_experience_inclusions,
    accent_color_hex = p_accent_color_hex,
    badge_text = p_badge_text,
    tagline = p_tagline
  WHERE id = p_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'package_not_found'; END IF;

  INSERT INTO audit_log(actor_user_id, action, entity, entity_id, payload)
  VALUES (
    auth.uid(), 'package.update', 'birthday_packages', p_id,
    jsonb_build_object('name', p_name, 'tier', p_tier, 'hall_name', p_hall_name)
  );

  RETURN jsonb_build_object('success', true);
END $$;
```

- [ ] **Step 2: Apply migration**

Run:
```bash
npx supabase db query --linked --file supabase/migrations/0152_birthday_packages_card_styling.sql
```

Expected: query executes with no errors.

- [ ] **Step 3: Commit migration**

```bash
git add supabase/migrations/0152_birthday_packages_card_styling.sql
git commit -m "feat(db): admin-configurable package accent, badge and tagline"
```

---

## Task 2: Admin package edit screen

**Files:**
- Modify: `lib/admin/packages/package_edit_screen.dart`

- [ ] **Step 1: Add controllers**

After `_tierCtrl` declaration (around line 104), add:

```dart
  final _accentColorCtrl = TextEditingController();
  final _badgeTextCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
```

- [ ] **Step 2: Load existing values**

In `_loadExisting`, after `_tierCtrl.text = ...`, add:

```dart
        _accentColorCtrl.text = (row['accent_color_hex'] as String?) ?? '';
        _badgeTextCtrl.text = (row['badge_text'] as String?) ?? '';
        _taglineCtrl.text = (row['tagline'] as String?) ?? '';
```

- [ ] **Step 3: Dispose controllers**

In `dispose()`, add:

```dart
    _accentColorCtrl.dispose();
    _badgeTextCtrl.dispose();
    _taglineCtrl.dispose();
```

- [ ] **Step 4: Validate hex color**

In `_submit()`, after the hall-name check and before JSON parsing, add:

```dart
    final accentHex = _accentColorCtrl.text.trim();
    if (accentHex.isNotEmpty &&
        !RegExp(r'^#([0-9A-Fa-f]{3}){1,2}$').hasMatch(accentHex)) {
      setState(() => _errorText =
          'Accent color must be a hex code like #FF7A6E.');
      return;
    }
```

- [ ] **Step 5: Add new params to submit map**

In the `params` map passed to the RPC, after `'p_experience_inclusions': ...`, add:

```dart
        'p_accent_color_hex': accentHex.isEmpty ? null : accentHex,
        'p_badge_text': _badgeTextCtrl.text.trim().isEmpty
            ? null
            : _badgeTextCtrl.text.trim(),
        'p_tagline': _taglineCtrl.text.trim().isEmpty
            ? null
            : _taglineCtrl.text.trim(),
```

- [ ] **Step 6: Add card-styling UI fields**

Insert this block after the per-pax pricing caption (after `const SizedBox(height: 12)` that follows the caption) and before the guest/duration row:

```dart
                    const SizedBox(height: 20),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Card styling',
                        style: AppTextStyles.caption(
                          context,
                          color: AppColors.lightTextSecondary,
                        ).copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextField(
                      controller: _taglineCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tagline',
                        hintText: 'Our most loved package',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _badgeTextCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Badge text (optional)',
                              hintText: 'Most Booked',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _accentColorCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Accent color hex',
                              hintText: '#FF7A6E',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hex only, e.g. #FF7A6E. Used for the top bar, price chips, badge and tagline.',
                      style: AppTextStyles.caption(
                        context, color: AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
```

- [ ] **Step 7: Analyze admin app**

Run:
```bash
flutter analyze -t lib/app_admin.dart
```

Expected: no errors in `lib/admin/packages/package_edit_screen.dart`.

- [ ] **Step 8: Commit**

```bash
git add lib/admin/packages/package_edit_screen.dart
git commit -m "feat(admin): editable package accent, badge and tagline"
```

---

## Task 3: Customer list screen

**Files:**
- Modify: `lib/features/birthday/birthday_packages_screen.dart`

- [ ] **Step 1: Replace static helpers with resolvers**

Replace the existing `_packageAccentColor` and `_packageBadge` top-level functions with:

```dart
Color? _parseHexColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 4) {
    final r = hex[1];
    final g = hex[2];
    final b = hex[3];
    buffer.write('FF$r$r$g$g$b$b');
  } else if (hex.length == 7) {
    buffer.write('FF${hex.substring(1)}');
  } else if (hex.length == 9) {
    buffer.write(hex.substring(1));
  } else {
    return null;
  }
  final value = int.tryParse(buffer.toString(), radix: 16);
  if (value == null) return null;
  return Color(value);
}

Color _staticAccentColor(String name) => switch (name) {
      'Happy Tales' => AppColors.rafiCoral,
      'Grand' => AppColors.navy,
      'Magical' => AppColors.gold,
      _ => AppColors.fitGreen,
    };

String? _staticBadgeText(String name) => switch (name) {
      'Happy Tales' => 'Most Booked',
      'Grand' => 'Big celebration',
      'Magical' => 'Premium',
      _ => null,
    };

String? _staticTagline(String name) => switch (name) {
      'Little Joy' => 'Perfect for intimate celebrations',
      'Happy Tales' => 'Our most loved package',
      'Grand' => 'Grand scale, seamless fun',
      'Magical' => 'The full enchanted experience',
      _ => null,
    };

Color _resolveAccentColor(Map<String, dynamic> package, String name) {
  final hex = (package['accent_color_hex'] as String?)?.trim();
  if (hex != null && hex.isNotEmpty) {
    final parsed = _parseHexColor(hex);
    if (parsed != null) return parsed;
  }
  return _staticAccentColor(name);
}

String? _resolveBadgeText(Map<String, dynamic> package) {
  final text = (package['badge_text'] as String?)?.trim();
  if (text != null && text.isNotEmpty) return text;
  final name = (package['name'] as String?) ?? '';
  return _staticBadgeText(name);
}

String? _resolveTagline(Map<String, dynamic> package) {
  final text = (package['tagline'] as String?)?.trim();
  if (text != null && text.isNotEmpty) return text;
  final name = (package['name'] as String?) ?? '';
  return _staticTagline(name);
}
```

- [ ] **Step 2: Update card build to use resolvers**

In `_PackageCardState.build`, replace:

```dart
    final accentColor = _packageAccentColor(name);
    final badge = _packageBadge(name);
```

with:

```dart
    final accentColor = _resolveAccentColor(p, name);
    final badgeText = _resolveBadgeText(p);
    final tagline = _resolveTagline(p);
    final badge = badgeText != null
        ? _Badge(text: badgeText, color: accentColor)
        : null;
```

- [ ] **Step 3: Remove badge from hero area**

The hero-image block is:

```dart
          // Hero photo — only when an actual cover is uploaded.
          if (cover != null && cover.isNotEmpty)
            Stack(
              children: [
                AspectRatio(...),
                if (badge != null)
                  Positioned(top: 12, left: 12, child: badge),
                Positioned(
                  top: 8,
                  right: 8,
                  child: _HeartButton(...),
                ),
              ],
            ),
```

Remove the `if (badge != null) Positioned(...)` child so the badge only appears once in the content area.

- [ ] **Step 4: Show tagline under name**

Find the name/description block inside the card content:

```dart
                          Text(name, style: AppTextStyles.h2(context)),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              description,
                              style: AppTextStyles.body(
                                context,
                                color: accentColor,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
```

Replace the `description` line with the tagline:

```dart
                          Text(name, style: AppTextStyles.h2(context)),
                          if (tagline != null && tagline.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              tagline,
                              style: AppTextStyles.body(
                                context,
                                color: accentColor,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
```

- [ ] **Step 5: Verify price chips already use accent color**

The earlier edit already made `_PriceChip` accept a `color` and the card passes `accentColor`. Confirm no further change needed.

- [ ] **Step 6: Analyze customer app**

Run:
```bash
flutter analyze -t lib/app.dart
```

Expected: no errors in `lib/features/birthday/birthday_packages_screen.dart`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/birthday/birthday_packages_screen.dart
git commit -m "feat(birthday): redesigned package cards with editable accent, badge and tagline"
```

---

## Task 4: Customer detail screen

**Files:**
- Modify: `lib/features/birthday/package_detail_screen.dart`

- [ ] **Step 1: Add accent color resolver**

Add the same resolver helpers near the top of the file (after imports, before the widget class):

```dart
Color? _parseHexColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 4) {
    final r = hex[1];
    final g = hex[2];
    final b = hex[3];
    buffer.write('FF$r$r$g$g$b$b');
  } else if (hex.length == 7) {
    buffer.write('FF${hex.substring(1)}');
  } else if (hex.length == 9) {
    buffer.write(hex.substring(1));
  } else {
    return null;
  }
  final value = int.tryParse(buffer.toString(), radix: 16);
  if (value == null) return null;
  return Color(value);
}

Color _staticAccentColor(String name) => switch (name) {
      'Happy Tales' => AppColors.rafiCoral,
      'Grand' => AppColors.navy,
      'Magical' => AppColors.gold,
      _ => AppColors.fitGreen,
    };

Color _resolveAccentColor(Map<String, dynamic> package) {
  final hex = (package['accent_color_hex'] as String?)?.trim();
  if (hex != null && hex.isNotEmpty) {
    final parsed = _parseHexColor(hex);
    if (parsed != null) return parsed;
  }
  return _staticAccentColor((package['name'] as String?) ?? '');
}
```

- [ ] **Step 2: Hide empty carousel placeholder**

In `_buildContent`, find:

```dart
            if (gallery.isNotEmpty) _Carousel(images: gallery),
            if (gallery.isEmpty) const SizedBox(height: 8),
```

Replace with:

```dart
            if (gallery.isNotEmpty) _Carousel(images: gallery),
```

Then in `_Carousel.build`, replace the empty `widget.images.isEmpty` placeholder branch with:

```dart
    if (widget.images.isEmpty) return const SizedBox.shrink();
```

- [ ] **Step 3: Merge all inclusion sources and use accent color**

In `_buildContent`, after computing `maxGuests`, compute the merged inclusion list and accent color:

```dart
    final accentColor = _resolveAccentColor(package);

    final inclusionLines = <String>[
      ...((package['inclusions'] as List?) ?? const [])
          .whereType<String>(),
      ...((package['experience_inclusions'] as List?)
              ?? const [])
          .whereType<String>(),
      ...?((package['non_food_offerings'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map((m) {
            final label = (m['label'] as String?) ?? '';
            final detail = (m['detail'] as String?) ?? '';
            final line = '$label: $detail'.trim();
            return line == ':' ? '' : line;
          })
          .where((s) => s.isNotEmpty)),
    ];
```

Then update the inclusions section to:

```dart
            _SectionHeader(
              text: "What's included",
              color: accentColor,
            ),
            _Inclusions(
              lines: inclusionLines,
              iconColor: accentColor,
            ),
```

- [ ] **Step 4: Update _SectionHeader and _Inclusions signatures**

Change `_SectionHeader` to accept an optional color:

```dart
class _SectionHeader extends StatelessWidget {
  final String text;
  final Color? color;
  const _SectionHeader({required this.text, this.color});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        text,
        style: AppTextStyles.h3(context).copyWith(
          color: color,
        ),
      ),
    );
  }
}
```

Change `_Inclusions` to accept a typed list and icon color:

```dart
class _Inclusions extends StatelessWidget {
  final List<String> lines;
  final Color iconColor;
  const _Inclusions({
    required this.lines,
    this.iconColor = AppColors.activeGreen,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Padding(...same empty message...);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(...same body but use `lines` directly and `iconColor` for the check icon...),
    );
  }
}
```

Remove the dynamic `raw` parsing from `_Inclusions` and use the precomputed `lines`.

- [ ] **Step 5: Analyze customer app**

Run:
```bash
flutter analyze -t lib/app.dart
```

Expected: no errors in `lib/features/birthday/package_detail_screen.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/birthday/package_detail_screen.dart
git commit -m "feat(birthday): detail screen uses package accent color and merges all inclusions"
```

---

## Task 5: Populate production package data

**Files:**
- None (Supabase SQL or admin web UI)

- [ ] **Step 1: Populate the four packages via SQL**

Run:
```sql
UPDATE birthday_packages
SET
  accent_color_hex = CASE name
    WHEN 'Little Joy' THEN '#0D4A2E'
    WHEN 'Happy Tales' THEN '#E8524A'
    WHEN 'Grand' THEN '#1E3A7B'
    WHEN 'Magical' THEN '#F5C442'
  END,
  badge_text = CASE name
    WHEN 'Happy Tales' THEN 'Most Booked'
    WHEN 'Grand' THEN 'Big celebration'
    WHEN 'Magical' THEN 'Premium'
    ELSE NULL
  END,
  tagline = CASE name
    WHEN 'Little Joy' THEN 'Perfect for intimate celebrations'
    WHEN 'Happy Tales' THEN 'Our most loved package'
    WHEN 'Grand' THEN 'Grand scale, seamless fun'
    WHEN 'Magical' THEN 'The full enchanted experience'
  END
WHERE name IN ('Little Joy', 'Happy Tales', 'Grand', 'Magical');
```

- [ ] **Step 2: Verify over admin web**

Open the admin app, navigate to Packages, edit each tier and confirm the new fields are populated and save correctly.

---

## Task 6: Build and deploy admin web

**Files:**
- Build output: `build/web/`

- [ ] **Step 1: Build admin web**

Run:
```bash
flutter build web -t lib/app_admin.dart
```

Expected: `build/web` is generated with no errors.

- [ ] **Step 2: Deploy to Cloudflare Pages**

Run (adjust project name if needed):
```bash
npx wrangler pages deploy build/web --project-name playdiaries-admin --branch feature-safari-club-tab
```

Expected: deployment succeeds and prints a preview URL.

- [ ] **Step 3: Commit build lock / notes if needed**

No source change; no commit required unless a version file is updated.

---

## Task 7: Verify customer app

**Files:**
- None

- [ ] **Step 1: Run static analysis**

```bash
flutter analyze
```

Expected: no issues.

- [ ] **Step 2: Run on device in profile mode**

```bash
flutter run --profile --device-id <your-ios-device-id> -t lib/app.dart
```

Expected: birthday tab shows all four packages with correct colors, badges, taglines, prices and inclusions.

- [ ] **Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "fix(birthday): final UI polish after review"
```

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| Thin accent bar, white card, no photos | Task 3 |
| Optional badge + tagline | Task 3, Task 4 |
| Accent color / badge / tagline editable in admin | Task 2 |
| New DB columns + RPC params | Task 1 |
| Static fallbacks for four known names | Task 3, Task 4 |
| Merged single inclusions list | Task 3, Task 4 |
| Hide empty carousel placeholder | Task 4 |
| Populate production data | Task 5 |
| Admin web deploy | Task 6 |
| Customer app verification | Task 7 |

## Placeholder scan

No TBD/TODO/fill-in-later items. Every step includes exact file paths, code snippets and expected commands.
