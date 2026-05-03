# Session 5b — Profile Tab

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-5 complete.

---

## Session Header

```
I am building Diaries Club. Database, RPCs, foundation, auth, home tab all done.
This session: build the complete Profile tab with all settings, family management,
referral, wallet history, help, and account deletion.

Estimated time: 4-5 hours
What to build:
  - Profile screen (single sectioned screen, iOS Settings style)
  - Referral card (promoted at top, dedicated)
  - Family section: list + add child + edit child screen
  - Wallet history (full transaction list with filters)
  - Activity history (sessions, orders, workshops)
  - Settings (theme, notifications, language placeholder)
  - Help screen (FAQ + WhatsApp + phone)
  - Pre-booking entry (per locked decision: Profile-only, not promoted)
  - Account deletion with strong "Type DELETE" confirmation
  - Edit family name and email
  - About / version info / legal links

What NOT to build:
  - Adventure tab profile cards (Session 8)
  - Birthday booking (Session 9)
  - Order history details (covered in Activity)

Output expected:
  - Complete profile flow in lib/features/profile/
  - All sub-screens functional
  - Realtime updates work for wallet, family, child changes
  - Account deletion calls family_anonymise RPC and signs out cleanly

Acceptance:
  - Profile loads with all sections visible
  - Referral card shows code + share button
  - Add second child → appears in family section
  - Wallet history shows all 14 transaction types correctly formatted
  - Pre-booking entry visible only in Profile (not promoted elsewhere)
  - "Type DELETE to confirm" requires literal DELETE input
  - Post-deletion: signs out, shows farewell screen, anonymisation worked in DB
```

---

## 1. Profile Screen Architecture

