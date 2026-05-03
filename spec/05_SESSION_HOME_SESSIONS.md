# Session 5 — Home Tab + Sessions

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-4 complete.

---

## Session Header

```
I am building Diaries Club. Auth, onboarding, foundation, schema, and RPCs are
all done. This session: build the Home tab and complete play-session lifecycle.

Estimated time: 5-6 hours
What to build:
  - Home tab with 4 distinct states (no session / active / grace / post-session)
  - Adaptive layout: timer dominates when nothing else, compact when other prompts active
  - Wallet card with bottom-sheet top-up modal
  - Razorpay integration (test mode for dev)
  - Session start flow: 1hr / 2hr selection → payment method → confirmation
  - QR code display + parent-shows-staff-scans flow
  - Session timer (server-clock driven)
  - Grace period UX
  - Extend session bottom sheet
  - Persistent birthday card (always visible if birthday in next 90 days)
  - Notification inbox sheet
  - Marketing consent card (24h after onboarding OR after 1st session)
  - Wallet balance live-updates via Supabase Realtime

What NOT to build:
  - Pre-booking prompts (locked decision: Profile-only, no auto-prompt)
  - Hero Recap Card / reflection screen (Session 6 — Gamification)
  - Order placement (Session 7 — Club + Orders)
  - Adventure tab (Session 8)
  - Birthday booking flow (Session 9)
  - Profile screens (Session 5b — separate session)

Output expected:
  - Functional Home tab in lib/features/home/
  - Wallet top-up working with Razorpay test mode end-to-end
  - Session can be created → QR shown → timer running
  - All states of Home properly handled
  - Realtime subscriptions update wallet balance, session status, notifications

Acceptance:
  - Top up ₹500 with Razorpay test card → balance updates within 5s
  - Start 1hr session via wallet → QR appears → status shows "active"
  - Wait until expiry → timer flips to grace state with yellow border
  - Tap "Extend" → bottom sheet → +30min → timer resumes from new expiry
  - Killing app and reopening: state restores correctly (timer accurate)
  - Birthday card shows for child whose birthday is within 90 days
```

---

## 1. Home Tab Architecture

### 1.1 Four primary states

| State | Trigger | Layout |
|---|---|---|
| `idle` | No active or grace session | Hero greeting + Wallet + Start Session CTA + Cards |
| `active` | A session row exists with status='active' | Adaptive: big timer if no other prompts, compact otherwise |
| `grace` | Session row with status='grace' | Yellow-bordered timer + Extend CTA prominent |
| `post_session` | Recent session completed, recap pending | Recap card prominent at top, returns to idle after dismiss |

Detection logic (one Riverpod provider, single source of truth):

```dart
@riverpod
Stream<HomeState> homeState(HomeStateRef ref) async* {
  final supabase = Supabase.instance.client;
  final familyId = supabase.auth.currentUser?.id;
  if (familyId == null) {
    yield const HomeState.idle();
    return;
  }

  // Subscribe to sessions table for this family
  await for (final rows in supabase
      .from('sessions')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .order('created_at', ascending: false)
      .limit(5)) {

    final activeOrGrace = rows.firstWhereOrNull(
      (r) => ['active', 'grace'].contains(r['status'])
    );

    if (activeOrGrace != null) {
      final session = Session.fromJson(activeOrGrace);
      if (session.status == 'active') {
        yield HomeState.active(session);
      } else {
        yield HomeState.grace(session);
      }
      continue;
    }

    // Check for completed-but-recap-pending session in last 30 mins
    final recentCompleted = rows.firstWhereOrNull((r) =>
      r['status'] == 'completed' &&
      r['reflection_status'] == 'pending' &&
      DateTime.parse(r['completed_at']).isAfter(
        DateTime.now().subtract(const Duration(minutes: 30))
      )
    );

    if (recentCompleted != null) {
      yield HomeState.postSession(Session.fromJson(recentCompleted));
      continue;
    }

    yield const HomeState.idle();
  }
}
```

### 1.2 Adaptive layout decision tree

When `active`:
- Are there other "important" prompts visible? (birthday-due-this-week, healthy-bite-pending, low-balance-warning, marketing-consent-card)
- **No other prompts** → big timer takes top 60% of screen
- **At least one other prompt** → compact timer at top (~120 height), other content below

