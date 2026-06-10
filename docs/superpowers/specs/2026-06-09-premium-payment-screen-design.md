# Premium Payment Screen — Design Specification

**Date:** 2026-06-09  
**Feature:** Wallet Top-Up Payment Screen (replaces existing `TopUpSheet`)  
**Status:** Approved — deferred to next build cycle  
**Author:** Kimi Code (brainstorming session)  

---

## 1. Background & Goals

Play Diaries is an indoor soft play area for kids. Parents top up their wallet via the Flutter app to pay for sessions, food, and merchandise. Trust and clarity are paramount — parents must feel confident every rupee is accounted for.

The existing `TopUpSheet` uses Razorpay for all payment methods, including UPI. Razorpay charges a 2% platform fee even on UPI transactions. This design introduces a **native UPI intent flow** that bypasses Razorpay for UPI, saving the business platform fees while giving users a faster, more familiar payment experience.

**Design principles:**
- Clean, minimal, white background
- No fake colored circles pretending to be app icons
- Real app recognition through the **system's native chooser** (Android) or direct deep links (iOS)
- Premium feel inspired by Swiggy/Zomato payment flows
- One unified UPI button — not a grid of app buttons

---

## 2. Architecture & Placement

### 2.1 File Structure

```
lib/features/home/widgets/
├── top_up_sheet.dart              # EXISTING — to be replaced
├── premium_payment_sheet.dart     # NEW — main payment sheet
├── upi_verification_sheet.dart    # NEW — post-payment verification
├── payment_success_sheet.dart     # NEW — success animation
└── ios_upi_fallback_sheet.dart    # NEW — iOS deep-link fallback + copy UPI ID
```

```
lib/core/services/
└── upi_intent_service.dart        # NEW — platform-specific UPI launch logic
```

### 2.2 Entry Point

The new sheet replaces the existing `TopUpSheet` as the wallet top-up entry point.

**Trigger:** `wallet_card.dart` → "Top up wallet" button  
**Navigation:** `showModalBottomSheet<void>(builder: (_) => PremiumPaymentSheet(amountPaise: selectedAmount))`

### 2.3 State Management

- **Widget-level state:** `ConsumerStatefulWidget` with local `_PaymentSheetState`
- **No new global providers** — reuses existing `currentWalletProvider` for balance refresh
- **Razorpay instance:** Managed locally in state (same pattern as current `TopUpSheet`)

### 2.4 Existing Code Reuse

| Component | Reuse Strategy |
|---|---|
| `PrimaryButton` | Direct reuse — CTA styling |
| `AppColors` / `AppTextStyles` | Direct reuse — navy, gold, activeGreen |
| `Money.fromPaise()` | Direct reuse — currency formatting |
| Razorpay card flow | Copied from `top_up_sheet.dart`, not rewritten |
| `razorpay-topup` Edge Function | Unchanged — used for card payments only |

---

## 3. UI Design

### 3.1 Main Payment Sheet (`PremiumPaymentSheet`)

```
┌─────────────────────────────┐
│  ─────── drag handle        │  24px radius top corners
│                             │
│  Add Money to Wallet        │  caption style, grey
│  ₹500                       │  display style, bold, navy
│  [Zero transaction fees]    │  green pill badge
│                             │
│  ⚡ Pay Instantly            │  section header with lightning bolt
│  ┌─────────────────────┐    │
│  │ [UPI icon]           │    │
│  │ UPI — Google Pay,    │    │  title: h3
│  │ PhonePe, Paytm       │    │  subtitle: "Zero fees • Money credited instantly"
│  │ Zero fees • Instant  │    │  right: forward arrow (›)
│  │              ›       │    │
│  └─────────────────────┘    │  full-width tappable card, 12px radius
│                             │
│  ───────── or pay with ──── │  divider with text
│                             │
│  ┌─────────────────────┐    │
│  │ [card icon]          │    │
│  │ Card or Net Banking  │    │  title: h3
│  │ Visa, Mastercard,    │    │  subtitle: card networks
│  │ RuPay                │    │  right: "2% fee" in subtle orange/grey
│  │              2% fee  │    │
│  │              ›       │    │
│  └─────────────────────┘    │
│                             │
│  🔒 Secured by 256-bit      │  lock icon + caption text, centered
│        Play Diaries         │  brand text, very subtle grey
│         encryption          │
│                             │
└─────────────────────────────┘
```

**Amount:** Passed as constructor parameter `amountPaise` (int). Displayed via `Money.fromPaise(amountPaise).formatted`.