### 1.1 Single sectioned screen layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back?] Profile           [bell]    │
├─────────────────────────────────────┤
│ HEADER ROW                          │
│ [avatar] Family Name           [✏]  │
│          +91 98765-43210            │
├─────────────────────────────────────┤
│ ★ REFERRAL CARD (promoted)          │
│   "Invite a friend, earn ₹200"      │
│   Code: AARAV2024 [Share]           │
├─────────────────────────────────────┤
│ ── FAMILY ──                        │
│ My kids                             │
│  • Aarav (5)            >           │
│  • Riya (8)             >           │
│  + Add child                        │
├─────────────────────────────────────┤
│ ── WALLET ──                        │
│ Balance         ₹1,250    [Top up]  │
│ History                       >     │
│ Pre-book a session            >     │
├─────────────────────────────────────┤
│ ── ACTIVITY ──                      │
│ Past sessions                 >     │
│ Past orders                   >     │
│ Workshops attended            >     │
│ Birthday parties              >     │
├─────────────────────────────────────┤
│ ── SETTINGS ──                      │
│ Theme            System       >     │
│ Notifications                 >     │
│ Language         English      >     │
├─────────────────────────────────────┤
│ ── SUPPORT ──                       │
│ Help & FAQ                    >     │
│ Talk to us on WhatsApp        ↗     │
│ Call us                       ↗     │
├─────────────────────────────────────┤
│ ── ACCOUNT ──                       │
│ Privacy Policy                ↗     │
│ Terms                         ↗     │
│ Refund Policy                 ↗     │
│ App version 1.0.0+1                 │
│                                     │
│ [Sign out]    secondary             │
│ [Delete account]   muted/red text   │
├─────────────────────────────────────┤
│ Bottom nav (Profile active)         │
└─────────────────────────────────────┘
```

### 1.2 Why single-screen

iOS Settings model is familiar to Indian smartphone users. Everything scannable in one place reduces "where do I find X?" friction. Sub-pages exist for editing actions (edit child, wallet history, etc.), but the discovery is on the main screen.

---

## 2. Profile Screen — `lib/features/profile/profile_screen.dart`

### 2.1 Implementation pattern

```dart
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final family = ref.watch(currentFamilyProvider);
    final children = ref.watch(familyChildrenProvider);
    final wallet = ref.watch(currentWalletProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        actions: [
          NotificationBellButton(),
        ],
      ),
      body: family.when(
        data: (f) => CustomScrollView(
          slivers: [
            // Header row
            SliverToBoxAdapter(child: _ProfileHeader(family: f)),

            // Referral card (promoted)
            SliverToBoxAdapter(child: ReferralCard(family: f)),

            // Family section
            const _SectionHeader(title: "Family"),
            SliverToBoxAdapter(
              child: ChildrenList(children: children.valueOrNull ?? []),
            ),

            // Wallet section
            const _SectionHeader(title: "Wallet"),
            SliverToBoxAdapter(child: _WalletSection(wallet: wallet.valueOrNull)),

            // Activity section
            const _SectionHeader(title: "Activity"),
            SliverList(delegate: SliverChildListDelegate([
              _NavRow(label: "Past sessions", route: '/profile/sessions'),
              _NavRow(label: "Past orders", route: '/profile/orders'),
              _NavRow(label: "Workshops attended", route: '/profile/workshops'),
              _NavRow(label: "Birthday parties", route: '/profile/birthdays'),
            ])),

            // Settings section
            const _SectionHeader(title: "Settings"),
            SliverList(delegate: SliverChildListDelegate([
              ThemeRow(),
              _NavRow(label: "Notifications", route: '/profile/notifications-settings'),
              _NavRow(label: "Language", trailing: "English", route: '/profile/language'),
            ])),

            // Support section
            const _SectionHeader(title: "Support"),
            SliverList(delegate: SliverChildListDelegate([
              _NavRow(label: "Help & FAQ", route: '/profile/help'),
              _ExternalRow(label: "Talk to us on WhatsApp", url: WHATSAPP_LINK),
              _ExternalRow(label: "Call us", url: TEL_LINK),
            ])),

            // Account section
            const _SectionHeader(title: "Account"),
            SliverList(delegate: SliverChildListDelegate([
              _ExternalRow(label: "Privacy Policy", url: 'https://diariesclub.com/privacy'),
              _ExternalRow(label: "Terms", url: 'https://diariesclub.com/terms'),
              _ExternalRow(label: "Refund Policy", url: 'https://diariesclub.com/refund-policy'),
              _AppVersionRow(),
              const SizedBox(height: 16),
              const _SignOutButton(),
              const _DeleteAccountButton(),
              const SizedBox(height: 80), // bottom padding
            ])),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-PROF', userMessage: 'Couldn\'t load profile'),
      ),
    );
  }
}
```

### 2.2 Profile header row

```dart
class _ProfileHeader extends ConsumerWidget {
  final Family family;
  const _ProfileHeader({required this.family});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Avatar (initials if no photo)
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withOpacity(0.2),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(family.name),
              style: AppTextStyles.h2(c, color: AppColors.navy),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(family.name, style: AppTextStyles.h3(c)),
                const SizedBox(height: 4),
                Text(
                  PhoneNormalizer.forDisplay(family.phone),
                  style: AppTextStyles.caption(c),
                ),
              ],
            ),
          ),
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.pencilSimple()),
            onPressed: () => _showEditProfileSheet(c),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }
}
```

Edit profile sheet allows changing family name and email (phone is immutable — that's the auth identifier).

---

## 3. Referral Card — `lib/features/profile/widgets/referral_card.dart`

### 3.1 Layout

```
┌─────────────────────────────────────┐
│  ✦ Invite a friend                  │
│                                     │
│  Friends who join through your code │
│  get ₹100 in their wallet. You get  │
│  ₹200 when they play their first    │
│  session.                           │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ AARAV2024              [Copy] │  │
│  └───────────────────────────────┘  │
│                                     │
│  [Share via WhatsApp]   PRIMARY     │
│  [Show details]         text link   │
└─────────────────────────────────────┘
```

Background: warm gradient (gold accent over navy). Sits at the top of Profile, prominent.

### 3.2 Logic

```dart
class ReferralCard extends ConsumerWidget {
  final Family family;
  const ReferralCard({super.key, required this.family});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A4A8B), AppColors.navy],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              Text("Invite a friend",
                style: AppTextStyles.h3(c, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Friends who join with your code get ₹100. You get ₹200 when they play their first session.",
            style: AppTextStyles.body(c, color: Colors.white70),
          ),
          const SizedBox(height: 16),

          // Code box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    family.referralCode,
                    style: AppTextStyles.h3(c, color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () => _copyCode(c, family.referralCode),
                  child: Text("Copy",
                    style: AppTextStyles.button(c, color: AppColors.gold)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Share button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _shareViaWhatsApp(family.referralCode),
              icon: PhosphorIcon(PhosphorIcons.whatsappLogo(), color: Colors.white),
              label: Text("Share via WhatsApp",
                style: AppTextStyles.button(c)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.activeGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Details link
          Center(
            child: TextButton(
              onPressed: () => context.push('/profile/referral-details'),
              child: Text("Show details",
                style: AppTextStyles.caption(c, color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  void _copyCode(BuildContext c, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: Text("Code copied: $code"),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _shareViaWhatsApp(String code) async {
    // Generate Branch deep link
    final branchUrl = await _generateBranchLink(code);

    final text = "Hey! I love Diaries Club for the kids. "
                 "Use my code $code when you sign up — you get ₹100, I get ₹200 "
                 "when you play your first session.\n\n$branchUrl";

    await Share.share(text);
  }
}
```

### 3.3 Referral details screen

`/profile/referral-details` — shows:
- How it works (3 steps)
- Conversion history: list of friends who joined and converted
- This month's referrals: count out of monthly cap (e.g., "2 of 5 this month")
- Total earned via referrals

---

## 4. Family Section

### 4.1 Children list

```dart
class ChildrenList extends ConsumerWidget {
  final List<Child> children;
  const ChildrenList({super.key, required this.children});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Column(
      children: [
        ...children.map((child) => _ChildRow(child: child)),
        ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withOpacity(0.15),
            ),
            child: PhosphorIcon(PhosphorIcons.plus(), color: AppColors.navy),
          ),
          title: Text("Add a child", style: AppTextStyles.body(c)),
          onTap: () => context.push('/profile/add-child'),
        ),
      ],
    );
  }
}

class _ChildRow extends StatelessWidget {
  final Child child;
  @override
  Widget build(BuildContext c) {
    final age = _calculateAge(child.dateOfBirth);
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: child.photoUrl != null
          ? CachedNetworkImageProvider(child.photoUrl!) as ImageProvider
          : null,
        backgroundColor: _heroColor(child.favouriteHero),
        child: child.photoUrl == null
          ? Text(child.name[0], style: const TextStyle(color: Colors.white))
          : null,
      ),
      title: Text(child.name),
      subtitle: Text("$age years old"),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/profile/child/${child.id}'),
    );
  }
}
```

### 4.2 Add child screen — `/profile/add-child`

Reuses the onboarding child-details + hero-pick screens but as a single combined screen (since we're past onboarding).

```
APP BAR
  - Back arrow
  - Title: "Add a child"

FORM (same fields as onboarding):
  - Photo upload (optional)
  - First name (required)
  - Date of birth (required)
  - Delivery address (optional)

HERO SELECTION
  - 2x2 grid (same as onboarding hero-pick)
  - Pick favourite

PRIMARY CTA
  - "Add to family"
```

On submit:
1. INSERT into children with selected hero
2. Update `families.has_children = true` if was false
3. Navigate back to Profile
4. Show toast: "[Name] added to your family!"

### 4.3 Edit child screen — `/profile/child/:id`

Same fields as add-child, pre-populated. Includes a "Remove child" option at the bottom (rare action, with confirmation).

**Removing a child:**
- Confirmation: "Remove [Name] from your family?"
- Body: "Their adventure progress, hero cards, and history will be archived but kept for your records."
- On confirm: `UPDATE children SET archived_at = now()` (soft-delete via spec extension — add column in a follow-up migration)
- Cannot remove the only child in family if `is_cafe_only = false` (toast: "Add another child first or set this account to cafe-only via settings")

---

## 5. Wallet Section

### 5.1 Profile wallet row

```
Balance              ₹1,250    [Top up]
History                          >
Pre-book a session               >
```

Tap "Top up" → opens TopUpSheet (same component from Session 5).
Tap "History" → navigates to `/profile/wallet-history`.
Tap "Pre-book a session" → navigates to `/profile/pre-book` (per locked decision).

### 5.2 Wallet History screen — `/profile/wallet-history`

```
APP BAR
  - Back arrow
  - Title: "Wallet history"
  - Right: Filter icon → opens filter sheet

CURRENT BALANCE BANNER
  - "₹1,250 available"
  - "+450 Diaries Coins earned (lifetime)"

FILTER PILLS (horizontal scroll)
  All | Top-ups | Sessions | Orders | Refunds | Bonuses

TRANSACTION LIST (grouped by date)
  TODAY
    [icon] Topped up               +₹500
           Razorpay                4:32 PM
    [icon] 1-hour session          -₹800
           Aarav                   2:15 PM
  YESTERDAY
    [icon] Order at Coffee Diaries -₹325
           with ₹23 coins back     Mar 28
  LAST 7 DAYS
    ...

INFINITE SCROLL
  - Load 20 at a time
  - Pull to refresh
```

### 5.3 Transaction row by type

Display logic for each `wallet_transactions.type`:

| Type | Icon | Title | Amount | Color |
|---|---|---|---|---|
| `topup` | `wallet` | Topped up | +₹X | green |
| `bonus` | `gift` | Bonus credit | +₹X | gold |
| `session_debit` | `clock` | X-hour session, [child] | -₹X | navy |
| `extension_debit` | `clock_clockwise` | Session extended | -₹X | navy |
| `order_debit` | `coffee` / `salad` | Order at [brand] | -₹X | navy |
| `workshop_debit` | `paint_brush` | Workshop: [name] | -₹X | navy |
| `birthday_deposit_debit` | `cake` | Birthday deposit | -₹X | navy |
| `birthday_balance_debit` | `cake` | Birthday balance | -₹X | navy |
| `refund` | `arrow_uturn_left` | Refund: [reason] | +₹X | green |
| `coins_credit` | `star` | Diaries Coins earned | +X coins | gold |
| `reactivation_credit` | `sparkle` | Welcome back credit | +₹X | gold |
| `visit_bonus` | `confetti` | Visit milestone reward | +₹X | gold |
| `streak_milestone` | `flame` | Streak reward | +₹X | gold |
| `manual_credit` / `manual_debit` | `pencil` | Admin adjustment | ±₹X | grey |

Tap any row → detail sheet showing:
- Full timestamp
- Reference (session ID, order ID, etc.) — tappable to view that session/order
- Razorpay payment ID if applicable
- Idempotency key (debugging context for support)

### 5.4 Pre-booking entry — `/profile/pre-book`

Per locked decision, this is the only entry point.

```
APP BAR
  - Back arrow
  - Title: "Pre-book a session"

EXPLANATION
  - "Reserve a play time in advance."
  - "We'll hold a slot with a 50% deposit from your wallet. The rest is paid
     when you check in."

CHILD SELECTOR
  - Avatar row, pick which child

DATE PICKER
  - Calendar widget, max 14 days ahead
  - Disabled past dates, today included

TIME PICKER
  - Show available time slots (admin-managed via venue_config)
  - 1-hour granularity (e.g., 10am, 11am, ..., 7pm)

DURATION
  - 1 hour / 2 hours toggle

PRICING SUMMARY
  - Total: ₹1,100
  - Hold now: ₹550 (from wallet)
  - Pay at venue: ₹550

PRIMARY CTA
  - "Hold this slot"
  - Calls pre_booking_create RPC
```

On success: shows confirmation screen with reservation summary, deep link saved to calendar option, and "View my bookings" link.

If wallet insufficient for hold amount → show TopUpSheet immediately with required amount pre-selected.

---

## 6. Activity Section — Sub-screens

Each activity sub-screen follows the same pattern: filter pills, infinite scroll, grouped by date.

### 6.1 Past sessions — `/profile/sessions`

```
TRANSACTION ROW
  ┌─────────────────────────────────────┐
  │ [duration icon] Aarav · 2 hours     │
  │ Mar 28 · Saturday afternoon         │
  │ Reflected · +120 XP earned          │
  │                                     │
  │ Tap → /profile/sessions/:id         │
  └─────────────────────────────────────┘

FILTERS
  All | Reflected | Auto-split | Active | Cancelled
```

Detail screen shows: child, duration, payment method, amount, XP per trait, hero card earned (if any), reflection moments tapped (if any).

### 6.2 Past orders — `/profile/orders`

```
TRANSACTION ROW
  ┌─────────────────────────────────────┐
  │ [coffee icon] Coffee Diaries        │
  │ Cappuccino, Croissant   ₹325        │
  │ Mar 28 · Got 23 Diaries Coins       │
  │                                     │
  │ Tap → /profile/orders/:id           │
  └─────────────────────────────────────┘

FILTERS
  All | Coffee | FIT | Combos
```

Detail screen shows: full item list with quantities, prices, GST breakdown, payment method, and **"Download invoice" button** (gets PDF from Edge Function).

### 6.3 Workshops attended — `/profile/workshops`

Shows past workshop registrations: workshop title, date, attended status, XP awarded.

### 6.4 Birthday parties — `/profile/birthdays`

Shows: upcoming + past birthday reservations. Tap → opens reservation status (Session 9). For completed parties, shows album link.

---

## 7. Settings Section

### 7.1 Theme row

```dart
class ThemeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return ListTile(
      leading: PhosphorIcon(PhosphorIcons.palette()),
      title: const Text("Theme"),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_label(mode)),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _showThemeSheet(c, ref),
    );
  }

  String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => "System",
    ThemeMode.light => "Light",
    ThemeMode.dark => "Dark",
  };

  void _showThemeSheet(BuildContext c, WidgetRef ref) =>
    showModalBottomSheet(
      context: c,
      builder: (_) => ThemeSelectorSheet(),
    );
}
```

Sheet shows 3 radio options: System / Light / Dark. Selection persists immediately via `appThemeModeProvider.set()`.

### 7.2 Notifications settings — `/profile/notifications-settings`

Per-category toggles, all enabled by default:
- Session reminders
- Hero progression alerts
- Birthday reminders
- Order status updates
- Wallet alerts (low balance, top-ups confirmed)
- Marketing & offers (matches `families.marketing_consent` — same toggle)
- Streak & milestones
- Workshop reminders

Each toggle stores preference in a new `notification_preferences` JSON column on families (add migration).

```sql
-- Migration: add notification_preferences to families
ALTER TABLE families ADD COLUMN IF NOT EXISTS notification_preferences JSONB DEFAULT '{
  "session_reminders": true,
  "hero_progression": true,
  "birthday_reminders": true,
  "order_status": true,
  "wallet_alerts": true,
  "marketing": false,
  "streaks_milestones": true,
  "workshop_reminders": true
}';
```

When dispatching notifications via Edge Function, check the relevant key before sending.

### 7.3 Language — `/profile/language`

Currently shows only "English" with a "Coming soon: हिन्दी, తెలుగు" caption. No actual switching for v1.

---

## 8. Help Screen — `/profile/help`

```
APP BAR
  - Back
  - Title: "Help"