```dart
@riverpod
bool hasUrgentHomePrompts(HasUrgentHomePromptsRef ref) {
  final birthdayWeek = ref.watch(birthdayWithinWeekProvider).valueOrNull ?? false;
  final healthyBite = ref.watch(healthyBitePendingProvider).valueOrNull ?? false;
  final lowBalance = ref.watch(lowWalletBalanceProvider).valueOrNull ?? false;
  // marketing_consent_card has its own visibility logic

  return birthdayWeek || healthyBite || lowBalance;
}
```

---

## 2. Home Screen — `lib/features/home/home_screen.dart`

### 2.1 Outer structure

```dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final state = ref.watch(homeStateProvider);

    return Scaffold(
      appBar: HomeAppBar(),
      body: state.when(
        data: (s) => switch (s) {
          HomeStateIdle() => const _IdleHomeView(),
          HomeStateActive(:final session) => _SessionHomeView(session: session),
          HomeStateGrace(:final session) => _GraceHomeView(session: session),
          HomeStatePostSession(:final session) => _PostSessionHomeView(session: session),
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => FriendlyErrorScreen(code: 'E-HOME', userMessage: 'Couldn\'t load home'),
      ),
    );
  }
}
```

### 2.2 HomeAppBar

```
LEFT:  Avatar (circle, 36×36) — child's photo if any, else parent initials
       Tap → navigates to /profile
CENTER: Empty (clean look)
RIGHT: Bell icon with unread badge → opens notification inbox sheet
       (unread count from notifications table where is_read=false)
```

### 2.3 Idle state layout

```
┌─────────────────────────────────────┐
│ HomeAppBar (avatar + bell)          │
├─────────────────────────────────────┤
│ GREETING                            │
│ "Hi, [Family Name] 👋"              │
│ "Ready for adventure?"              │
├─────────────────────────────────────┤
│ WALLET CARD (large, prominent)      │
│ ┌─────────────────────────────┐     │
│ │ Diaries Wallet              │     │
│ │ ₹1,250                      │     │
│ │ +120 Diaries Coins earned   │     │
│ │ [Top up] button             │     │
│ └─────────────────────────────┘     │
├─────────────────────────────────────┤
│ START SESSION CTA                   │
│ ┌─────────────────────────────┐     │
│ │ Start playing               │     │
│ │ Pick your time and go       │     │
│ │ [Start session →]           │     │
│ └─────────────────────────────┘     │
├─────────────────────────────────────┤
│ BIRTHDAY CARD (if applicable)       │
│ persistent, always visible if       │
│ birthday in next 90 days            │
├─────────────────────────────────────┤
│ MARKETING CONSENT CARD              │
│ (only if conditions met, see §11)   │
├─────────────────────────────────────┤
│ HEALTHY BITE WIDGET                 │
│ (only if pending claim exists)      │
├─────────────────────────────────────┤
│ RECENT ACTIVITY (last 3 events)     │
│ XP, sessions, top-ups               │
├─────────────────────────────────────┤
│ Bottom nav (Home active)            │
└─────────────────────────────────────┘
```

### 2.4 Active state layout (adaptive)

**No urgent prompts → big timer dominates:**
```
┌─────────────────────────────────────┐
│ HomeAppBar                          │
├─────────────────────────────────────┤
│         ●○○                         │
│      child avatar                   │
│                                     │
│         42:18                       │ ← timer (display size, dominant)
│      time remaining                 │
│                                     │
│    [Show QR] secondary              │
│    [Extend session] outlined        │
├─────────────────────────────────────┤
│ Wallet card (compact, ~80 height)   │
├─────────────────────────────────────┤
│ Birthday card (if applicable)       │
└─────────────────────────────────────┘
```

**With urgent prompts → compact timer:**
```
┌─────────────────────────────────────┐
│ HomeAppBar                          │
├─────────────────────────────────────┤
│ COMPACT TIMER ROW                   │
│ ●○○ Aarav · 42:18 · [QR]           │
├─────────────────────────────────────┤
│ Birthday card (urgent)              │
│ Healthy bite waiting                │
│ Wallet card                         │
│ Extend session button (full width)  │
└─────────────────────────────────────┘
```

### 2.5 Grace state layout

```
┌─────────────────────────────────────┐
│ HomeAppBar                          │
├─────────────────────────────────────┤
│ ⚠ Yellow gradient background       │
│         child avatar                │
│                                     │
│         +05:23                      │ ← over by 5min 23s
│    Planning to extend?              │
│                                     │
│  [Extend session] PRIMARY (gold)    │
│  [I'm wrapping up] secondary        │
├─────────────────────────────────────┤
│ Wallet card                         │
└─────────────────────────────────────┘
```