**Green pill:** `AppColors.activeGreen` background, white text, 16px height, 8px horizontal padding. Only shown when UPI section is visible.

**"or pay with" divider:** Horizontal line (`Divider` with `Color(0xFFE0E0E0)`), centered text "or pay with" in caption style.

**Trust footer:** `PhosphorIcons.lockKey` icon + "Secured by 256-bit encryption" in `AppTextStyles.caption` with `Colors.grey[500]`. Below: "Play Diaries" in same style but lighter.

### 3.2 UPI Verification Sheet (`UpiVerificationSheet`)

Shown after the user returns from the UPI app (both Android and iOS).

```
┌─────────────────────────────┐
│  ─────── drag handle        │
│                             │
│  Complete your payment      │  h2
│  in the UPI app             │
│                             │
│  Transaction Reference      │  caption
│  PD_abc123_xyz789           │  body, monospace, copy icon
│  [📋 Copy]                  │
│                             │
│  Amount: ₹500               │  body
│  Status: Pending...         │  body with spinner
│                             │
│  ┌─────────────────────┐    │
│  │ I've completed      │    │  PrimaryButton, full width
│  │ payment             │    │
│  └─────────────────────┘    │
│                             │
│  Pay a different way        │  text link, dismisses to main sheet
│                             │
└─────────────────────────────┘
```

**Behavior:**
- Tapping "I've completed payment" calls `verify-upi-payment` Edge Function
- Polls `pending_payments` table every 3 seconds for up to 30 seconds
- Shows auto-refresh spinner with "We are verifying your payment..."
- On success → dismisses, shows `PaymentSuccessSheet`
- On timeout (>30s) → shows "Payment expired. Try again." with retry button

### 3.3 Payment Success Sheet (`PaymentSuccessSheet`)

```
┌─────────────────────────────┐
│  ─────── drag handle        │
│                             │
│        ✅                   │  Animated checkmark (green circle + check)
│                             │
│  Payment successful!        │  h2, centered
│  ₹500 added to your wallet  │  body, centered, grey
│                             │
│  ┌─────────────────────┐    │
│  │ Done                │    │  PrimaryButton, full width
│  └─────────────────────┘    │
│                             │
└─────────────────────────────┘
```

**Animation:** `flutter_animate` — scale + fade in for checkmark, then slide up for text.

**On dismiss:** `Navigator.of(context).pop()` twice (close success sheet + close payment sheet) → wallet balance auto-refreshes via `currentWalletProvider` stream.

### 3.4 iOS UPI Fallback Sheet (`IosUpiFallbackSheet`)

Shown on iOS when no deep link works.

```
┌─────────────────────────────┐
│  ─────── drag handle        │
│                             │
│  Pay with UPI               │  h2
│                             │
│  UPI ID                     │  caption
│  yourname@okaxis            │  bodyLarge, bold, copy icon
│  [📋 Tap to copy]           │
│                             │
│  Amount: ₹500               │  body
│                             │
│  ── or open your app ──     │
│                             │
│  [Open Google Pay]          │  text link (tries tez://)
│  [Open PhonePe]             │  text link (tries phonepe://)
│  [Open Paytm]               │  text link (tries paytmmp://)
│                             │
│  ┌─────────────────────┐    │
│  │ I've completed      │    │  PrimaryButton
│  │ payment             │    │
│  └─────────────────────┘    │
│                             │
│  Pay a different way        │  text link
│                             │
└─────────────────────────────┘
```

**Copy behavior:** Tapping the UPI ID copies to clipboard and shows a brief "Copied" toast (SnackBar).

**Deep link text links:** Subtle underlined text, `AppColors.navy`. If a link fails (app not installed), show "App not installed" in red below that link.

---

## 4. Payment Flow (State Machine)