QUICK CONTACT BAR (top, prominent)
  ┌─────────────────────────────────────┐
  │ Need urgent help?                   │
  │ [WhatsApp]  [Call]                  │
  └─────────────────────────────────────┘

FAQ SECTIONS (accordion)
  ▼ About Diaries Club
     What is Diaries Club?
     What are Diaries Coins?
     Why have a wallet?
  ▼ Sessions
     How do play sessions work?
     What if my time runs out?
     Can I extend?
  ▼ Wallet & Payments
     How do top-up offers work?
     Are wallet credits refundable?
     Why is my balance not updating?
  ▼ Hero Adventure
     How do my kids earn XP?
     What are hero traits?
     How do reflections work?
  ▼ Birthdays
     How do I book a birthday?
     Can I cancel?
     What's included?
  ▼ Account
     How do I edit my info?
     Can I delete my account?
     Privacy and data

REPORT AN ISSUE BUTTON
  - Opens WhatsApp with prefilled context:
    "I need help with: [type below]
     My phone: +91 98765-43210
     App version: 1.0.0+1
     Error code: [if any]"

ESCALATION CARD
  - "Still stuck?"
  - Phone + WhatsApp + email options
```

FAQ content is hardcoded in v1 (no CMS). Can be moved to admin-editable later if needed.

---

## 9. Account Section

### 9.1 Sign out

```dart
class _SignOutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _confirmSignOut(c, ref),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text("Sign out"),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext c, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text("Sign out?"),
        content: const Text("You'll need to enter your phone number again to sign back in."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Sign out")),
        ],
      ),
    );
    if (confirmed == true) {
      // Clear local storage
      await SharedPreferences.getInstance().then((p) => p.clear());
      await const FlutterSecureStorage().deleteAll();

      await Supabase.instance.client.auth.signOut();
      if (c.mounted) context.go('/auth/phone');
    }
  }
}
```

### 9.2 Delete account — `_DeleteAccountButton`

Two-stage process per locked decision (strong friction, immediate anonymisation).

```dart
class _DeleteAccountButton extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextButton(
        onPressed: () => context.push('/profile/delete-account'),
        child: Text(
          "Delete account",
          style: AppTextStyles.caption(c, color: AppColors.adminRed),
        ),
      ),
    );
  }
}
```

### 9.3 Delete account screen — `/profile/delete-account`

```
APP BAR
  - Back arrow
  - Title: "Delete account"