The timer color is `AppColors.warningYellow`. The screen has a soft yellow tint overlay to communicate urgency without panic.

### 2.6 Post-session state layout

```
┌─────────────────────────────────────┐
│ HomeAppBar                          │
├─────────────────────────────────────┤
│ HERO RECAP CARD                     │ ← prominent
│ "Aarav had an adventure!"           │
│ [Tap to reflect →]                  │
│                                     │
│ Plus all idle-state content below   │
└─────────────────────────────────────┘
```

The Hero Recap card itself is built in Session 6. Here we just render a placeholder card with a "Tap to reflect" CTA that navigates to `/reflection/:sessionId`.

---

## 3. Wallet Card Component — `lib/features/home/widgets/wallet_card.dart`

### 3.1 Layout

```dart
class WalletCard extends ConsumerWidget {
  final bool compact;
  const WalletCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final wallet = ref.watch(currentWalletProvider);

    return wallet.when(
      data: (w) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.navy, Color(0xFF2A4A8B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("Diaries Wallet",
                  style: AppTextStyles.caption(c, color: Colors.white70)),
                const Spacer(),
                if (!compact) Icon(PhosphorIcons.wallet(), color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Money.fromPaise(w.balancePaise),
              style: compact ? AppTextStyles.h2(c, color: Colors.white)
                              : AppTextStyles.display(c, color: Colors.white),
            ),
            if (!compact && w.coinsLifetime > 0) ...[
              const SizedBox(height: 4),
              Text(
                "${w.coinsLifetime} Diaries Coins earned ⭐",
                style: AppTextStyles.caption(c, color: AppColors.gold),
              ),
            ],
            const SizedBox(height: compact ? 12 : 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _showTopUpSheet(c),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
                ),
                child: Text(compact ? "Top up" : "Top up wallet",
                  style: AppTextStyles.button(c)),
              ),
            ),
          ],
        ),
      ),
      loading: () => const ShimmerWalletCard(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showTopUpSheet(BuildContext c) => showModalBottomSheet(
    context: c,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const TopUpSheet(),
  );
}
```

### 3.2 Realtime wallet provider

```dart
@riverpod
Stream<Wallet> currentWallet(CurrentWalletRef ref) async* {
  final familyId = Supabase.instance.client.auth.currentUser?.id;
  if (familyId == null) return;

  await for (final rows in Supabase.instance.client
      .from('wallets')
      .stream(primaryKey: ['id'])
      .eq('family_id', familyId)
      .limit(1)) {
    if (rows.isEmpty) continue;
    yield Wallet.fromJson(rows.first);
  }
}
```

---

## 4. Top-up Bottom Sheet — `lib/features/home/widgets/top_up_sheet.dart`

### 4.1 Layout

```
┌─────────────────────────────────────┐
│         ▔▔                          │ ← drag handle
│                                     │
│ Top up wallet                  ✕   │
│ Current balance: ₹250               │
├─────────────────────────────────────┤
│ Quick top-up                        │
│                                     │
│ ┌────────┐ ┌────────┐               │
│ │ ₹500   │ │ ₹1,000 │               │
│ └────────┘ └────────┘               │
│                                     │
│ ┌────────┐ ┌────────┐               │
│ │ ₹3,000 │ │ ₹4,000 │               │
│ │ +₹500  │ │ +₹1,000│               │
│ │ 🔥 POP │ │ ⭐ BEST │               │
│ └────────┘ └────────┘               │
├─────────────────────────────────────┤
│ Custom amount                       │
│ ┌─────────────────────┐             │
│ │ ₹ 1,500             │             │
│ └─────────────────────┘             │
├─────────────────────────────────────┤
│ Pay with Razorpay                   │
│ [Pay ₹1,500 →]                      │
│                                     │
│ Secure payment by Razorpay          │
└─────────────────────────────────────┘
```

The 4 quick-amount tiles come from `venue_config.topup_offers` JSON (already seeded with placeholders in Session 1). Each tile shows the amount, any bonus credit, and an optional badge.

### 4.2 Logic

