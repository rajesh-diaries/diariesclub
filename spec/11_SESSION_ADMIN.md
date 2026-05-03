# Session 11 — Admin Web

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-10 + 5b complete.

---

## Session Header

```
I am building Diaries Club. The customer app and staff app are spec'd.
This session: build the admin web app — Flutter web flavor, desktop-first,
sidebar navigation, used by founder + ops team to run the venue.

Locked decisions:
  - Same Flutter codebase, web flavor (admin_dev, admin_prod)
  - Sidebar layout, desktop-first (1280px min)
  - All admin actions go through service_role via Edge Functions OR
    SECURITY DEFINER RPCs with admin role check
  - Read-only impersonation supported for debugging
  - 2-person approval for wallet debits ENABLED but with single-admin fallback
    (founder operates solo for v1)

Estimated time: 6-7 hours
What to build:
  - Admin web flavor build target (lib/main_admin_dev.dart, lib/main_admin_prod.dart)
  - Admin auth (separate from customer auth — uses email + password + 2FA placeholder)
  - Sidebar navigation shell
  - 13 admin sections:
    1. Live Ops dashboard
    2. Birthday CRM (the heart of operations)
    3. Refunds queue
    4. Customers
    5. Workshops
    6. Catalog (menu items, combos, packages)
    7. Config (venue_config editor)
    8. Content (FAQ, reflection moments, hero cards)
    9. Users (staff PIN management, tablet provisioning)
    10. Reports (revenue, sessions, retention)
    11. Reactivation (CSV import + SMS blast)
    12. System Health
    13. Audit Log

What NOT to build:
  - Customer-facing screens (already done)
  - Staff app (already done)
  - Edge Functions called by admin (Session 13)

Output expected:
  - Admin web build deployable to a web host (Vercel/Netlify/Cloudflare Pages)
  - All sections functional or with detailed stubs
  - All actions write audit_log entries with admin actor_id

Acceptance:
  - Admin signs in with email/password
  - Sidebar shows 13 sections, navigation works
  - Live Ops dashboard shows current active sessions, today's revenue, pending refunds
  - Birthday CRM shows all reservations grouped by status; can transition between states
  - Reactivation: upload CSV → preview → blast SMS via MSG91
  - System health dashboard shows real-time metrics
```

---

## 1. Admin Web Flavor Setup

### 1.1 Add admin flavors

```dart
enum Flavor { dev, staging, prod, staffDev, staffProd, adminDev, adminProd }

class FlavorConfig {
  // ... existing fields
  final bool isAdmin;

  bool get isAdminDev => flavor == Flavor.adminDev;
  bool get isAdminProd => flavor == Flavor.adminProd;
  bool get isAdmin => isAdminDev || isAdminProd;
}
```

### 1.2 Entry points

```dart
// lib/main_admin_dev.dart
void main() async {
  F = FlavorConfig(
    flavor: Flavor.adminDev,
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    razorpayKeyId: '', // not used
    sentryDsn: const String.fromEnvironment('SENTRY_DSN_ADMIN'),
    branchKey: '',
    sentryEnabled: false,
    isStaffApp: false,
    isAdmin: true,
  );
  await bootstrap();
}
```

### 1.3 App entry routing

```dart
class DiariesClubApp extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    if (F.isAdmin) return const AdminApp();
    if (F.isStaff) return const StaffApp();
    return const CustomerApp();
  }
}
```

### 1.4 Build commands

```bash
flutter build web --flavor adminProd \
  -t lib/main_admin_prod.dart \
  --dart-define-from-file=env/admin_prod.json \
  --release \
  --web-renderer canvaskit

# Deploy to Vercel/Netlify/Cloudflare Pages
```

---

## 2. Admin Authentication

### 2.1 Schema: admin_users

Admins have separate authentication from customers. Use Supabase Auth with email+password.

```sql
-- Migration: 0006_admin_users.sql

CREATE TABLE IF NOT EXISTS admin_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID UNIQUE NOT NULL,        -- Supabase auth.users.id
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
  is_active BOOLEAN DEFAULT true,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Helper: is_admin() function for RLS / RPCs
CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
  SELECT EXISTS(
    SELECT 1 FROM admin_users
    WHERE auth_user_id = auth.uid() AND is_active = true
  )
$$;

-- Seed first admin (founder)
-- Manually after first signup: INSERT INTO admin_users (auth_user_id, name, email, role)
-- VALUES ('<your-auth-uid>', 'Founder', 'you@diariesclub.com', 'super_admin');
```

### 2.2 Login screen

```
┌─────────────────────────────────────┐
│ FULL SCREEN, CENTERED               │
│                                     │
│   [Diaries Logo]                    │
│   Admin Console                     │
│                                     │
│   Email                             │
│   ┌──────────────────────┐          │
│   │ admin@diariesclub.com│          │
│   └──────────────────────┘          │
│                                     │
│   Password                          │
│   ┌──────────────────────┐          │
│   │ ••••••••             │          │
│   └──────────────────────┘          │
│                                     │
│   [Sign in]                         │
│                                     │
│   Forgot password?                  │
└─────────────────────────────────────┘
```

```dart
Future<void> _signIn() async {
  setState(() => _isLoading = true);
  try {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    // Verify admin role
    final adminCheck = await Supabase.instance.client
      .from('admin_users')
      .select()
      .eq('auth_user_id', response.user!.id)
      .eq('is_active', true)
      .maybeSingle();

    if (adminCheck == null) {
      await Supabase.instance.client.auth.signOut();
      throw 'not_admin';
    }

    // Update last_login_at
    await Supabase.instance.client
      .from('admin_users')
      .update({'last_login_at': DateTime.now().toIso8601String()})
      .eq('auth_user_id', response.user!.id);

    if (mounted) context.go('/admin/live-ops');
  } catch (e) {
    setState(() {
      _errorText = e == 'not_admin'
        ? 'Not authorised'
        : 'Invalid credentials';
      _isLoading = false;
    });
  }
}
```