WARNING BANNER (red-tinted)
  - Icon: warning triangle
  - "This action is permanent."

WHAT WILL HAPPEN
  Your account will be permanently anonymised:
  ✓ Your name, phone, and email will be removed
  ✓ Your children's names and photos will be deleted
  ✓ Your wallet balance will be lost
  ✓ Your hero cards and progress will be deleted

  We'll keep:
  • Transaction history (required for tax records)

  Once deleted, your account cannot be recovered.
  You'd need to sign up fresh with this phone number.

WALLET BALANCE BANNER (if > 0)
  ⚠ You have ₹1,250 in your wallet that will be lost.
  [Use it before deleting] → /home

CONFIRMATION INPUT
  Type DELETE to confirm:
  ┌──────────────────────┐
  │                      │
  └──────────────────────┘

PRIMARY CTA (disabled until input matches "DELETE" exactly)
  [Permanently delete my account]   RED

CANCEL LINK
  [Never mind, take me back]
```

### 9.4 Delete logic

```dart
class DeleteAccountScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _isDeleting = false;

  bool get _canDelete =>
    _confirmController.text == 'DELETE' && !_isDeleting;

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    final familyId = Supabase.instance.client.auth.currentUser!.id;

    try {
      await Supabase.instance.client.rpc(
        'family_anonymise',
        params: {'p_family_id': familyId},
      );

      // Clear everything locally
      await SharedPreferences.getInstance().then((p) => p.clear());
      await const FlutterSecureStorage().deleteAll();
      await Supabase.instance.client.auth.signOut();

      // Show farewell screen
      if (mounted) context.go('/farewell');
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      setState(() => _isDeleting = false);
      _showError("Couldn't delete account. Please contact support.");
    }
  }

  // build() renders the layout above
}
```

### 9.5 Farewell screen — `/farewell`

Brief, dignified screen:
```
APP BAR — none