```dart
class TopUpSheet extends ConsumerStatefulWidget {
  const TopUpSheet({super.key});
  @override
  ConsumerState<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<TopUpSheet> {
  late Razorpay _razorpay;
  int? _selectedAmountPaise;
  int? _selectedBonusPaise;
  final _customController = TextEditingController();
  bool _isProcessing = false;
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    _customController.dispose();
    super.dispose();
  }

  void _selectQuickAmount(int amount, int bonus) {
    setState(() {
      _selectedAmountPaise = amount;
      _selectedBonusPaise = bonus;
      _customController.clear();
    });
  }

  void _useCustomAmount() {
    final rupees = int.tryParse(_customController.text);
    if (rupees == null || rupees < 100 || rupees > 50000) return;
    setState(() {
      _selectedAmountPaise = rupees * 100;
      _selectedBonusPaise = 0;
    });
  }

  Future<void> _initiatePayment() async {
    if (_selectedAmountPaise == null) return;

    setState(() => _isProcessing = true);
    _idempotencyKey = const Uuid().v4();

    final family = await ref.read(currentFamilyProvider.future);

    try {
      // Create order via Edge Function (server-side amount validation)
      final order = await Supabase.instance.client.functions.invoke(
        'create-razorpay-order',
        body: {
          'amount_paise': _selectedAmountPaise,
          'bonus_paise': _selectedBonusPaise,
          'idempotency_key': _idempotencyKey,
        },
      );

      final options = {
        'key': F.razorpayKeyId,
        'amount': _selectedAmountPaise,
        'order_id': order.data['order_id'],
        'name': 'Diaries Club',
        'description': 'Wallet top-up',
        'prefill': {
          'contact': family!.phone,
          'email': family.email ?? '',
        },
        'notes': {
          'family_id': family.id,
          'idempotency_key': _idempotencyKey,
        },
        'theme': {'color': '#1E3A7B'},
      };

      _razorpay.open(options);
    } catch (e, st) {
      Sentry.captureException(e, stackTrace: st);
      setState(() => _isProcessing = false);
      _showError("Couldn't start payment. Please try again.");
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse res) async {
    // Webhook will credit the wallet server-side via wallet_topup RPC.
    // We just need to wait for the wallet stream to update.
    // Show optimistic success UI immediately.

    setState(() => _isProcessing = false);
    if (mounted) {
      Navigator.pop(context);
      _showSuccessToast(_selectedAmountPaise! + _selectedBonusPaise!);
    }
  }

  void _onPaymentError(PaymentFailureResponse res) {
    setState(() => _isProcessing = false);
    _showError("Payment failed. ${res.message ?? ''}");
  }

  void _onExternalWallet(ExternalWalletResponse res) {
    // External wallet selected — leave handling to webhook
  }

  void _showSuccessToast(int totalPaise) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.activeGreen,
      content: Text("${Money.fromPaise(totalPaise)} added to your wallet 🎉"),
    ));

  void _showError(String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.adminRed,
      content: Text(msg),
    ));

  @override
  Widget build(BuildContext c) {
    final config = ref.watch(venueConfigProvider).valueOrNull;
    final offers = (config?.topupOffers as List?) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(c).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12, left: 24, right: 24,
        bottom: MediaQuery.of(c).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Top up wallet", style: AppTextStyles.h2(c)),
              IconButton(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          // ... offers grid (2x2), custom amount field, pay button
        ],
      ),
    );
  }
}
```

### 4.3 Edge Function: `create-razorpay-order`

This is implemented in Session 12 (Edge Functions). For now, it's an HTTP endpoint that:
1. Receives `amount_paise`, `bonus_paise`, `idempotency_key`
2. Validates amount > 0, ≤ ₹50,000
3. Calls Razorpay Orders API to create an order
4. Returns `order_id`
5. Stores pending top-up record (used by webhook for matching)

Razorpay webhook calls `wallet_topup` RPC on payment.captured event with the same `idempotency_key`. The wallet stream updates within 1-2 seconds.

---

## 5. Start Session Flow

### 5.1 Start Session CTA

Tap "Start session" → navigates to `/session/start`.

### 5.2 Session Start Screen — `lib/features/sessions/session_start_screen.dart`