```
[User taps "Top up wallet"] 
    │
    ▼
[Show PremiumPaymentSheet with amount]
    │
    ├──► [User taps "Card or Net Banking"]
    │        │
    │        ▼
    │    [Existing Razorpay flow — unchanged]
    │    [create_order → razorpay.open() → confirm → success]
    │
    └──► [User taps "UPI"]
             │
             ▼
         [Generate transaction ref: PD_{userId}_{timestamp}]
         [Save to Supabase pending_payments table]
         │
             ├──► [Platform == Android]
             │        │
             │        ▼
             │    [Launch upi://pay intent via url_launcher]
             │    [System chooser opens with real app icons]
             │    [User selects app → pays → returns]
             │
             └──► [Platform == iOS]
                      │
                      ▼
                  [Try canLaunchUrl on tez://]
                  │    ├──► [Yes] → Launch tez://
                  │    └──► [No]
                  │             ▼
                  │         [Try canLaunchUrl on phonepe://]
                  │         │    ├──► [Yes] → Launch phonepe://
                  │         │    └──► [No]
                  │         │             ▼
                  │         │         [Try canLaunchUrl on paytmmp://]
                  │         │         │    ├──► [Yes] → Launch paytmmp://
                  │         │         │    └──► [No]
                  │         │         │             ▼
                  │         │         │         [Show IosUpiFallbackSheet]
                  │         │         │         [User copies UPI ID or tries text links]
                  │         │         │         [User pays manually]
                  │         │         │
                  │         │         ▼
                  │         │     [User taps "I've completed payment"]
                  │         │
                  ▼         ▼         ▼
              [Show UpiVerificationSheet]
              [Display txn ref (copyable)]
              [Poll Supabase pending_payments every 3s]
              │
                  ├──► [Status == 'success']
                  │        │
                  │        ▼
                  │    [Show PaymentSuccessSheet]
                  │    [Dismiss → wallet refreshes]
                  │
                  ├──► [Status == 'pending' after 30s]
                  │        │
                  │        ▼
                  │    [Show "Payment expired. Try again."]
                  │    ["Retry" → back to PremiumPaymentSheet]
                  │
                  └──► [Status == 'failed']
                           │
                           ▼
                       [Show error with txn ref]
                       ["If charged, refund in 3-5 days"]
```

---

## 5. Platform-Specific Behavior

### 5.1 Android

**Mechanism:** `url_launcher` with `upi://pay` URI.

```dart
final upiUrl = Uri.parse(
  'upi://pay?'
  'pa=YOUR_UPI_ID&'
  'pn=Play%20Diaries&'
  'am=${amountInRupees}&'
  'cu=INR&'
  'tr=$transactionRef&'
  'tn=Wallet%20top-up',
);

if (await canLaunchUrl(upiUrl)) {
  await launchUrl(upiUrl, mode: LaunchMode.externalApplication);
}
```

**Behavior:** Android's intent system automatically shows a system chooser dialog listing all installed UPI apps (GPay, PhonePe, Paytm, BHIM, bank apps, etc.) with their real icons. The user selects one, the app opens with amount and payee pre-filled, they authenticate and pay.

**Return to app:** The user manually switches back (recent apps or home button). The app was in the background; `UpiVerificationSheet` was already shown before launch, so it's waiting.

### 5.2 iOS

**Mechanism:** `url_launcher` with proprietary app URL schemes.

```dart
final schemes = [
  ('tez://upi/pay?...', 'Google Pay'),      // May be gpay:// now
  ('phonepe://pay?...', 'PhonePe'),
  ('paytmmp://pay?...', 'Paytm'),
];

for (final (scheme, name) in schemes) {
  final uri = Uri.parse('$scheme&pa=YOUR_UPI_ID&am=...');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return; // Successfully launched
  }
}

// None worked → show fallback sheet
showModalBottomSheet(builder: (_) => IosUpiFallbackSheet(...));
```

**Info.plist additions required:**
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>tez</string>
  <string>gpay</string>
  <string>phonepe</string>
  <string>paytmmp</string>
</array>
```

**Behavior:** If a scheme works, the UPI app opens directly with pre-filled details. If none work, the fallback sheet appears with copyable UPI ID and text links.

**Return to app:** Same as Android — manual switch back.

### 5.3 URL Scheme Monitoring

Because iOS URL schemes are undocumented and change without notice, the implementation should:
1. Log which scheme succeeded/failed to analytics/Supabase
2. Include a remote config flag to disable broken schemes without app update
3. Consider a monthly manual test of schemes

---

## 6. Backend Integration (Supabase)

### 6.1 Database Schema: `pending_payments`

```sql
CREATE TABLE pending_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
  amount_paise int NOT NULL CHECK (amount_paise > 0),
  transaction_ref text NOT NULL UNIQUE,
  payment_method text NOT NULL CHECK (payment_method IN ('upi_intent', 'razorpay')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed', 'expired')),
  platform text NOT NULL CHECK (platform IN ('android', 'ios')),
  metadata jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '15 minutes'),
  verified_at timestamptz
);

CREATE INDEX idx_pending_payments_family ON pending_payments(family_id);
CREATE INDEX idx_pending_payments_ref ON pending_payments(transaction_ref);
CREATE INDEX idx_pending_payments_status ON pending_payments(status) WHERE status = 'pending';
```

### 6.2 Row Level Security

```sql
ALTER TABLE pending_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Families can view own pending payments"
  ON pending_payments FOR SELECT
  USING (family_id IN (
    SELECT id FROM families WHERE phone = auth.jwt() ->> 'phone'
  ));