CONTENT (centered)
  Soft Lottie animation (gentle wave)
  "Your account has been deleted."
  "Thanks for being part of Diaries Club."
  "We're sorry to see you go."

  [Back to start]  → restarts to /auth/phone
```

---

## 10. Edit Family Profile Sheet

Triggered by pencil icon in profile header.

```
BOTTOM SHEET
  Title: "Edit profile"
  Fields:
    - Family name (text field)
    - Email (text field, optional)
  
  Phone shown as read-only:
    "Phone: +91 98765-43210"
    "To change phone, contact support"

  [Save] PRIMARY
  [Cancel] secondary
```

On save: UPDATE families row.

---

## 11. Files to Create

```
lib/
└── features/
    └── profile/
        ├── profile_screen.dart
        ├── widgets/
        │   ├── referral_card.dart
        │   ├── children_list.dart
        │   ├── theme_selector_sheet.dart
        │   ├── edit_profile_sheet.dart
        │   ├── transaction_row.dart
        │   ├── activity_row.dart
        │   └── faq_accordion.dart
        ├── add_child_screen.dart
        ├── edit_child_screen.dart
        ├── referral_details_screen.dart
        ├── wallet_history_screen.dart
        ├── pre_booking_screen.dart
        ├── past_sessions_screen.dart
        ├── session_detail_screen.dart
        ├── past_orders_screen.dart
        ├── order_detail_screen.dart
        ├── past_workshops_screen.dart
        ├── past_birthdays_screen.dart
        ├── notifications_settings_screen.dart
        ├── language_screen.dart
        ├── help_screen.dart
        ├── delete_account_screen.dart
        └── farewell_screen.dart