```
APP BAR
  - Back arrow
  - Title: "Start a session"

CHILD SELECTION (only if multiple children)
  - Avatar row, scrollable horizontally
  - Tap to select; selected gets gold border
  - If only one child, hidden / pre-selected

DURATION SELECTION
  - Two big cards side by side:

    ┌──────────────┐  ┌──────────────┐
    │   1 hour     │  │   2 hours    │
    │   ₹800       │  │   ₹1,100     │
    │   Quick play │  │   Best value │
    └──────────────┘  └──────────────┘

PAYMENT METHOD
  - Two rows:
    ○ Diaries Wallet (₹1,250 available)
       Disabled if balance < required
    ○ Cash at venue
       Caption: "Pay our team when you check in"

PRIMARY CTA (sticky bottom)
  - Wallet path: "Pay ₹800 from wallet"
  - Cash path: "Continue with cash"
  - Disabled until duration + payment chosen

COPY VOICE
  - Direct, no upselling
  - "₹800 / 1 hour" not "Only ₹800!" or "Limited time"
```

### 5.3 Session create logic

```dart
Future<void> _startSession() async {
  setState(() => _isLoading = true);
  final idempotencyKey = const Uuid().v4();
  // Save key to secure storage before call (resume protection)
  await _saveIdempotencyKey(idempotencyKey);

  try {
    final result = await Supabase.instance.client.rpc('session_create', params: {
      'p_venue_id': _venueId,
      'p_family_id': Supabase.instance.client.auth.currentUser!.id,
      'p_child_id': _selectedChildId,
      'p_duration_minutes': _selectedDurationMinutes,
      'p_payment_method': _selectedPaymentMethod,
      'p_idempotency_key': idempotencyKey,
    });

    final sessionId = result['session_id'];

    // Clear idempotency key (success)
    await _clearIdempotencyKey(idempotencyKey);

    // Navigate to QR display
    if (mounted) context.go('/session/qr/$sessionId');

  } on PostgrestException catch (e) {
    setState(() => _isLoading = false);

    if (e.message.contains('insufficient_balance')) {
      _showInsufficientBalanceSheet();
    } else {
      _showError("Couldn't start session. Please try again.");
    }
  }
}

void _showInsufficientBalanceSheet() {
  showModalBottomSheet(
    context: context,
    builder: (_) => InsufficientBalanceSheet(
      requiredPaise: _selectedDurationMinutes == 60 ? 80000 : 110000,
      onTopUp: () {
        Navigator.pop(context);
        showModalBottomSheet(context: context, builder: (_) => const TopUpSheet());
      },
      onSwitchToCash: () {
        Navigator.pop(context);
        setState(() => _selectedPaymentMethod = 'cash');
      },
    ),
  );
}
```

---

## 6. QR Display Screen — `lib/features/sessions/session_qr_screen.dart`

After session creation, parent shows QR to staff for verification.

### 6.1 Layout

```
APP BAR
  - Title: "Show this at the desk"
  - No back button (this is "in-session", going back is confusing)

KEEP SCREEN ON
  - Use `wakelock_plus` to keep screen awake on this view

CONTENT
  - Child avatar + name at top
  - Large QR code (300×300, gold border)
  - Caption below: "Show to staff. They'll scan to confirm."
  - Session details:
    - Duration: 1 hour
    - Amount: ₹800
    - Payment: Wallet (or Cash)
  - Brightness boost button: "Brighten screen ☀"
    Tap → `screen_brightness` package boosts to max

SECONDARY CTA
  - "Continue without scanning" (small text link, bottom)
    Tap → opens confirm sheet:
    "Already checked in? We'll mark this session as active."
    [Confirm] [Cancel]
    On confirm → marks session active server-side via Edge Function
```

### 6.2 QR generation

```dart
class SessionQrScreen extends ConsumerWidget {
  final String sessionId;
  const SessionQrScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext c, WidgetRef ref) {
    // Wakelock
    WakelockPlus.enable();

    final qrData = ref.watch(sessionQrDataProvider(sessionId));

    return Scaffold(
      // ...
      body: qrData.when(
        data: (qr) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.gold, width: 3),
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
            ),
            child: QrImageView(
              data: qr.encoded,
              size: 280,
              version: QrVersions.auto,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: AppColors.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square, color: AppColors.navy,
              ),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(
          code: 'E-QR', userMessage: 'Couldn\'t generate QR'),
      ),
    );
  }
}
```

### 6.3 QR data structure

```dart
@riverpod
Future<QrData> sessionQrData(SessionQrDataRef ref, String sessionId) async {
  // Edge Function generates short-lived nonce + signs the QR payload
  final response = await Supabase.instance.client.functions.invoke(
    'generate-session-qr',
    body: {'session_id': sessionId},
  );
  return QrData.fromJson(response.data);
}

class QrData {
  final String encoded;       // base64-encoded JWT signed by service_role
  final DateTime expiresAt;   // 15 mins after generation

  // Decoded payload includes: session_id, family_id, nonce, expires_at
}
```

