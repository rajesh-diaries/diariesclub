# Safari Club Tab — Design Specification

**Date:** 2026-06-09  
**Feature:** Safari Club "Coming Soon" Tab + Waitlist  
**Status:** Approved  
**Author:** Kimi Code (brainstorming session)  

---

## 1. Background & Goals

Safari Club is a toddler activity program for 2–4 year olds (Mon–Fri, 9:30 AM–12:30 PM) focused on building four timeless character traits: **Brave, Curious, Kind, Creative**. It is positioned beyond preschool and daycare — not academic, not child-minding, but intentional character-building through play, story, and hands-on discovery.

This design covers the **"Coming Soon" phase** — a lightweight explainer tab that gauges parent interest before the full program launches. No payment, no teacher admin, no complex backend. Just a beautiful explainer + waitlist form.

**Design principles:**
- Premium and valued — not salesy
- Club feel — exclusive, warm, inviting
- Reuse existing assets (hero characters, announcements system)
- Clean, minimal, storybook aesthetic
- Jungle green (#2D5016) + safari gold (#F4A261) + soft cream (#FFF8E7)

---

## 2. Architecture & Placement

### 2.1 File Structure

```
lib/features/safari/
├── safari_screen.dart              # Main scrollable screen (all 8 sections)
└── widgets/
    ├── safari_hero_banner.dart     # Jungle gradient + character images + tagline
    ├── safari_announcement_card.dart  # Dynamic announcement from admin
    ├── safari_philosophy_card.dart    # Program description
    ├── safari_trait_card.dart      # Individual trait card (reused x4)
    ├── safari_what_it_is.dart      # Checklist section
    ├── safari_faq_section.dart     # FAQ accordion
    ├── safari_waitlist_form.dart   # Express Interest form
    └── safari_colors.dart          # Safari-specific color constants

lib/admin/safari_waitlist/
└── safari_waitlist_screen.dart     # Admin list view of waitlist entries

lib/core/router/
├── app_router.dart                 # Add /safari branch to StatefulShellRoute
└── app_shell.dart                  # Add 5th BottomNavigationBarItem
```

### 2.2 Entry Point

The Safari Club tab becomes the **5th bottom navigation tab**.

**Current tabs:** Home · Club · Adventure · Profile  
**New tabs:** Home · Club · Adventure · **Safari** · Profile

**Navigation changes:**
- `lib/core/router/app_router.dart` — add `StatefulShellBranch` with `/safari` route
- `lib/core/router/app_shell.dart` — add `BottomNavigationBarItem` with `PhosphorIconsRegular.treePalm` or `PhosphorIconsRegular.globeHemisphereWest`

### 2.3 State Management

- **Widget-level state:** `ConsumerStatefulWidget` for the form (validation, loading, success)
- **No new global providers** for v1 — uses existing `currentFamilyProvider` to pre-fill child name if available
- **Announcement data:** Reuses existing announcements query (same pattern as home screen cards)

### 2.4 Existing Code Reuse

| Component | Reuse Strategy |
|---|---|
| Hero images (`assets/hero/rafi.png`, etc.) | Direct reuse — same images used in Adventure tab |
| `PrimaryButton` | Direct reuse for CTA |
| `AppColors` / `AppTextStyles` | Direct reuse with Safari-specific accent colors |
| Announcements system | Reuse existing `announcements` table + admin panel |
| Supabase client | Direct reuse for waitlist insert |
| `AppTextStyles.h2`, `.body`, `.caption` | Direct reuse |

---

## 3. UI Design

### 3.1 Section 1: Dynamic Announcement Card

```
┌─────────────────────────────┐
│  [LATEST UPDATE]            │  gold pill badge
│  🌿 Safari Club is coming   │  white text on jungle gradient
│      soon.                  │
└─────────────────────────────┘
```

- **Background:** `linear-gradient(135deg, #2D5016, #3a6b1e)`
- **Pill badge:** Background `#F4A261`, text `#2D5016`, uppercase, 11px
- **Text:** 15px, white, line-height 1.5
- **Data source:** Existing `announcements` table, filtered by `category = 'safari'` or similar
- **Admin control:** Staff updates text via `/admin/announcements`
- **Margin:** 12px all sides, 16px border radius

### 3.2 Section 2: Hero Banner

```
┌─────────────────────────────┐
│  ○ ○ ○ ○   (4 char images)  │  72px circles, overlapping layout
│                             │
│  Safari Club                │  32px, bold, cream #FFF8E7
│  A club for little          │  17px, gold #F4A261
│      explorers.             │
│                             │
│  Ages 2–4 · Mon–Fri ·       │  14px, cream at 70% opacity
│  9:30 AM – 12:30 PM         │
└─────────────────────────────┘
```

- **Background:** `linear-gradient(180deg, #2D5016, #1a3009)`
- **Character images:** 4 circular images from `assets/hero/`:
  - `rafi.png` — Lion (Brave)
  - `gerry.png` — Giraffe (Curious)
  - `ellie.png` — Elephant (Kind)
  - `zena.png` — Chameleon (Creative)
- **Image size:** 72px diameter, `#FFF8E7` background, soft shadow
- **Layout:** Centered row with alternating vertical offset (2nd and 4th images raised by 12px)
- **Decorative orbs:** Two large gold circles at 10-15% opacity for depth
- **Padding:** 40px top, 36px bottom

### 3.3 Section 3: Philosophy Card

```
┌─────────────────────────────┐
│ Safari Club is a toddler    │
│ activity program that goes  │
│ beyond preschool and        │
│ daycare. We believe in      │
│ building character —        │
│ through play, story, and    │
│ hands-on discovery.         │
└─────────────────────────────┘
```

- **Background:** White
- **Padding:** 24px
- **Border radius:** 16px
- **Text:** 15px, `#4a4a4a`, centered, line-height 1.7
- **Shadow:** `0 2px 8px rgba(45,80,22,0.08)`

### 3.4 Section 4: The Four Traits

**Section header:** "The Four Traits" — 22px, `#2D5016`, centered

**Each trait card:**

```
┌─────────────────────────────┐
│ [img]  Brave like Rafi      │
│        The courage to try,  │
│        fail, and try again. │
│        ...                  │
└─────────────────────────────┘
```

- **Image:** 64px × 64px, 16px radius, left side
- **Title:** 17px, bold, `#2D5016`
- **Description:** 14px, `#666`, line-height 1.6
- **Background:** White, 16px radius, soft shadow
- **Gap between cards:** 16px

**Trait definitions:**

| Character | Image | Trait | Description |
|---|---|---|---|
| Rafi | `assets/hero/rafi.png` | **Brave** | The courage to try, fail, and try again. To speak up, stand tall, and explore the unknown without fear. |
| Gerry | `assets/hero/gerry.png` | **Curious** | The hunger to ask "why?" and "what if?" To look closer, reach higher, and never stop wondering about the world. |
| Ellie | `assets/hero/ellie.png` | **Kind** | The strength to care, share, and include others. True confidence comes from lifting people up, not putting them down. |
| Zena | `assets/hero/zena.png` | **Creative** | The ability to see what isn't there yet. To adapt, imagine, and build something new from the pieces around you. |

### 3.5 Section 5: What Safari Club Is

**Header:** "What Safari Club Is" — 18px, `#2D5016`, centered

**Checklist (5 items):**
- ✓ Character building through play & activities
- ✓ Small groups with dedicated guides
- ✓ Screen-free mornings of real play
- ✓ A calm, intentional morning routine
- ✓ A toddler activity program beyond preschool & daycare

- **Checkmark:** `#5BAD4E`, 20px
- **Text:** 15px, `#4a4a4a`
- **Gap:** 14px between items
- **Background:** White card, 24px padding, 16px radius

### 3.6 Section 6: FAQ

**Header:** "Questions Parents Ask" — 22px, `#2D5016`, centered

**3 questions:**

1. **"What will my child do each morning?"**
   > Activities are designed around the four traits — creative exploration, collaborative play, sensory discovery, and confidence-building. The specific activities evolve as we learn what engages our little explorers best. No screens, ever.

2. **"Can I stay during the session?"**
   > We have a dedicated parent viewing area. You're also welcome to relax at our cafe with complimentary coffee while your explorer adventures.

3. **"Is this a preschool?"**
   > Safari Club is a toddler activity program that goes beyond preschool and daycare. We focus on character development through play — not academics, worksheets, or rankings.

- **Question:** 15px, bold, `#2D5016`
- **Answer:** 14px, `#666`, line-height 1.6, 8px top margin
- **Card:** White, 16px padding, 12px radius, subtle shadow
- **Gap:** 10px between cards

### 3.7 Section 7: Express Interest Form

**Header:** "Express Interest" — 22px, `#2D5016`, centered  
**Subtext:** "Be the first to know when Safari Club opens." — 15px, `#666`, centered

**Fields:**

| Field | Type | Validation |
|---|---|---|
| Your Name | Text input | Required, min 2 chars |
| Phone Number | Phone input | Required, valid Indian mobile |
| Child's Name | Text input | Required, min 2 chars |
| Child's Age | Segmented buttons (2 / 3 / 4) | Required, single select |

**CTA:** "Express Interest" — full width, `#2D5016` background, `#FFF8E7` text, 16px font, 16px padding  
**Subtext below CTA:** "We'll reach out when enrollment opens." — 13px, `#999`, centered

**Form states:**
- **Default:** All fields empty, CTA enabled
- **Validating:** Show inline errors below each field
- **Submitting:** CTA shows loading spinner, disabled
- **Success:** Form replaced with thank you message: *"Thank you! We'll reach out when Safari Club opens."* + green checkmark

### 3.8 Section 8: Footer

- **Text:** "Safari Club · Play Diaries"
- **Style:** 12px, `#aaa`, centered
- **Padding:** 32px bottom

---

## 4. Scroll Behavior & Layout

- **Screen type:** Single scrollable `ListView`
- **Padding:** 0px horizontal for full-bleed hero, 20px horizontal for content sections
- **Section spacing:** 32px between major sections
- **Bottom padding:** 32px (above safe area)
- **No app bar** — hero banner serves as the visual header

---

## 5. Backend Integration (Supabase)

### 5.1 Database Schema: `safari_waitlist`

```sql
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
```

### 5.2 Row Level Security

```sql
ALTER TABLE public.safari_waitlist ENABLE ROW LEVEL SECURITY;

-- Users can only insert (not read)
CREATE POLICY "Anyone can join waitlist"
  ON public.safari_waitlist FOR INSERT
  WITH CHECK (true);

-- Admin users can read all
CREATE POLICY "Admins can view waitlist"
  ON public.safari_waitlist FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.admin_users 
    WHERE user_id = auth.uid() AND is_active = true
  ));

-- Admin users can update
CREATE POLICY "Admins can update waitlist"
  ON public.safari_waitlist FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.admin_users 
    WHERE user_id = auth.uid() AND is_active = true
  ));
```

### 5.3 Insert Logic (Flutter)

```dart
Future<void> _submitWaitlist() async {
  final family = ref.read(currentFamilyProvider).valueOrNull;
  
  await Supabase.instance.client.from('safari_waitlist').insert({
    'family_id': family?['id'],
    'parent_name': _parentNameController.text.trim(),
    'phone': _phoneController.text.trim(),
    'child_name': _childNameController.text.trim(),
    'child_age': _selectedAge,
    'source': 'app',
  });
}
```

### 5.4 Pre-fill Logic

If the user is logged in and has children in their family:
- Pre-fill child name from `family_children_provider` (first child)
- Pre-fill phone from `currentFamilyProvider`
- Parent can edit all fields before submitting

---

## 6. Admin Panel Integration

### 6.1 Admin Screen: Safari Waitlist

**Route:** `/admin/safari-waitlist`  
**Location:** `lib/admin/safari_waitlist/safari_waitlist_screen.dart`

**Features:**
- Data table showing all waitlist entries
- Columns: Parent Name, Phone, Child Name, Age, Status, Date
- Status dropdown: pending → contacted → enrolled → declined
- Admin notes text field per row
- Search/filter by phone or child name
- Export to CSV (optional v2)

**Navigation:** Add "Safari Waitlist" item to `AdminSidebar`

### 6.2 Admin Sidebar Update

Add to `lib/admin/widgets/admin_sidebar.dart`:
```dart
AdminNavItem(
  icon: PhosphorIconsRegular.treePalm,
  label: 'Safari Waitlist',
  route: '/admin/safari-waitlist',
),
```

### 6.3 Admin Router Update

Add to `lib/admin/admin_router.dart`:
```dart
GoRoute(
  path: '/admin/safari-waitlist',
  builder: (_, __) => const SafariWaitlistScreen(),
),
```

---

## 7. Announcements Integration

The Safari tab reuses the existing announcements system:

**How it works:**
1. Admin creates an announcement in `/admin/announcements` with `category = 'safari'`
2. Safari tab fetches the latest safari announcement
3. Displays it as the green gradient card at the top

**Flutter query:**
```dart
final announcement = await Supabase.instance.client
  .from('announcements')
  .select('title, body, created_at')
  .eq('category', 'safari')
  .eq('is_active', true)
  .order('created_at', ascending: false)
  .limit(1)
  .maybeSingle();
```

**Fallback:** If no safari announcement exists, the card is hidden.

---

## 8. Error Handling

| Scenario | Behavior |
|---|---|
| **Network error on submit** | Show SnackBar: "Something went wrong. Please try again." + retry button |
| **Duplicate phone number** | Allow duplicate (parents may join for multiple children). Show confirmation: "You're already on the list! We'll reach out soon." |
| **Invalid phone number** | Inline error: "Please enter a valid phone number" |
| **Missing required field** | Inline error below field, CTA disabled until valid |
| **Supabase auth error** | Allow anonymous submission (family_id = null). Form works for guests too. |
| **Announcement fetch fails** | Hide announcement card gracefully. Rest of screen loads normally. |

---

## 9. Testing Checklist

### 9.1 UI
- [ ] Hero banner renders with 4 character images
- [ ] Tagline "A club for little explorers." visible
- [ ] All 8 sections scroll smoothly
- [ ] Form validation works (empty fields, invalid phone)
- [ ] Age selection (2/3/4) is single-select
- [ ] Success state shows after submission
- [ ] Pre-fill works for logged-in users with children
- [ ] Screen works for logged-out users (no crash)

### 9.2 Backend
- [ ] Waitlist entry saves to Supabase
- [ ] RLS allows insert from any user
- [ ] RLS restricts read/update to admins only
- [ ] family_id is nullable (works for guests)
- [ ] Admin screen shows all entries
- [ ] Status update works from admin panel

### 9.3 Integration
- [ ] 5th tab appears in bottom nav
- [ ] Tab icon is consistent with Safari theme
- [ ] Announcement card fetches from admin panel
- [ ] No announcement = card hidden (not empty)
- [ ] Admin sidebar shows "Safari Waitlist" link

---

## 10. Dependencies

Already present in `pubspec.yaml`:
- `flutter_riverpod: ^2.5.1` — State management
- `go_router: ^14.0.0` — Routing
- `supabase_flutter: ^2.5.0` — Backend
- `phosphor_flutter: ^2.1.0` — Icons
- `google_fonts: ^6.2.1` — Nunito font

**No new dependencies required.**

---

## 11. Migration Plan

**Day 1 — Parent App:**
1. Add `safari_waitlist` table + RLS (migration)
2. Create `SafariScreen` with all 8 sections
3. Add `/safari` route to `app_router.dart`
4. Add 5th tab to `AppShell`
5. Build `SafariWaitlistForm` with validation + Supabase insert

**Day 2 — Admin + Polish:**
1. Create `SafariWaitlistScreen` for admin
2. Add route to `admin_router.dart`
3. Add nav item to `AdminSidebar`
4. Connect announcement card to existing system
5. Test on Android + iOS
6. Handle edge cases (guest users, network errors)

---

## 12. Future Enhancements (v2+)

- **Teacher admin panel** — Zone selector, attendance, photo upload, badges
- **Safari Map** — Live zone status for enrolled children
- **Explorer's Backpack** — Badges, artwork, polaroid photos
- **Safari Postcard** — Auto-generated daily update
- **Character Letter** — Friday letter from a character
- **Enrollment & Payment** — Razorpay integration
- **Ecosystem connections** — Club tab coffee banner, FIT lunch boxes
- **Push notifications** — Check-in, photos, postcard, letter

---

## 13. Open Questions

1. **Character images:** Confirm `assets/hero/rafi.png`, `gerry.png`, `ellie.png`, `zena.png` are the final Safari Club illustrations.
2. **Announcement category:** Does the existing `announcements` table have a `category` column? If not, add it or use a different filtering mechanism.
3. **Pre-fill behavior:** Should we pre-fill the child's name from the family's first child, or show a dropdown if multiple children exist?
4. **Admin access:** Which admin roles should see the Safari Waitlist? All admins or a specific role?

---

## 14. References

- Existing hero assets: `assets/hero/rafi.png`, `gerry.png`, `ellie.png`, `zena.png`
- Announcements admin: `lib/admin/announcements/`
- Admin sidebar: `lib/admin/widgets/admin_sidebar.dart`
- Admin router: `lib/admin/admin_router.dart`
- App router: `lib/core/router/app_router.dart`
- App shell: `lib/core/router/app_shell.dart`
- Profile screen (children list): `lib/features/profile/profile_screen.dart`