---

## 3. Sidebar Layout

### 3.1 Layout

```
┌─────┬─────────────────────────────────────┐
│LOGO │ APP BAR                             │
│     │ Section Title           [user] [≡]  │
├─────┼─────────────────────────────────────┤
│  📊 │                                     │
│Live │                                     │
│ Ops │                                     │
│     │                                     │
│  🎂 │                                     │
│Bday │       MAIN CONTENT AREA             │
│ CRM │                                     │
│     │                                     │
│  ↺  │                                     │
│Refund                                     │
│     │                                     │
│  👥 │                                     │
│Cust.│                                     │
│     │                                     │
│  🎓 │                                     │
│Workshp                                    │
│     │                                     │
│  📋 │                                     │
│Catlg│                                     │
│     │                                     │
│  ⚙  │                                     │
│Config                                     │
│     │                                     │
│  📝 │                                     │
│Content                                    │
│     │                                     │
│  🔑 │                                     │
│Users│                                     │
│     │                                     │
│  📈 │                                     │
│Reprts                                     │
│     │                                     │
│  📨 │                                     │
│Reactv                                     │
│     │                                     │
│  💚 │                                     │
│Health                                     │
│     │                                     │
│  📜 │                                     │
│Audit│                                     │
└─────┴─────────────────────────────────────┘
```

### 3.2 Implementation

```dart
class AdminShell extends ConsumerWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Scaffold(
      body: Row(
        children: [
          AdminSidebar(),
          Expanded(
            child: Column(
              children: [
                AdminAppBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminSidebar extends ConsumerWidget {
  static const sections = [
    _NavSection('/admin/live-ops', 'Live Ops', 'pulse'),
    _NavSection('/admin/birthdays', 'Birthday CRM', 'cake'),
    _NavSection('/admin/refunds', 'Refunds', 'arrowUUpLeft'),
    _NavSection('/admin/customers', 'Customers', 'users'),
    _NavSection('/admin/workshops', 'Workshops', 'graduationCap'),
    _NavSection('/admin/catalog', 'Catalog', 'storefront'),
    _NavSection('/admin/config', 'Config', 'gear'),
    _NavSection('/admin/content', 'Content', 'fileText'),
    _NavSection('/admin/users', 'Users', 'key'),
    _NavSection('/admin/reports', 'Reports', 'chartBar'),
    _NavSection('/admin/reactivation', 'Reactivation', 'envelope'),
    _NavSection('/admin/health', 'System Health', 'heartbeat'),
    _NavSection('/admin/audit', 'Audit Log', 'scroll'),
  ];

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final currentRoute = GoRouterState.of(c).matchedLocation;

    return Container(
      width: 220,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo + brand
          Padding(
            padding: const EdgeInsets.all(20),
            child: Image.asset('assets/images/logo_white.png', height: 32),
          ),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 8),

          // Sections
          Expanded(
            child: ListView(
              children: sections.map((s) => _NavItem(
                section: s,
                isActive: currentRoute.startsWith(s.route),
              )).toList(),
            ),
          ),

          // User pill bottom
          const Divider(color: Colors.white24, height: 1),
          AdminUserPill(),
        ],
      ),
    );
  }
}
```

---

## 4. Section 1 — Live Ops Dashboard

### 4.1 Layout

```
┌─────────────────────────────────────────────┐
│ Live Ops                                    │
├─────────────────────────────────────────────┤
│ TOP STATS (4-card row)                      │
│ ┌────┬────┬────┬────┐                       │
│ │ 5  │ 12 │ 3  │₹4,250│                     │
│ │Act.│Tdy │Pend│Today │                     │
│ │Sess│Sess│Refds Cash │                     │
│ └────┴────┴────┴────┘                       │
├─────────────────────────────────────────────┤
│ ACTIVE SESSIONS (real-time table)           │
│ ┌─────┬──────┬────────┬──────┬────────┐     │
│ │Child│Family│Started │Remain│Actions │     │
│ ├─────┼──────┼────────┼──────┼────────┤     │
│ │Aarav│Sharma│4:32 PM │1:23  │Force...│     │
│ └─────┴──────┴────────┴──────┴────────┘     │
├─────────────────────────────────────────────┤
│ INCOMING (today's pipeline)                 │
│ • 3 sessions waiting to start                │
│ • 2 birthday inquiries to respond            │
│ • 1 refund pending approval                  │
└─────────────────────────────────────────────┘
```

### 4.2 Real-time data

Same data sources as customer/staff apps but unfiltered (admin sees all):

```dart
@riverpod
Stream<LiveOpsSnapshot> liveOpsSnapshot(LiveOpsSnapshotRef ref) async* {
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    final supabase = Supabase.instance.client;

    final activeSessions = await supabase
      .from('sessions')
      .select('*, family:families(name), child:children(name)')
      .inFilter('status', ['active', 'grace']);

    final todaySessions = await supabase
      .from('sessions')
      .select('id', const FetchOptions(count: CountOption.exact))
      .gte('created_at', DateTime.now().toIso8601String().substring(0, 10));

    final pendingRefunds = await supabase
      .from('refunds')
      .select('id', const FetchOptions(count: CountOption.exact))
      .eq('status', 'pending');

    final todayCash = await supabase
      .from('wallet_transactions')
      .select('amount_paise')
      .eq('payment_method', 'cash')
      .gte('created_at', DateTime.now().toIso8601String().substring(0, 10));
    final cashSum = (todayCash as List).fold<int>(0, (s, t) => s + ((t['amount_paise'] as int) * -1).abs());

    yield LiveOpsSnapshot(
      activeSessions: (activeSessions as List).map((r) => Session.fromJson(r)).toList(),
      todaySessionsCount: todaySessions.count ?? 0,
      pendingRefundsCount: pendingRefunds.count ?? 0,
      todayCashPaise: cashSum,
    );
  }
}
```

---

## 5. Section 2 — Birthday CRM (the heart of operations)

This is the most important admin screen because birthdays = primary revenue. The whole reservation pipeline is managed here.