The QR contains a nonce stored in `qr_nonces` table (Session 1 schema). Staff scan triggers `verify-session-qr` Edge Function which marks the nonce used and confirms session check-in. Staff scanning is built in Session 10.

### 6.4 Session timer auto-starts

The session is created with `expires_at` set immediately. The timer starts ticking from session creation, not from QR scan. This is intentional — the parent already paid; if they choose to delay scanning, they're using their own time.

---

## 7. Active Session: Session Timer Component

Already built in Session 3 (`SessionTimerWidget`). Adaptive sizes:

```dart
class SessionTimerWidget extends ConsumerStatefulWidget {
  final Session session;
  final TimerSize size;
  // ...
}

enum TimerSize { compact, regular, dominant }
```

`compact` = ~30 height, single line "42:18" inline with avatar
`regular` = ~120 height, fits with other Home prompts
`dominant` = ~240 height, display-size text, takes top half of screen

Home picks the size based on `hasUrgentHomePrompts`.

---

## 8. Extend Session Bottom Sheet — `lib/features/sessions/widgets/extend_session_sheet.dart`

Triggered from active or grace state.

### 8.1 Layout

```
┌─────────────────────────────────────┐
│         ▔▔                          │
│ Extend session                  ✕   │
├─────────────────────────────────────┤
│ Currently expires: 4:30 PM          │
│ Wallet balance: ₹450                │
├─────────────────────────────────────┤
│ Add time:                           │
│                                     │
│  ┌─────────┐ ┌─────────┐            │
│  │ +30 min │ │ +1 hour │            │
│  │ ₹150    │ │ ₹300    │            │
│  └─────────┘ └─────────┘            │
├─────────────────────────────────────┤
│ Pay with:                           │
│ ○ Wallet                            │
│ ○ Cash at desk                      │
├─────────────────────────────────────┤
│ [Extend session]  PRIMARY           │
└─────────────────────────────────────┘
```

### 8.2 Logic

Calls `session_extend` RPC with:
- `p_session_id`
- `p_duration_minutes`
- `p_payment_method`
- `p_initiated_by = 'parent'`
- `p_idempotency_key`

On success: bottom sheet closes, timer auto-updates via Realtime stream (sessions table subscription).

---

## 9. Birthday Card (Persistent on Home) — `lib/features/home/widgets/birthday_card.dart`

Always rendered if any child has birthday in next 90 days.

### 9.1 Layout

```
┌─────────────────────────────────────┐
│  🎂 (illustration, not emoji)       │
│  Aarav's birthday                   │
│  32 days to go                      │
│                                     │
│  [Plan the party →]                 │
└─────────────────────────────────────┘
```

Background: warm gradient (gold to coral). Tap CTA → navigates to `/birthday`.

### 9.2 Visibility rules

- One card per child (if 2 kids both within 90 days, show 2 cards stacked)
- Always visible until birthday day +1 (then hidden until next year)
- Once a reservation is made for that birthday → card morphs:
  - "Aarav's party is coming up!" + "Saturday March 15, 4:00 PM"
  - CTA changes to "View status →"

### 9.3 Provider

```dart
@riverpod
Future<List<UpcomingBirthday>> upcomingBirthdays(UpcomingBirthdaysRef ref) async {
  final familyId = Supabase.instance.client.auth.currentUser?.id;
  if (familyId == null) return [];

  final children = await Supabase.instance.client
    .from('children').select().eq('family_id', familyId);

  final today = IstDates.nowInIst();
  final results = <UpcomingBirthday>[];

  for (final c in children) {
    final dob = DateTime.parse(c['date_of_birth']);
    final nextBirthday = DateTime(today.year, dob.month, dob.day);
    final daysUntil = nextBirthday.difference(today).inDays;

    if (daysUntil >= 0 && daysUntil <= 90) {
      // Check if reservation exists
      final reservation = await Supabase.instance.client
        .from('birthday_reservations')
        .select()
        .eq('child_id', c['id'])
        .inFilter('status', ['reserved', 'deposit_paid', 'confirmed'])
        .maybeSingle();

      results.add(UpcomingBirthday(
        child: Child.fromJson(c),
        daysUntil: daysUntil,
        reservation: reservation != null ? BirthdayReservation.fromJson(reservation) : null,
      ));
    }
  }

  return results;
}
```