CREATE POLICY "App can insert pending payments"
  ON pending_payments FOR INSERT
  WITH CHECK (family_id IN (
    SELECT id FROM families WHERE phone = auth.jwt() ->> 'phone'
  ));
```

### 6.3 Edge Function: `verify-upi-payment` (NEW)

**Purpose:** Called when user taps "I've completed payment" in the verification sheet.

**Input:** `{ transaction_ref: string }`

**Logic:**
1. Look up `pending_payments` by `transaction_ref`
2. If status already `'success'` → return `{ status: 'success' }`
3. If `expires_at < now()` → update status to `'expired'`, return `{ status: 'expired' }`
4. For UPI intent payments: **manual verification for MVP**
   - In the first version, the merchant (Play Diaries staff) verifies UPI payments via their bank statement or UPI app history
   - Staff uses the existing admin web app (`lib/admin/`) to view pending payments and mark them as `'success'`
   - Alternatively, a lightweight Supabase Realtime listener on `pending_payments` can notify staff
   - Future iteration: integrate with IDFC merchant API or payment gateway webhook for automatic verification
5. Return `{ status: 'pending' }` if not yet verified

**Note:** For the MVP, the verification is asynchronous. The user's verification sheet polls and will eventually show success once staff confirms. This is acceptable for a soft play area where payments are relatively low-volume and staff can verify in real-time.

### 6.4 Wallet Credit Flow

When `pending_payments.status` becomes `'success'`:

**Option A (MVP):** Staff manually verifies and credits wallet via the existing admin web app (`lib/admin/`). A new admin screen `PendingPaymentsScreen` would list pending UPI payments with confirm/reject actions.

**Option B (preferred):** Supabase trigger or Edge Function:
```sql
CREATE OR REPLACE FUNCTION credit_wallet_on_payment_success()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'success' AND OLD.status = 'pending' THEN
    UPDATE wallets
    SET balance_paise = balance_paise + NEW.amount_paise,
        updated_at = now()
    WHERE family_id = NEW.family_id;
    
    INSERT INTO wallet_transactions (
      family_id, type, amount_paise, description, reference_id
    ) VALUES (
      NEW.family_id, 'credit', NEW.amount_paise, 
      'Wallet top-up via UPI', NEW.transaction_ref
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_credit_wallet
  AFTER UPDATE ON pending_payments
  FOR EACH ROW
  EXECUTE FUNCTION credit_wallet_on_payment_success();
```

### 6.5 Razorpay Card Flow (Unchanged)

The existing `razorpay-topup` Edge Function continues to handle card payments:
1. `create_order` → returns Razorpay order ID
2. `razorpay.open(options)` → user pays
3. `payment.success` callback → calls `confirm` Edge Function
4. `confirm` credits wallet directly

No changes to this flow. The `PremiumPaymentSheet` simply routes card taps to the same Razorpay logic.

---

## 7. Error Handling & Edge Cases

| Scenario | User Experience | Technical Handling |
|---|---|---|
| **No UPI app installed (Android)** | System chooser may be empty or not open. User returns to verification sheet. | After return, verification flow checks status. If no payment found, shows "We couldn't detect a payment." |
| **Deep link fails (iOS)** | Falls through to `IosUpiFallbackSheet` automatically. | Sequential `canLaunchUrl` checks. No user-facing error. |
| **User cancels in UPI app** | Returns to verification sheet. Taps "Pay a different way" to go back. | Status stays `'pending'`. User can retry. |
| **Payment pending > 15 min** | "Payment expired. Try again." with retry button. | `expires_at` trigger auto-updates status. |
| **User says "I paid" but no record** | "We couldn't find this payment. If you were charged, it'll be refunded in 3-5 business days. Try again?" | Edge Function returns `not_found`. Staff can manually verify later. |
| **Network error during save** | "Something went wrong. Please try again." with retry. | Exponential backoff (1s, 2s, 4s). Max 3 retries. |
| **App killed during payment** | On next app open, check for `pending_payments` with status `'pending'`. If found and not expired, resume verification sheet. | `initState` check in home screen or app lifecycle listener. |
| **Duplicate transaction ref** | Should never happen (timestamp + userId). If it does, increment counter suffix. | Server-side UNIQUE constraint catches it; generate new ref. |
| **Double payment (user pays twice)** | Same txn ref in UPI params should prevent double-charge at UPI level. If two records exist, both verified, wallet credited twice. | Idempotency: `wallet_transactions` should have UNIQUE on `reference_id` to prevent double credit. |

---

## 8. Security Considerations

1. **Transaction reference:** `PD_{userId}_{timestamp}` format. Not guessable (includes timestamp to millisecond). `UNIQUE` constraint prevents replays.
2. **RLS:** Pending payments table has RLS — users can only see their own records.
3. **Amount integrity:** Amount is set server-side when saving pending payment. UPI intent URL uses the same amount. No client-side tampering possible.
4. **UPI ID exposure:** The UPI ID (`YOUR_UPI_ID@okaxis`) is embedded in the app. This is acceptable for a merchant receiving payments — it's public information (like a bank account number).
5. **Verification:** MVP uses manual verification. Future: integrate bank API or webhook for automatic verification.

---

## 9. Dependencies

Already present in `pubspec.yaml`:
- `url_launcher: ^6.2.5` — UPI intent launch
- `razorpay_flutter: ^1.3.6` — Card payments (unchanged)
- `supabase_flutter: ^2.5.0` — Database, Edge Functions
- `flutter_riverpod: ^2.5.1` — State management
- `phosphor_flutter: ^2.1.0` — Icons
- `flutter_animate: ^4.5.2` — Success animation

**No new dependencies required.**

---

## 10. Testing Checklist

### 10.1 Android
- [ ] UPI button opens system chooser with real app icons
- [ ] Selecting GPay opens GPay with correct amount and payee
- [ ] Selecting PhonePe opens PhonePe with correct amount and payee
- [ ] Completing payment in UPI app → returning to app → verification sheet shows success
- [ ] Canceling in UPI app → returning → "Pay a different way" works
- [ ] No UPI app installed → graceful fallback message
- [ ] Card button opens Razorpay with same amount
- [ ] Network failure during pending payment save → retry works

### 10.2 iOS
- [ ] UPI button tries deep links in order
- [ ] If GPay installed → opens GPay directly
- [ ] If no apps installed → fallback sheet appears
- [ ] Copy UPI ID button works
- [ ] "Open Google Pay" text link works when GPay installed
- [ ] Completing payment manually → "I've completed payment" → verification → success
- [ ] Card button opens Razorpay (same as Android)

### 10.3 Backend
- [ ] `pending_payments` row created with correct data
- [ ] `transaction_ref` is UNIQUE
- [ ] Expired payments auto-update to `'expired'`
- [ ] Successful payment triggers wallet credit
- [ ] Duplicate `reference_id` in `wallet_transactions` prevented

---

## 11. Migration Plan

1. **Phase 1 (This build):** No code changes. Design saved. Team sets up `pending_payments` table and `verify-upi-payment` Edge Function.
2. **Phase 2 (Next build):** Implement `PremiumPaymentSheet`, `UpiVerificationSheet`, `PaymentSuccessSheet`, `IosUpiFallbackSheet`, and `UpiIntentService`.
3. **Phase 3:** Replace `TopUpSheet` import in `wallet_card.dart` with `PremiumPaymentSheet`.
4. **Phase 4:** Monitor analytics — which iOS deep links work, UPI completion rate, fallback rate.
5. **Phase 5:** If IDFC merchant API becomes available, upgrade `verify-upi-payment` to automatic verification.

---

## 12. Open Questions for Implementation

1. **UPI ID:** Replace `[REPLACE_WITH_YOUR_UPI_ID]` with actual business UPI ID before shipping.
2. **iOS URL schemes:** Verify current schemes for GPay (`tez://` vs `gpay://`), PhonePe, Paytm at time of implementation.
3. **Verification method:** Confirm MVP will use manual staff verification vs. automatic bank API.
4. **Wallet credit trigger:** Decide between Supabase trigger (Option B) vs. manual staff credit (Option A) for MVP.
5. **Analytics:** Add `metadata` logging for which UPI app was used, which iOS scheme succeeded.

---

## 13. References

- Existing payment implementation: `lib/features/home/widgets/top_up_sheet.dart`
- Existing Razorpay integration: `lib/features/home/widgets/top_up_sheet.dart` (lines ~200-400)
- Wallet provider: `lib/core/providers/current_wallet_provider.dart`
- Primary button: `lib/core/widgets/primary_button.dart`
- App colors: `lib/core/theme/app_colors.dart`
- App text styles: `lib/core/theme/app_text_styles.dart`
- Currency utils: `lib/core/utils/currency.dart`
- Router: `lib/core/router/app_router.dart`