```

---

## 12. Acceptance Tests

```
TEST 1 — Profile loads
  1. Sign in → tap Profile tab
  2. All sections visible: header, referral card, family, wallet, activity, settings, support, account
  3. Family name displays correctly
  4. Phone displays formatted: "+91 98765-43210"

TEST 2 — Referral card
  1. Tap "Copy" → snackbar confirms code copied
  2. Tap "Share via WhatsApp" → opens WhatsApp with prefilled message + Branch link
  3. Tap "Show details" → /profile/referral-details

TEST 3 — Add second child
  1. Tap "Add a child" → /profile/add-child
  2. Fill form, pick hero, submit
  3. Returns to Profile, new child appears in list
  4. families.has_children = true

TEST 4 — Edit child
  1. Tap an existing child
  2. Edit screen shows pre-populated values
  3. Change name, save → returns to Profile, name updated
  4. Database reflects update

TEST 5 — Wallet history
  1. Tap "History" in wallet section
  2. List shows all transactions, grouped by date
  3. Filter pill "Top-ups" → shows only topup type
  4. Tap a transaction → detail sheet with all metadata

TEST 6 — Pre-booking flow
  1. Wallet has sufficient balance
  2. Tap "Pre-book a session" → /profile/pre-book
  3. Pick date+time+duration → "Hold this slot"
  4. RPC succeeds → confirmation screen
  5. Pre-booking visible in Profile activity