### 5.1 Layout

```
┌─────────────────────────────────────────────┐
│ Birthday CRM             [+ New manual]     │
├─────────────────────────────────────────────┤
│ FILTER BAR                                  │
│ Status: [All▼] Date: [Next 30 days▼]        │
│ Search: [phone or name]                     │
├─────────────────────────────────────────────┤
│ KANBAN BOARD (4 columns, scrollable cols)   │
│ ┌──────────┬──────────┬──────────┬──────────┐│
│ │INTERESTED│CONTACTED │CONFIRMED │COMPLETED │ │
│ │   (3)    │   (2)    │   (5)    │   (1)    │ │
│ ├──────────┼──────────┼──────────┼──────────┤│
│ │┌────────┐│┌────────┐│┌────────┐│┌────────┐ │
│ ││Aarav   │││Riya    │││Krish   │││Tanya   │ │
│ ││Hero Adv│││Legend  │││Basics  │││Hero Adv│ │
│ ││₹25,000 │││₹45,000 │││₹15,000 │││₹25,000 │ │
│ ││Apr 12  │││May 5   │││Mar 30  │││Mar 15  │ │
│ ││+91 987.│││+91 988.│││+91 999.│││+91 911.│ │
│ ││[Contact│││[Confirm│││[Mark   │││[Album  │ │
│ │ via WA]│││]       │││completd│││publish]│ │
│ │└────────┘│└────────┘│└────────┘│└────────┘ │
│ └──────────┴──────────┴──────────┴──────────┘│
└─────────────────────────────────────────────┘
```

### 5.2 Card detail (click for sidebar drawer)

When admin clicks a card, opens a right-side drawer with full reservation info + actions.

```dart
class BirthdayDetailDrawer extends ConsumerWidget {
  final String reservationId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final reservation = ref.watch(reservationByIdProvider(reservationId));

    return reservation.when(
      data: (r) => Container(
        width: 480,
        color: Theme.of(c).cardColor,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text("${_packageName(r)} — ${_familyName(r)}",
                style: AppTextStyles.h2(c)),
              const SizedBox(height: 8),
              _StatusBadge(status: r.status),
              const SizedBox(height: 24),

              // Family contact
              _Section(title: "Contact", children: [
                _DetailRow(label: "Family", value: _familyName(r)),
                _DetailRow(label: "Phone", value: PhoneNormalizer.forDisplay(_familyPhone(r))),
                _ActionButton(
                  icon: PhosphorIcons.whatsappLogo(),
                  label: "Send WhatsApp",
                  onPressed: () => _sendWhatsApp(_familyPhone(r), r),
                ),
                _ActionButton(
                  icon: PhosphorIcons.phoneCall(),
                  label: "Call",
                  onPressed: () => _call(_familyPhone(r)),
                ),
              ]),

              // Child details
              _Section(title: "Child", children: [
                _DetailRow(label: "Name", value: _childName(r)),
                _DetailRow(label: "Age", value: _childAge(r)),
                _DetailRow(label: "Birthday", value: _formatDate(_childDob(r))),
              ]),

              // Booking details
              _Section(title: "Booking", children: [
                _DetailRow(label: "Package", value: _packageName(r)),
                _DetailRow(label: "Price", value: Money.fromPaise(r.packagePricePaise)),
                _DetailRow(label: "Preferred when", value: r.preferredMonth ?? '—'),
                _DetailRow(label: "Window", value: r.preferredWindow ?? '—'),
                _DetailRow(label: "Kids", value: '${r.numKids}'),
                _DetailRow(label: "Adults", value: '${r.numAdults}'),
                if (r.specialRequests?.isNotEmpty ?? false)
                  _DetailRow(label: "Special", value: r.specialRequests!),
                if (r.slotDate != null) ...[
                  _DetailRow(label: "Confirmed date", value: _formatDate(r.slotDate!)),
                  _DetailRow(label: "Time", value: r.slotStartTime?.toString() ?? '—'),
                ],
              ]),

              // Money
              _Section(title: "Money", children: [
                _DetailRow(label: "Package price", value: Money.fromPaise(r.packagePricePaise)),
                _DetailRow(label: "Deposit collected (offline)",
                  value: r.depositPaidPaise > 0 ? Money.fromPaise(r.depositPaidPaise) : '—'),
                _DetailRow(label: "Balance due", value: Money.fromPaise(r.balancePaise)),
              ]),

              // Status transitions (action bar at bottom)
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              _StatusActionBar(reservation: r),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text("Error loading")),
    );
  }
}

class _StatusActionBar extends ConsumerWidget {
  final BirthdayReservation reservation;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (reservation.status) {
        'interested' => [
          PrimaryButton(label: "Mark contacted", onPressed: () => _transition(c, ref, 'admin_contacted')),
          const SizedBox(height: 8),
          OutlinedButton(child: const Text("Cancel"), onPressed: () => _cancel(c, ref)),
        ],
        'admin_contacted' => [
          PrimaryButton(label: "Confirm date", onPressed: () => _confirmDateDialog(c, ref)),
          const SizedBox(height: 8),
          OutlinedButton(child: const Text("Cancel"), onPressed: () => _cancel(c, ref)),
        ],
        'confirmed' => [
          PrimaryButton(label: "Mark completed (auto-award card)",
            onPressed: () => _markCompleted(c, ref)),
          const SizedBox(height: 8),
          OutlinedButton(child: const Text("No-show"), onPressed: () => _markNoShow(c, ref)),
        ],
        'completed' => [
          if (reservation.albumReadyAt == null)
            PrimaryButton(label: "Upload photos & publish album",
              onPressed: () => _openPhotoUpload(c, ref))
          else
            const Text("Album published ✓", style: TextStyle(color: AppColors.activeGreen)),
        ],
        _ => [const Text("No actions available")],
      },
    );
  }
}
```

### 5.3 Confirm date dialog

When admin moves from `admin_contacted → confirmed`, prompts for date+time:

```dart
Future<void> _confirmDateDialog(BuildContext c, WidgetRef ref) async {
  final result = await showDialog<({DateTime date, TimeOfDay time, int depositPaise})>(
    context: c,
    builder: (_) => _ConfirmDateForm(),
  );
  if (result == null) return;

  // Update reservation
  await Supabase.instance.client.from('birthday_reservations').update({
    'status': 'confirmed',
    'slot_date': result.date.toIso8601String().substring(0, 10),
    'slot_start_time': '${result.time.hour}:${result.time.minute.toString().padLeft(2, '0')}:00',
    'deposit_paid_paise': result.depositPaise,
    'admin_confirmed_at': DateTime.now().toIso8601String(),
  }).eq('id', reservation.id);

  // Audit
  await Supabase.instance.client.from('audit_log').insert({
    'actor_type': 'admin',
    'action': 'birthday.confirm',
    'entity_type': 'birthday_reservation',
    'entity_id': reservation.id,
    'new_value': {'date': result.date.toIso8601String(), 'deposit': result.depositPaise},
  });

  // Push to family
  await Supabase.instance.client.from('notifications').insert({
    'family_id': reservation.familyId,
    'type': 'birthday_d_minus_30',
    'title': "You're confirmed! 🎉",
    'body': "Your party is set for ${_formatDate(result.date)} at ${result.time.format(c)}.",
    'deep_link': '/birthday/status/${reservation.id}',
    'reference_id': reservation.id,
  });
}
```

### 5.4 Photo upload + publish

When admin moves to `completed` and album is ready:

```dart
Future<void> _openPhotoUpload(BuildContext c, WidgetRef ref) async {
  // Open dialog for multi-file picker
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.image,
  );
  if (result == null || result.files.isEmpty) return;

  // Upload each to Supabase Storage
  for (final file in result.files) {
    final bytes = file.bytes!;
    final compressed = await PhotoCompressService.compress(bytes);

    final path = 'birthday_albums/${reservation.id}/${file.name}';
    await Supabase.instance.client.storage
      .from('birthday-photos')
      .uploadBinary(path, compressed,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));

    final publicUrl = Supabase.instance.client.storage
      .from('birthday-photos')
      .getPublicUrl(path);

    // Insert birthday_party_photos row
    await Supabase.instance.client.from('birthday_party_photos').insert({
      'reservation_id': reservation.id,
      'photo_url': publicUrl,
      'uploaded_by_admin': Supabase.instance.client.auth.currentUser!.id,
    });
  }

  // Publish album
  await Supabase.instance.client.rpc('birthday_album_publish', params: {
    'p_reservation_id': reservation.id,
    'p_admin_id': Supabase.instance.client.auth.currentUser!.id,
  });
}
```

---

## 6. Section 3 — Refunds Queue

```
┌─────────────────────────────────────────────┐
│ Refunds                                     │
├─────────────────────────────────────────────┤
│ TABS: Pending(3) | Approved | Completed | All│
├─────────────────────────────────────────────┤
│ TABLE                                       │
│ ┌────┬─────┬─────────┬──────┬──────┬──────┐ │
│ │Date│Family│Reason  │Amount│Init. │Action│ │
│ ├────┼─────┼─────────┼──────┼──────┼──────┤ │
│ │Mar30│Sharma│Wrong order│₹800│Staff│Approve│
│ │     │      │            │     │     │Reject│ │
│ └────┴─────┴─────────┴──────┴──────┴──────┘ │
└─────────────────────────────────────────────┘
```

### 6.1 Approve / reject actions

```dart
Future<void> _approve(Refund refund) async {
  // 2-person approval check (per venue_config flag)
  final config = await ref.read(venueConfigProvider.future);
  if (config.requireTwoPersonForDebit) {
    // For v1 with single admin: skip; later add second-admin approval flow
  }

  await Supabase.instance.client.rpc('refund_approve', params: {
    'p_refund_id': refund.id,
    'p_approver_id': Supabase.instance.client.auth.currentUser!.id,
  });
}

Future<void> _reject(Refund refund, String reason) async {
  await Supabase.instance.client
    .from('refunds')
    .update({
      'status': 'rejected',
      'rejection_reason': reason,
      'approved_by': Supabase.instance.client.auth.currentUser!.id,
      'approved_at': DateTime.now().toIso8601String(),
    })
    .eq('id', refund.id);
}
```

### 6.2 New RPC: `refund_approve`

```sql
CREATE OR REPLACE FUNCTION refund_approve(
  p_refund_id UUID,
  p_approver_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_refund refunds%ROWTYPE;
  v_wallet wallets%ROWTYPE;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  SELECT * INTO v_refund FROM refunds WHERE id = p_refund_id FOR UPDATE;
  IF v_refund.status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_refund_state';
  END IF;

  -- Wallet path: credit immediately
  IF v_refund.destination = 'wallet' THEN
    UPDATE wallets SET balance_paise = balance_paise + v_refund.amount_paise, updated_at = now()
      WHERE family_id = v_refund.family_id RETURNING * INTO v_wallet;

    INSERT INTO wallet_transactions(
      family_id, type, amount_paise, balance_after_paise,
      payment_method, reference_id, reference_type
    ) VALUES (
      v_refund.family_id, 'refund', v_refund.amount_paise, v_wallet.balance_paise,
      'system', v_refund.id, 'refund'
    );

    UPDATE refunds SET
      status = 'completed',
      approved_by = p_approver_id,
      approved_at = now()
    WHERE id = p_refund_id;
  ELSE
    -- Razorpay path: mark approved, Edge Function processes refund
    UPDATE refunds SET
      status = 'approved',
      approved_by = p_approver_id,
      approved_at = now()
    WHERE id = p_refund_id;
  END IF;

  -- Notify family
  INSERT INTO notifications(family_id, type, title, body, deep_link)
  VALUES (
    v_refund.family_id, 'refund_processed',
    Money(v_refund.amount_paise) || ' refund approved',
    'Reason: ' || v_refund.reason,
    '/profile/wallet-history'
  );

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, new_value)
  VALUES (p_approver_id, 'admin', 'refund.approve', 'refund', p_refund_id,
          jsonb_build_object('amount', v_refund.amount_paise));

  RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION refund_approve TO authenticated, service_role;
```