---

## 10. Notification Inbox Sheet

Bell icon on AppBar opens this sheet.

### 10.1 Layout

```
┌─────────────────────────────────────┐
│         ▔▔                          │
│ Notifications              Mark all │
├─────────────────────────────────────┤
│ TODAY                               │
│ ● Hero Card earned                  │
│   Just now                          │
│                                     │
│ ● Aarav reached Champion!           │
│   2 hours ago                       │
├─────────────────────────────────────┤
│ THIS WEEK                           │
│ ○ Wallet topped up ₹500             │
│   Yesterday                         │
└─────────────────────────────────────┘
```

- Filled dot = unread
- Empty dot = read
- Tap notification → navigates to `deep_link` from notification row, marks as read
- "Mark all" → updates all unread for current user to read=true

### 10.2 Live updates

Supabase Realtime subscription on notifications table for current user. Bell badge updates in real time.

---

## 11. Marketing Consent Card — `lib/features/home/widgets/marketing_consent_card.dart`

### 11.1 Show conditions

Show on Home tab if ALL of:
- `families.marketing_consent = false` (default)
- `families.created_at < 24h ago` OR user has at least 1 completed session
- User hasn't dismissed this card

Track dismissal in SharedPreferences: `marketing_consent_dismissed_at`. Once dismissed, never show again (per locked decision).

### 11.2 Layout

```
┌─────────────────────────────────────┐
│  ✉  Stay in the loop               │
│  Get birthday tips, party ideas,    │
│  and special offers from Diaries.   │
│                                     │
│  [Yes, send me updates]  PRIMARY    │
│  [No thanks]             secondary  │
└─────────────────────────────────────┘
```

On "Yes": update `families.marketing_consent = true`, dismiss card.
On "No thanks": just dismiss card.

---

## 12. Healthy Bite Pending Widget

If a child earned a Healthy Bite (per session_create with bite=true), but staff hasn't given them the card yet, show a small pulsing card on Home:

```
┌─────────────────────────────────────┐
│ 🥕 Aarav earned a Healthy Bite!     │
│ Show this at the FIT counter        │
│ [Show] [I got it]                   │
└─────────────────────────────────────┘
```

- "Show" → navigates to QR screen for the bite (separate from session QR)
- "I got it" → marks bite as distributed (calls staff-side flow stub)

This is a placeholder; staff distribution flow is in Session 10.

---

## 13. Recent Activity (Idle State Bottom)

Last 3 events from a unified activity stream:

```
┌─────────────────────────────────────┐
│ Recent activity                     │
├─────────────────────────────────────┤
│ ⊕ Topped up ₹500            2 hr ago│
│ ⌛ Aarav played 2 hours      Mar 28  │
│ ⭐ +50 XP earned             Mar 28  │
│                                     │
│ See all →                           │
└─────────────────────────────────────┘
```

Source: union of `wallet_transactions`, `sessions` (completed), `xp_events`. Sort by created_at desc, limit 3. Tap → opens full activity log (built in Session 5b — Profile).

---

## 14. Resume / Reopen Logic

If app is killed mid-session and reopened:
- Splash → Auth restored → Family loaded → routed to Home
- Home state stream emits current state from sessions table
- If active session: timer renders correctly (server-clock-based, accurate)
- If grace session: yellow state renders correctly
- No state lost; all derived from server

If app killed mid-payment (Razorpay):
- On reopen, idempotency key is in secure storage
- Wallet balance might already reflect the payment (webhook fired)
- If not yet reflected: user just sees old balance briefly, webhook arrives, balance updates
- If user retries top-up with same idempotency key: RPC returns "idempotent: true", no double-charge

---

## 15. Files to Create

```
lib/
├── features/
│   ├── home/
│   │   ├── home_screen.dart
│   │   ├── home_app_bar.dart
│   │   ├── views/
│   │   │   ├── idle_home_view.dart
│   │   │   ├── session_home_view.dart
│   │   │   ├── grace_home_view.dart
│   │   │   └── post_session_home_view.dart
│   │   └── widgets/
│   │       ├── wallet_card.dart
│   │       ├── top_up_sheet.dart
│   │       ├── start_session_card.dart
│   │       ├── birthday_card.dart
│   │       ├── healthy_bite_widget.dart
│   │       ├── marketing_consent_card.dart
│   │       ├── recent_activity_list.dart
│   │       └── notification_inbox_sheet.dart
│   └── sessions/
│       ├── session_start_screen.dart
│       ├── session_qr_screen.dart
│       └── widgets/
│           ├── extend_session_sheet.dart
│           ├── insufficient_balance_sheet.dart
│           └── duration_card.dart
├── core/
│   └── providers/
│       ├── home_state_provider.dart
│       ├── current_wallet_provider.dart
│       ├── upcoming_birthdays_provider.dart
│       ├── notifications_provider.dart
│       └── venue_config_provider.dart
```