TEST 7 — Theme switching
  1. Settings → Theme → Dark → all screens reflow
  2. Sign out, sign back in → theme preference persisted

TEST 8 — Notifications settings
  1. Toggle "Marketing & offers" off
  2. families.notification_preferences updated in DB
  3. Future marketing notifications skipped server-side

TEST 9 — Help screen
  1. Tap each FAQ section → expands inline
  2. Tap "Report an issue" → WhatsApp opens with context

TEST 10 — Sign out
  1. Tap Sign out → confirmation dialog
  2. Confirm → routes to /auth/phone
  3. Local storage cleared

TEST 11 — Delete account (full flow)
  1. Tap "Delete account" → /profile/delete-account
  2. Read warning, see wallet balance (if any)
  3. Type "delete" (lowercase) → button stays disabled
  4. Type "DELETE" → button enabled
  5. Tap → family_anonymise RPC fires
  6. Database: families.is_anonymised = true, name='Deleted User', child names removed, wallet_transactions preserved
  7. Routes to /farewell
  8. Tap "Back to start" → /auth/phone
  9. Try to sign in with same phone → new account flow (fresh)
```

---

## 13. Open Items for Founder

- [ ] Confirm referral copy: "₹100 / ₹200" credit amounts (already in venue_config but worth re-checking)
- [ ] WhatsApp support number (still placeholder `+919XXXXXXXXX` from previous sessions)
- [ ] FAQ content — write actual answers for v1 (need ~30 questions answered)
- [ ] Confirm soft-delete vs hard-delete for child removal (currently spec says soft-archive)
- [ ] Decide if "Talk to us on WhatsApp" should pre-fill a context message (recommended yes)
- [ ] Marketing email opt-in copy: "tips and offers" wording — wordsmith?

---

## What's NOT in this session

- Adventure tab (Session 8)
- Hero Recap card / reflection (Session 6)
- Order placement (Session 7)
- Birthday booking (Session 9)
- Order detail with full invoice download (Edge Function in Session 13 generates PDF)