---

## 7. Section 4 — Customers

### 7.1 Layout

```
┌─────────────────────────────────────────────┐
│ Customers                                   │
├─────────────────────────────────────────────┤
│ SEARCH BAR                                  │
│ [Search by phone, name, or child name]      │
├─────────────────────────────────────────────┤
│ FILTERS                                     │
│ ☐ Active ☐ Cafe-only ☐ Has children         │
│ Last visit: [All▼]                          │
├─────────────────────────────────────────────┤
│ TABLE                                       │
│ ┌──────┬──────┬──────┬──────┬──────────────┐│
│ │Phone │Name  │Kids  │Wallet│Last visit    ││
│ ├──────┼──────┼──────┼──────┼──────────────┤│
│ │+91...│Sharma│Aarav │₹1,250│2 days ago    ││
│ │      │      │+1    │      │              ││
│ │      │      │      │      │[Open]        ││
│ └──────┴──────┴──────┴──────┴──────────────┘│
└─────────────────────────────────────────────┘
```

### 7.2 Customer detail page

Click row → `/admin/customers/:id` with comprehensive view:

- Family details (editable)
- All children with hero progress
- Wallet transaction history (with admin manual adjust button)
- All sessions
- All orders
- All refunds
- All birthday reservations
- Workshop registrations
- Audit trail (this customer's events)
- **Read-only impersonation** button (opens customer view in new tab — see below)

### 7.3 Read-only impersonation

For debugging customer issues without changing anything.

```dart
Future<void> _impersonate(Family family) async {
  // Create a short-lived JWT for read-only customer view
  final token = await Supabase.instance.client.functions.invoke(
    'admin-impersonate-token',
    body: {'family_id': family.id, 'mode': 'readonly'},
  );

  // Open customer app in new tab with the token in URL hash
  // Customer app on detecting this token enters "readonly mode" — UI banner shown,
  // all actions disabled
  final url = '${F.customerAppUrl}/?impersonate_token=${token.data['token']}';
  await launchUrl(Uri.parse(url));

  // Audit
  await Supabase.instance.client.from('audit_log').insert({
    'actor_type': 'admin',
    'action': 'admin.impersonate',
    'entity_type': 'family',
    'entity_id': family.id,
  });
}
```

The Edge Function `admin-impersonate-token` (Session 13) generates a custom JWT signed with `service_role` that includes `is_impersonation: true`. The customer app, on detecting this, shows a yellow banner "VIEW MODE — admin impersonating" and disables all mutating actions.

### 7.4 Manual wallet adjust

```dart
Future<void> _manualAdjust(Family family) async {
  final adjustment = await showDialog<({int amountPaise, String reason})>(
    context: c,
    builder: (_) => _ManualAdjustDialog(),
  );
  if (adjustment == null) return;

  // 2-person approval for debits (per venue_config)
  final isDebit = adjustment.amountPaise < 0;
  final config = await ref.read(venueConfigProvider.future);

  if (isDebit && config.requireTwoPersonForDebit) {
    final secondApprover = await _request2ndApprover();
    if (secondApprover == null) return;
  }

  await Supabase.instance.client.rpc('manual_wallet_adjust', params: {
    'p_family_id': family.id,
    'p_amount_paise': adjustment.amountPaise,
    'p_reason': adjustment.reason,
    'p_admin_id': Supabase.instance.client.auth.currentUser!.id,
  });
}
```

---

## 8. Section 5 — Workshops

### 8.1 Layout

```
┌─────────────────────────────────────────────┐
│ Workshops             [+ Schedule new]      │
├─────────────────────────────────────────────┤
│ TABS: Upcoming | Past | Cancelled           │
├─────────────────────────────────────────────┤
│ TABLE / CARDS                               │
│ ┌───────────────────────────────────────┐   │
│ │ Sat Mar 30, 4 PM     [Curious]        │   │
│ │ Mini Scientists                       │   │
│ │ Ages 5-9 · 90 min · ₹500              │   │
│ │ 5 of 8 spots filled                   │   │
│ │ [View registrations] [Edit] [Cancel]  │   │
│ └───────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 8.2 Schedule new workshop

Form dialog:
- Title, description, cover image URL
- Date + time + duration
- Age min, age max
- Capacity
- Price
- Primary trait (which hero earns the XP)
- XP award amount

On submit → INSERT into `workshops` table. Customer app sees it within ~5s via Realtime.

### 8.3 View registrations

Modal listing registered families + children. Admin can mark attended (calls `workshop_attend` RPC which awards XP).

---

## 9. Section 6 — Catalog

Sub-navigation within section: **Menu items | Combos | Birthday packages**

### 9.1 Menu items

Same UX as staff app's menu availability toggle, but with full CRUD:
- Add/edit menu item (name, description, price, image, category, brand, sort_order, allergens)
- Delete (soft-delete by setting is_available=false; full delete with confirm)
- Bulk import via CSV

### 9.2 Combos

CRUD for `combos` table:
- Name, description, cover image
- Price (admin enters; this is the bundle price)
- Inclusions (JSON editor or structured form)
- Active toggle

### 9.3 Birthday packages

CRUD for `birthday_packages`:
- Name, tier, description, gallery images
- Price (paise), max kids, max adults, duration
- Inclusions (JSON)
- Hero theme
- Deposit amount (used for display only since it's collected offline)
- "Most Booked" / "Premium" badge flag (manual)
- Active toggle

---

## 10. Section 7 — Config

Edit `venue_config` row. Sectioned form:

### 10.1 Sections

```
PRICING
  - 1hr session price
  - 2hr session price
  - Extension per hour

SESSION RULES
  - Grace period (minutes)
  - Grace max (minutes)
  - Extend nudge after (minutes)
  - QR validity (minutes)

LOYALTY
  - Cashback percent
  - Reflection window (hours)

XP DEFAULTS
  - All XP amounts...

REFERRALS
  - Gifter credit (paise)
  - New family credit
  - Monthly cap

WALLET
  - Low balance threshold
  - Reactivation credit
  - Reactivation expiry days
  - Top-up offers (JSON edit, structured)

VISIT MILESTONES
  - JSON edit, list of {visits, reward_paise, reward_xp}

PRE-BOOKING
  - Hold percent
  - Grace minutes

APP VERSION CONTROL (per platform)
  - iOS min supported, latest
  - Android min supported, latest

WALL OF LEGENDS
  - Enabled toggle
  - Anonymise toggle

POLICIES
  - Two-person approval for debits (toggle)
```

### 10.2 Save

```dart
Future<void> _save(Map<String, dynamic> updates) async {
  await Supabase.instance.client
    .from('venue_config')
    .update(updates)
    .eq('venue_id', _venueId);

  // Audit
  await Supabase.instance.client.from('audit_log').insert({
    'actor_type': 'admin',
    'action': 'config.update',
    'entity_type': 'venue_config',
    'entity_id': _venueId,
    'new_value': updates,
  });

  // Customer apps reading from venue_config provider get updates within ~5s
}
```

---

## 11. Section 8 — Content

### 11.1 FAQ editor

CRUD for FAQ entries. Schema addition:

```sql
CREATE TABLE IF NOT EXISTS faq_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category TEXT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

Customer Help screen pulls from this table (Session 5b had it hardcoded; this makes it editable).

### 11.2 Reflection moments

CRUD for `reflection_moments` (the 24 cards). Edit display text, icon, weight. Add new.

### 11.3 Hero card definitions

CRUD for `hero_card_definitions`. Upload card image to Storage. Set rarity, hero, birthday-exclusive flag.

---

## 12. Section 9 — Users

### 12.1 Staff PIN management

```
┌─────────────────────────────────────────────┐
│ Staff               [+ Add staff]           │
├─────────────────────────────────────────────┤
│ TABLE                                       │
│ Name      Phone   Role          Last used   │
│ Priya     +91...  staff         5 min ago   │
│ Ravi      +91...  venue_manager 1h ago      │
│ ...                                         │
│ Actions: [Reset PIN] [Deactivate]           │
└─────────────────────────────────────────────┘
```

### 12.2 Add staff

Form: name, phone, role, set initial PIN.

```dart
Future<void> _addStaff(StaffFormData data) async {
  await Supabase.instance.client.rpc('admin_create_staff', params: {
    'p_venue_id': _venueId,
    'p_name': data.name,
    'p_phone': data.phone,
    'p_role': data.role,
    'p_pin': data.pin,
  });
}
```

```sql
CREATE OR REPLACE FUNCTION admin_create_staff(
  p_venue_id UUID,
  p_name TEXT, p_phone TEXT, p_role TEXT, p_pin TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'not_authorised'; END IF;

  INSERT INTO staff (venue_id, name, phone, role, pin_hash)
  VALUES (p_venue_id, p_name, p_phone, p_role, crypt(p_pin, gen_salt('bf')));

  RETURN jsonb_build_object('success', true);
END $$;
```

### 12.3 Reset PIN

Generates a new PIN, shows it once to admin (then hashed). Admin shares with staff via secure channel.

### 12.4 Tablet provisioning

Add new tablet device:
- Device label
- Generates a tablet auth user automatically (admin gets credentials shown once)

### 12.5 Admin users

CRUD for `admin_users` (super_admin only).

---

## 13. Section 10 — Reports

Read-only dashboards. Per-section:

### 13.1 Revenue

- Today, this week, this month, all-time
- Breakdown: sessions, orders, workshops, birthdays
- Cash vs wallet vs Razorpay
- Refunds total
- Chart: daily revenue over last 30 days

### 13.2 Sessions

- Total per period
- Average duration
- Wallet vs cash split
- Most popular time slots (heatmap)
- Repeat rate (% of families with 2+ sessions)

### 13.3 Retention

- Cohort analysis: families joined in week X, % still active in weeks X+1, X+2, ...
- Churn definition: no session in last 60 days

### 13.4 Birthday funnel

- Discovery → interest submitted → contacted → confirmed → completed conversion rates
- Average time from interest to confirmed
- Average package value
- Completion rate

### 13.5 XP / hero engagement

- Reflections submitted % vs auto-split %
- Stage transition rate per child
- Most-tapped reflection moments
- Hero card draw outcomes (rare vs common ratio sanity check)

Export each report as CSV.

---

## 14. Section 11 — Reactivation

The one-time blast to your ~2,000 paper-book contacts.

### 14.1 Layout

```
┌─────────────────────────────────────────────┐
│ Reactivation Campaign                       │
├─────────────────────────────────────────────┤
│ STEP 1: IMPORT                              │
│ Upload CSV (phone, name, last_visit, count) │
│ [Choose file]                               │
│ Preview: 1,847 valid rows                   │
│ Skipped: 153 (invalid phone format)         │
│ [Import to staging]                         │
├─────────────────────────────────────────────┤
│ STEP 2: REVIEW                              │
│ ✓ 1,847 contacts in staging                 │
│ ✓ All phones E.164 normalised               │
│ ✓ 200 dupes against existing families       │
│ Sample: [10 random rows shown]              │
├─────────────────────────────────────────────┤
│ STEP 3: SET UP CAMPAIGN                     │
│ Welcome credit: ₹200 (from venue_config)    │
│ Expiry: 90 days                             │
│ SMS template (DLT-approved):                │
│ "Hi! Diaries Club is back ☕. We've added   │
│ ₹200 to your account. Open app to claim:    │
│ {{branch_link}}"                            │
├─────────────────────────────────────────────┤
│ STEP 4: BLAST                               │
│ ⚠ This will send 1,847 SMS messages.        │
│ Estimated cost: ₹333 (₹0.18 × 1,847)        │
│ [SEND ALL]      [Send to my phone first]    │
├─────────────────────────────────────────────┤
│ STEP 5: TRACK                               │
│ Sent: 1,847                                  │
│ Delivered: 1,723                             │
│ Failed: 124                                  │
│ Redeemed: 89 (4.8%)                         │
│ Last 24h chart:                             │
│ [bar chart of redemptions over time]        │
└─────────────────────────────────────────────┘
```

### 14.2 CSV import logic

```dart
Future<void> _importCsv(Uint8List bytes) async {
  final csvString = utf8.decode(bytes);
  final rows = const CsvToListConverter().convert(csvString);
  final headers = rows.first;

  int valid = 0, skipped = 0;
  final stagingRows = <Map<String, dynamic>>[];

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final phone = PhoneNormalizer.toE164(row[headers.indexOf('phone')].toString());
    if (phone == null) {
      skipped++;
      continue;
    }

    stagingRows.add({
      'phone': phone,
      'name': row[headers.indexOf('name')]?.toString(),
      'last_visit_date': _parseDate(row[headers.indexOf('last_visit')]),
      'visit_count': int.tryParse(row[headers.indexOf('count')].toString()) ?? 0,
      'credit_paise': 20000,  // default ₹200
      'credit_expires_at': DateTime.now().add(const Duration(days: 90)).toIso8601String(),
      'sms_status': 'pending',
    });
    valid++;
  }

  // Bulk insert
  await Supabase.instance.client.from('reactivation_contacts').insert(stagingRows);

  setState(() {
    _previewValid = valid;
    _previewSkipped = skipped;
  });
}
```

### 14.3 Send blast

Calls Edge Function `reactivation-blast` (Session 13) which iterates contacts and sends SMS via MSG91.

```dart
Future<void> _sendBlast() async {
  final confirmed = await showDialog<bool>(...);
  if (confirmed != true) return;

  await Supabase.instance.client.functions.invoke(
    'reactivation-blast',
    body: {'venue_id': _venueId},
  );

  // Track progress via reactivation_contacts.sms_status updates (Realtime)
}
```

### 14.4 Test mode

"Send to my phone first" button sends only to the admin's phone for verification before mass blast.

---

## 15. Section 12 — System Health

```
┌─────────────────────────────────────────────┐
│ System Health                               │
├─────────────────────────────────────────────┤
│ STATUS LIGHTS                               │
│ ● API: green (p95: 124ms)                   │
│ ● Database: green                           │
│ ● Edge Functions: green                     │
│ ● Razorpay reconciliation: yellow (last 22m │
│   old)                                      │
│ ● Push delivery rate: 96%                   │
├─────────────────────────────────────────────┤
│ METRICS (last 24h)                          │
│ Active families: 142                        │
│ Sessions started: 38                        │
│ Orders placed: 67                           │
│ Failed payments: 2                          │
│ Webhook delays > 5min: 0                    │
│ Sentry errors: 14 (8 unique)                │
├─────────────────────────────────────────────┤
│ RECONCILIATION LOG                          │
│ Last run: 2 min ago - Success - 0 mismatches│
│ Run history (last 24): [bar chart]          │
│ [Run reconciliation now]                    │
├─────────────────────────────────────────────┤
│ BACKUPS                                     │
│ Last automated: 4h ago - Success            │
│ Last manual download: 6 days ago            │
│ [Download latest backup]                    │
└─────────────────────────────────────────────┘
```

Data sources:
- `system_health_snapshots` table (populated by cron — Session 13)
- `reconciliation_log` table

---

## 16. Section 13 — Audit Log

Read-only with filters.

```
┌─────────────────────────────────────────────┐
│ Audit Log                                   │
├─────────────────────────────────────────────┤
│ FILTERS                                     │
│ Actor: [All▼]  Action: [All▼]               │
│ Date: [Last 7 days▼]                        │
│ Search: [entity ID]                         │
├─────────────────────────────────────────────┤
│ TABLE                                       │
│ Time    Actor    Action     Entity   Detail │
│ 2:30PM  Priya    sess.create session  Aarav │
│ 2:31PM  Priya    refund.iss refund   ₹400   │
│ 2:32PM  System   wallet.top family   ₹500   │
│ ...                                         │
└─────────────────────────────────────────────┘
```

Export to CSV. Click row → modal with full `old_value` / `new_value` JSON.

---

## 17. Files to Create

```
lib/
├── main_admin_dev.dart
├── main_admin_prod.dart
├── app_admin.dart
└── features/
    └── admin/
        ├── login_screen.dart
        ├── shell.dart
        ├── widgets/
        │   ├── admin_sidebar.dart
        │   ├── admin_app_bar.dart
        │   ├── admin_user_pill.dart
        │   ├── nav_item.dart
        │   ├── data_table_basic.dart
        │   ├── filter_bar.dart
        │   ├── stat_card.dart
        │   ├── status_badge.dart
        │   ├── detail_drawer.dart
        │   └── ...
        ├── live_ops/
        │   └── live_ops_screen.dart
        ├── birthday_crm/
        │   ├── birthday_crm_screen.dart
        │   ├── birthday_kanban.dart
        │   ├── birthday_card.dart
        │   ├── birthday_detail_drawer.dart
        │   ├── confirm_date_dialog.dart
        │   └── photo_uploader.dart
        ├── refunds/
        │   ├── refunds_queue_screen.dart
        │   └── refund_detail_drawer.dart
        ├── customers/
        │   ├── customers_list_screen.dart
        │   ├── customer_detail_screen.dart
        │   ├── manual_adjust_dialog.dart
        │   └── impersonate_button.dart
        ├── workshops/
        │   ├── workshops_screen.dart
        │   ├── workshop_form.dart
        │   └── registrations_modal.dart
        ├── catalog/
        │   ├── catalog_screen.dart
        │   ├── menu_items_tab.dart
        │   ├── combos_tab.dart
        │   └── packages_tab.dart
        ├── config/
        │   ├── config_screen.dart
        │   └── config_section.dart
        ├── content/
        │   ├── content_screen.dart
        │   ├── faq_editor.dart
        │   ├── reflection_moments_editor.dart
        │   └── hero_cards_editor.dart
        ├── users/
        │   ├── users_screen.dart
        │   ├── staff_form.dart
        │   ├── reset_pin_dialog.dart
        │   └── tablet_provision_dialog.dart
        ├── reports/
        │   ├── reports_screen.dart
        │   ├── revenue_report.dart
        │   ├── sessions_report.dart
        │   ├── retention_report.dart
        │   ├── birthday_funnel_report.dart
        │   └── xp_engagement_report.dart
        ├── reactivation/
        │   ├── reactivation_screen.dart
        │   ├── csv_uploader.dart
        │   ├── campaign_setup.dart
        │   └── tracking_dashboard.dart
        ├── health/
        │   └── system_health_screen.dart
        └── audit/
            └── audit_log_screen.dart
```

---

## 18. Acceptance Tests

```
TEST 1 — Admin login
  1. Open admin web URL
  2. Sign in with admin email + password
  3. Verify admin_users row exists for this auth_user_id
  4. Lands on Live Ops dashboard

TEST 2 — Live Ops real-time
  1. Open Live Ops in one window
  2. Customer in another window starts a session
  3. Within 30s, Live Ops active sessions count increments

TEST 3 — Birthday CRM transitions
  1. Customer submits birthday interest
  2. Admin Birthday CRM shows new card in INTERESTED column
  3. Admin clicks → drawer opens with details
  4. Click "Mark contacted" → moves to CONTACTED column
  5. Click "Confirm date" → dialog → enter date → CONFIRMED column
  6. Click "Mark completed" → birthday_reservation_complete RPC fires
  7. Hero card auto-awarded in customer's collection
  8. Customer notification sent

TEST 4 — Photo upload + album publish
  1. Reservation in completed state, no album yet
  2. Click "Upload photos & publish"
  3. Multi-select photos, upload
  4. Photos appear in birthday_party_photos table
  5. Click Publish → birthday_album_publish fires
  6. Customer notification: "Album is ready"
  7. Customer app can now view album

TEST 5 — Refund approval
  1. Staff issued ₹800 refund (>₹500 cap) → status='pending'
  2. Admin Refunds → see pending refund
  3. Click Approve → refund_approve fires
  4. Customer wallet credited
  5. Audit log entry created

TEST 6 — Customer search + impersonate
  1. Customers screen, search by phone
  2. Click row → customer detail
  3. Click "Impersonate (read-only)"
  4. New tab opens with customer view
  5. Yellow banner "VIEW MODE" visible
  6. All buttons disabled / no actions allowed
  7. Audit log captures impersonation event

TEST 7 — Manual wallet adjust
  1. Customer detail → click Manual adjust
  2. Add ₹100 with reason "Goodwill — broken cup"
  3. Wallet balance updated
  4. wallet_transactions row added (manual_credit type)
  5. Audit logged

TEST 8 — Schedule new workshop
  1. Workshops → Schedule new
  2. Form: title, date, capacity 8, age 5-9, ₹500, primary_trait=gerry
  3. Submit → workshops row created
  4. Customer Club tab → workshops tab → new workshop visible

TEST 9 — Catalog menu item add
  1. Catalog → Menu items → add new
  2. Fill form (name, price, brand=coffee, image, category)
  3. Save → menu_items row, customer Coffee tab updates

TEST 10 — Config edit
  1. Config → Pricing → change 1hr to ₹900
  2. Save
  3. Customer Session start screen reflects new price within ~5s

TEST 11 — Reactivation CSV import
  1. Reactivation → upload CSV with 1,847 rows
  2. Preview shows valid/skipped counts
  3. Import to staging → reactivation_contacts table populated
  4. Click "Send to my phone" → MSG91 sends to admin's phone only
  5. SMS received with Branch link

TEST 12 — Reactivation blast (TEST MODE first)
  1. With small test set (10 contacts)
  2. Click SEND ALL → reactivation-blast Edge Function fires
  3. SMS_status updates from pending → queued → dispatched
  4. Track dashboard updates in real time
  5. After delivery, redeemed count tracks via redemption flow

TEST 13 — System health
  1. Open System Health
  2. All status lights green or yellow with explanations
  3. Reconciliation log shows recent runs
  4. Click "Run reconciliation now" → fires razorpay-reconcile Edge Function
  5. Updates status

TEST 14 — Audit log filtering
  1. Audit log screen
  2. Filter by Actor: Priya → only Priya's actions
  3. Filter by Action: refund.* → only refund actions
  4. Click row → modal with full JSON

TEST 15 — Admin role enforcement
  1. Try to call any admin RPC without admin_users row
  2. RPC raises 'not_authorised'
  3. Confirm RLS / function checks block non-admins
```

---

## 19. Open Items for Founder

- [ ] Confirm initial admin email (yours): used for first signup + super_admin
- [ ] Decide if 2FA is required for admin (recommended for production; defer to v1.1 if too complex)
- [ ] Confirm 2-person approval default (currently OFF; toggle on later)
- [ ] Decide hosting for admin web: Vercel / Netlify / Cloudflare Pages — recommend Cloudflare Pages (free, fast)
- [ ] Confirm DLT-approved SMS template wording for reactivation campaign
- [ ] Approve impersonation as a feature (some founders prefer to disable for compliance)
- [ ] Decide CSV column order for reactivation import (suggested: phone, name, last_visit_date, visit_count)
- [ ] Decide retention metric definition (suggested: 60-day inactive = churned)

---

## What's NOT in this session

- Edge Functions (Session 13): admin-impersonate-token, reactivation-blast, razorpay-reconcile
- Edge Functions for report aggregation if needed
- Cron jobs (system_health snapshots, etc.) — Session 13
- Public marketing site at diariesclub.com (separate project; Pre-Launch checklist)