---

## 16. Acceptance Tests (Manual)

```
TEST 1 — Top up via wallet
  1. Home (idle) → tap wallet "Top up"
  2. Bottom sheet opens
  3. Tap ₹500 quick tile → "Pay ₹500"
  4. Razorpay opens with test card prefill
  5. Use card 4111 1111 1111 1111, CVV 123, future expiry
  6. Payment succeeds → toast "₹500 added 🎉"
  7. Wallet card updates within 5s to show new balance

TEST 2 — Start session via wallet
  1. Wallet has ≥₹800
  2. Home idle → "Start session" → /session/start
  3. Pick child (if multiple) → 1 hour → Wallet → "Pay ₹800 from wallet"
  4. RPC succeeds → /session/qr/:id
  5. QR renders, screen brightness boosted, wakelock active
  6. Back to Home → state shows active timer

TEST 3 — Insufficient balance
  1. Wallet has <₹800
  2. Try to start 1hr session via wallet
  3. RPC returns insufficient_balance
  4. Bottom sheet appears with [Top up] and [Switch to cash]

TEST 4 — Adaptive timer
  1. Active session, no urgent prompts → big dominant timer
  2. Birthday approaches < 7 days → birthday card becomes urgent → timer goes compact
  3. Healthy Bite pending → still compact (multiple urgent prompts)

TEST 5 — Grace state
  1. Wait until session expires (or shorten in DB for testing)
  2. Status flips to grace → yellow background, +mm:ss counter
  3. Tap "Extend session" → bottom sheet → +30 min wallet
  4. RPC succeeds → flips back to active, fresh timer

TEST 6 — Hard cap auto-close
  1. Manually update session in DB: started_at = now() - 110 min, duration = 60 min
  2. After grace_max_minutes (30), cron fires force_close_grace_sessions
  3. Session status = 'auto_closed'
  4. Home re-renders to idle state

TEST 7 — Birthday card visibility
  1. Update child DOB so next birthday is 60 days away
  2. Home shows birthday card with "60 days to go"
  3. Tap → navigates to /birthday
  4. After reservation made → card morphs to "View status →"

TEST 8 — Notification inbox
  1. In DB, insert notification row for current user
  2. Bell badge updates within 2s (Realtime)
  3. Tap bell → sheet opens, notification visible with deep link
  4. Tap notification → navigates + marks read
  5. Bell badge decrements

TEST 9 — Marketing consent card
  1. Onboard new user → Home shows no marketing card initially
  2. Wait 24h (or change family.created_at) → card appears
  3. Tap "Yes" → marketing_consent = true, card dismisses
  4. Restart app → card never reappears

TEST 10 — Realtime wallet sync
  1. App open on Home
  2. In another device/dashboard, manually credit wallet via SQL
  3. Wallet card on app updates within 2s without refresh

TEST 11 — Resume after kill mid-session
  1. Active session, kill app via task manager
  2. Reopen → splash → home → active session correct
  3. Timer continues from correct value (server-clock-based)
```

---

## 17. Open Items for Founder

- [ ] Confirm Razorpay test key (currently `rzp_test_xxx` placeholder in flavors)
- [ ] Confirm topup_offers JSON in venue_config (₹500 / ₹1,000 / ₹3,000+₹500 / ₹4,000+₹1,000)
- [ ] Approve QR validity period (currently 15 min from generation)
- [ ] Confirm session pricing (₹800/1hr, ₹1,100/2hr — already in venue_config)
- [ ] Confirm extension pricing (₹300/hour — already in venue_config)
- [ ] Decide if "Continue without scanning" fallback path should require staff PIN later (security tradeoff)

---

## What's NOT in this session

- Hero Recap card detail (Session 6)
- Reflection screen (Session 6)
- Order placement (Session 7)
- Birthday booking flow (Session 9)
- Profile screens / wallet history / referral (Session 5b)
- Staff QR scanning (Session 10)
- Razorpay webhook (Session 12)
- Force-close cron (Session 13)
