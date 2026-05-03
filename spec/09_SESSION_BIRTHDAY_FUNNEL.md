# Session 9 — Birthday Funnel (Primary Business Lever)

> Paste `00_CONTEXT.md` first, then this file. Fresh Claude Code conversation.
> **Prerequisites:** Sessions 1-8 + 5b complete.

---

## Session Header

```
I am building Diaries Club. The birthday funnel is the PRIMARY business lever
for this app. Every birthday booked ≈ ₹15K-45K in revenue and the app's
gamification is largely justified by surfacing birthday opportunities to parents.

This session: build the entire birthday flow.

Locked decisions for this session (different from earlier draft):
  - NO in-app deposit. Deposit paid offline (cash/UPI to admin).
    The app just submits "interest" — admin closes the deal externally.
  - NO staff-app photo capture. Admin uploads photos manually from web admin.
  - Birthday-exclusive hero card AUTO-awarded the moment admin marks
    reservation 'completed'.

Estimated time: 6-7 hours
What to build:
  - Persistent birthday card on Home (already started in Session 5; expand here)
  - Birthday Discovery hub (the journey landing screen)
  - Birthday Packages browse screen
  - Package Detail + Reserve Interest screen
  - Reservation Status tracking screen (4 states)
  - Post-event Album viewer
  - Birthday journey state engine (D-90 through D+7 push triggers)
  - Hero-progression triggered birthday nudges
  - Schema adjustments for the simplified flow

What NOT to build:
  - Razorpay deposit flow (removed by decision)
  - Staff photo capture mode (removed by decision)
  - Admin photo upload UI (Session 11 — Admin web)
  - Cron triggers for birthday journey D-N notifications (Session 13)

Output expected:
  - Working in-app birthday browse + reserve flow
  - Reservation status visible end-to-end
  - Album viewable once admin uploads photos and marks completed
  - All schema adjustments in supabase/migrations/0004_birthday_simplification.sql

Acceptance:
  - Tap Home birthday card → Birthday Discovery
  - Browse 3 packages → reserve interest with month preference + guest counts
  - Reservation status updates as admin progresses it through dashboard
  - On completion: hero card auto-awarded, push fires "Album coming in 3-5 days"
  - When admin uploads photos and marks album_ready: push fires, parent views album
```

---

## 1. Schema Adjustments (Migration 0004)

The simplified flow needs a few tweaks:

```sql
-- 0004_birthday_simplification.sql

-- 1. Adjust status enum: drop deposit_paid stage
ALTER TABLE birthday_reservations DROP CONSTRAINT IF EXISTS birthday_reservations_status_check;
ALTER TABLE birthday_reservations ADD CONSTRAINT birthday_reservations_status_check
  CHECK (status IN (
    'interested',         -- parent submitted reserve interest
    'admin_contacted',    -- our team has reached out
    'confirmed',          -- date locked, deposit collected offline
    'completed',          -- party happened
    'cancelled',
    'no_show'
  ));

-- Migrate existing rows (just in case):
UPDATE birthday_reservations
  SET status = 'interested'
  WHERE status = 'reserved';
UPDATE birthday_reservations
  SET status = 'admin_contacted'
  WHERE status = 'deposit_paid';

-- 2. deposit_paid_paise becomes informational (admin types it after offline collection)
COMMENT ON COLUMN birthday_reservations.deposit_paid_paise IS
  'Informational only — paid offline (cash/UPI). Admin enters this when collecting.';

-- 3. Optional date/time at submission (matches "Roughly when" UI)
ALTER TABLE birthday_reservations
  ALTER COLUMN slot_date DROP NOT NULL,
  ALTER COLUMN slot_start_time DROP NOT NULL,
  ALTER COLUMN slot_end_time DROP NOT NULL;
ALTER TABLE birthday_reservations
  ADD COLUMN IF NOT EXISTS preferred_month TEXT,
  ADD COLUMN IF NOT EXISTS preferred_window TEXT,
  ADD COLUMN IF NOT EXISTS special_requests TEXT;

-- 4. Photo upload is admin-only (loosen the constraint)
ALTER TABLE birthday_party_photos
  ALTER COLUMN uploaded_by_pin DROP NOT NULL;
ALTER TABLE birthday_party_photos
  ADD COLUMN IF NOT EXISTS uploaded_by_admin UUID REFERENCES auth.users(id);
ALTER TABLE birthday_party_photos
  ADD CONSTRAINT photo_uploader_required
  CHECK (uploaded_by_pin IS NOT NULL OR uploaded_by_admin IS NOT NULL);

-- 5. The birthday_availability table is no longer used (admin schedules manually)
-- Keep it but mark as not currently used; can re-enable later
COMMENT ON TABLE birthday_availability IS
  'Reserved for future use. Currently admin schedules slots externally.';

-- 6. Adjust the 'reservation_expires_at' meaning: now means "auto-cancel if admin
-- doesn't contact within X days" (default 3 days)
COMMENT ON COLUMN birthday_reservations.reservation_expires_at IS
  'Auto-cancel if status stays at interested past this. Default: 72h after submission.';

-- 7. Update RPCs (replace birthday_reservation_create + drop birthday_deposit_record)
-- See section 4 below for new RPC signature
```

### 1.1 Replace `birthday_reservation_create` RPC

```sql
DROP FUNCTION IF EXISTS birthday_reservation_create(...);

CREATE OR REPLACE FUNCTION birthday_reservation_create(
  p_venue_id UUID,
  p_family_id UUID,
  p_child_id UUID,
  p_package_id UUID,
  p_preferred_month TEXT,        -- e.g., "March 2026" or "Late April"
  p_preferred_window TEXT,       -- e.g., "weekend afternoon"
  p_num_kids INTEGER,
  p_num_adults INTEGER,
  p_special_requests TEXT,
  p_triggered_by TEXT,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pkg birthday_packages%ROWTYPE;
  v_res birthday_reservations%ROWTYPE;
  v_existing birthday_reservations%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT * INTO v_existing FROM birthday_reservations WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN
      RETURN jsonb_build_object('success', true, 'idempotent', true, 'reservation_id', v_existing.id);
    END IF;
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages WHERE id = p_package_id AND venue_id = p_venue_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'invalid_package'; END IF;

  -- Block: already an active reservation for this child this birthday year?
  IF EXISTS (
    SELECT 1 FROM birthday_reservations
    WHERE child_id = p_child_id
      AND status IN ('interested', 'admin_contacted', 'confirmed')
      AND created_at > now() - INTERVAL '1 year'
  ) THEN
    RAISE EXCEPTION 'reservation_exists';
  END IF;

  INSERT INTO birthday_reservations(
    venue_id, family_id, child_id, package_id,
    preferred_month, preferred_window, special_requests,
    num_kids, num_adults,
    package_price_paise, balance_paise,
    triggered_by, reservation_expires_at,
    idempotency_key, status
  ) VALUES (
    p_venue_id, p_family_id, p_child_id, p_package_id,
    p_preferred_month, p_preferred_window, p_special_requests,
    p_num_kids, p_num_adults,
    v_pkg.price_paise, v_pkg.price_paise, -- balance = full until admin records deposit
    p_triggered_by, now() + INTERVAL '72 hours',
    p_idempotency_key, 'interested'
  ) RETURNING * INTO v_res;

  -- Notify family (acknowledgement)
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    p_family_id, 'birthday_d_minus_90',
    'Reservation request received!',
    'Our team will WhatsApp you within 24 hours to confirm.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_family_id, 'customer', 'birthday.reserve_interest', 'birthday_reservation',
          v_res.id, p_venue_id,
          jsonb_build_object('package_id', p_package_id, 'kids', p_num_kids, 'adults', p_num_adults));

  RETURN jsonb_build_object(
    'success', true,
    'reservation_id', v_res.id
  );
END $$;
```

### 1.2 New RPC: `birthday_reservation_complete` (admin-only)

Triggered from admin web when admin marks the party as completed. Auto-awards the hero card.

```sql
CREATE OR REPLACE FUNCTION birthday_reservation_complete(
  p_reservation_id UUID,
  p_admin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_pkg birthday_packages%ROWTYPE;
  v_hero TEXT;
  v_card hero_card_definitions%ROWTYPE;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;

  IF v_res.status NOT IN ('confirmed') THEN
    RAISE EXCEPTION 'invalid_state_for_completion';
  END IF;

  SELECT * INTO v_pkg FROM birthday_packages WHERE id = v_res.package_id;

  -- Determine hero theme for the card
  v_hero := COALESCE(v_pkg.hero_theme, 'mixed');
  -- For 'mixed', pick a random hero
  IF v_hero = 'mixed' THEN
    v_hero := (ARRAY['rafi','ellie','gerry','zena'])[1 + floor(random() * 4)::int];
  END IF;

  -- Pick a birthday-exclusive card matching the hero (or any if specific not found)
  SELECT * INTO v_card FROM hero_card_definitions
    WHERE is_birthday_exclusive = true AND hero = v_hero AND is_active = true
      AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = v_res.child_id)
    ORDER BY random() LIMIT 1;

  IF NOT FOUND THEN
    -- Fallback: any birthday-exclusive card
    SELECT * INTO v_card FROM hero_card_definitions
      WHERE is_birthday_exclusive = true AND is_active = true
        AND id NOT IN (SELECT card_id FROM hero_card_collection WHERE child_id = v_res.child_id)
      ORDER BY random() LIMIT 1;
  END IF;

  IF v_card.id IS NOT NULL THEN
    INSERT INTO hero_card_collection(child_id, card_id, birthday_booking_id)
    VALUES (v_res.child_id, v_card.id, v_res.id)
    ON CONFLICT (child_id, card_id) DO NOTHING;
  END IF;

  -- Birthday host XP bonus to the child (1000 XP, split across all 4 traits)
  PERFORM xp_credit_with_split(
    v_res.child_id, v_res.family_id, v_res.venue_id,
    'birthday_hosted',
    250, 250, 250, 250,           -- 1000 / 4
    v_res.id,
    jsonb_build_object('package', v_pkg.tier)
  );

  -- Mark completed + link card
  UPDATE birthday_reservations SET
    status = 'completed',
    birthday_hero_card_id = v_card.id
  WHERE id = p_reservation_id;

  -- Notify parent
  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_d_plus_1',
    'Thank you for celebrating with us! 🎉',
    'A special birthday hero card has been added to ' ||
    (SELECT name FROM children WHERE id = v_res.child_id) ||
    '''s collection. Photos coming in 3-5 days.',
    '/birthday/status/' || v_res.id, v_res.id
  );

  -- Audit
  INSERT INTO audit_log(actor_id, actor_type, action, entity_type, entity_id, venue_id, new_value)
  VALUES (p_admin_id, 'admin', 'birthday.complete', 'birthday_reservation',
          v_res.id, v_res.venue_id,
          jsonb_build_object('hero_card_id', v_card.id));

  RETURN jsonb_build_object(
    'success', true,
    'hero_card_id', v_card.id,
    'hero_card_name', v_card.name
  );
END $$;

GRANT EXECUTE ON FUNCTION birthday_reservation_complete TO service_role;
```

### 1.3 New RPC: `birthday_album_publish` (admin-only)

Triggered when admin finishes uploading photos and clicks "Publish album."

```sql
CREATE OR REPLACE FUNCTION birthday_album_publish(
  p_reservation_id UUID,
  p_admin_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_res birthday_reservations%ROWTYPE;
  v_photo_count INTEGER;
BEGIN
  SELECT * INTO v_res FROM birthday_reservations WHERE id = p_reservation_id FOR UPDATE;

  IF v_res.status <> 'completed' THEN
    RAISE EXCEPTION 'invalid_state_for_album';
  END IF;

  SELECT COUNT(*) INTO v_photo_count FROM birthday_party_photos WHERE reservation_id = p_reservation_id;
  IF v_photo_count = 0 THEN RAISE EXCEPTION 'no_photos'; END IF;

  UPDATE birthday_reservations SET
    album_ready_at = now()
  WHERE id = p_reservation_id;

  INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
  VALUES (
    v_res.family_id, 'birthday_album_ready',
    'Photo album is ready! 📸',
    'See ' || v_photo_count || ' photos from the celebration.',
    '/birthday/album/' || v_res.id, v_res.id
  );

  RETURN jsonb_build_object('success', true, 'photo_count', v_photo_count);
END $$;

GRANT EXECUTE ON FUNCTION birthday_album_publish TO service_role;
```

---

## 2. Birthday Card on Home (Expanded)

Already started in Session 5. Here's the full state machine:

### 2.1 Display variants

| State | Trigger | Visual |
|---|---|---|
| `not_started` | child birthday > 90 days away OR < 1 day past | hidden |
| `prompting` | birthday in 90-1 days, no reservation yet | warm gradient, "Plan the party" CTA |
| `interest_submitted` | reservation status = 'interested' | navy bg, "We'll WhatsApp you" |
| `admin_contacted` | reservation status = 'admin_contacted' | navy bg, "Talking with our team" |
| `confirmed` | reservation status = 'confirmed' | gold bg, "[Date] - [Time]" |
| `tomorrow` | confirmed AND date is today/tomorrow | celebration anim, "Tomorrow!" |
| `completed_album_pending` | status = 'completed', album_ready_at = NULL | muted bg, "Photos coming soon" |
| `completed_album_ready` | status = 'completed', album_ready_at SET | gold bg, "View album" |

### 2.2 Provider

```dart
@riverpod
Future<BirthdayCardState> birthdayCardState(BirthdayCardStateRef ref) async {
  final familyId = Supabase.instance.client.auth.currentUser?.id;
  if (familyId == null) return const BirthdayCardState.hidden();

  final children = await ref.read(familyChildrenProvider.future);
  final today = IstDates.nowInIst();

  for (final child in children) {
    final dob = child.dateOfBirth;
    final nextBirthday = DateTime(today.year, dob.month, dob.day);
    final daysUntil = nextBirthday.difference(today).inDays;

    if (daysUntil < -1 || daysUntil > 90) continue;

    // Check existing reservation for this birthday
    final reservation = await Supabase.instance.client
      .from('birthday_reservations')
      .select()
      .eq('child_id', child.id)
      .gte('created_at', DateTime(today.year - 1, dob.month, dob.day).toIso8601String())
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

    if (reservation == null) {
      return BirthdayCardState.prompting(child: child, daysUntil: daysUntil);
    }

    final r = BirthdayReservation.fromJson(reservation);
    return _stateFromReservation(child, r, daysUntil);
  }

  return const BirthdayCardState.hidden();
}

BirthdayCardState _stateFromReservation(Child child, BirthdayReservation r, int daysUntil) {
  return switch (r.status) {
    'interested' => BirthdayCardState.interestSubmitted(child: child, reservation: r),
    'admin_contacted' => BirthdayCardState.adminContacted(child: child, reservation: r),
    'confirmed' => daysUntil <= 1
      ? BirthdayCardState.tomorrow(child: child, reservation: r)
      : BirthdayCardState.confirmed(child: child, reservation: r),
    'completed' => r.albumReadyAt == null
      ? BirthdayCardState.completedAlbumPending(child: child, reservation: r)
      : BirthdayCardState.completedAlbumReady(child: child, reservation: r),
    _ => const BirthdayCardState.hidden(),
  };
}
```

---

## 3. Birthday Discovery — `lib/features/birthday/birthday_discovery_screen.dart`

The hub for the birthday journey.

### 3.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Birthday                     │
├─────────────────────────────────────┤
│ HERO SECTION (~280 high)            │
│ [warm gradient bg, soft confetti]   │
│ [Aarav avatar in ring]              │
│ Aarav's birthday                    │
│ 32 days to go                       │
├─────────────────────────────────────┤
│ JOURNEY PROGRESS BAR                │
│ ●─●─○─○─○─○                          │
│ D-90  D-60  D-30  D-14  D-7   Day 0 │
│ "We're here →"                      │
├─────────────────────────────────────┤
│ MAIN CTA CARD                       │
│ "Plan Aarav's birthday with us"     │
│ "3 packages, every detail handled"  │
│ [See packages →]    PRIMARY          │
├─────────────────────────────────────┤
│ PACKAGE TEASER ROW (horizontal)     │
│ [Basics] [Hero Adv] [Legendary]     │
├─────────────────────────────────────┤
│ SOCIAL PROOF                        │
│ Recently celebrated                 │
│ A.'s birthday — 24 happy kids       │
│ R.'s birthday — Hero Adventure      │
├─────────────────────────────────────┤
│ HELP                                │
│ Have questions? Chat with us        │
└─────────────────────────────────────┘
```

### 3.2 Implementation

```dart
class BirthdayDiscoveryScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final state = ref.watch(birthdayCardStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Birthday")),
      body: state.when(
        data: (s) {
          // If reservation exists, redirect to status screen
          if (s case BirthdayCardStateInterestSubmitted() ||
                   BirthdayCardStateAdminContacted() ||
                   BirthdayCardStateConfirmed() ||
                   BirthdayCardStateTomorrow()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final reservationId = (s as dynamic).reservation.id;
              context.go('/birthday/status/$reservationId');
            });
            return const Center(child: CircularProgressIndicator());
          }

          if (s case BirthdayCardStatePrompting(:final child, :final daysUntil)) {
            return _DiscoveryView(child: child, daysUntil: daysUntil);
          }

          // Album-ready state → straight to album
          if (s case BirthdayCardStateCompletedAlbumReady(:final reservation)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.go('/birthday/album/${reservation.id}');
            });
            return const Center(child: CircularProgressIndicator());
          }

          // No upcoming birthday → empty
          return const _NoBirthdayState();
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-BD', userMessage: 'Couldn\'t load'),
      ),
    );
  }
}
```

The Discovery view has the full layout above. Hero illustration small group of all 4 heroes around a cake (asset to be commissioned).

### 3.3 Journey progress bar

```dart
class JourneyProgressBar extends StatelessWidget {
  final int daysUntil;
  @override
  Widget build(BuildContext c) {
    final milestones = [
      (90, 'D-90'),
      (60, 'D-60'),
      (30, 'D-30'),
      (14, 'D-14'),
      (7, 'D-7'),
      (0, 'Day 0'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          Row(
            children: milestones.asMap().entries.expand((entry) {
              final i = entry.key;
              final (days, label) = entry.value;
              final isPast = daysUntil <= days;
              final isCurrent = i < milestones.length - 1
                ? daysUntil <= milestones[i].$1 && daysUntil > milestones[i+1].$1
                : daysUntil <= 0;

              return [
                _MilestoneDot(
                  isPast: isPast,
                  isCurrent: isCurrent,
                ),
                if (i < milestones.length - 1)
                  Expanded(child: Container(
                    height: 2,
                    color: isPast ? AppColors.gold : AppColors.lightBorder,
                  )),
              ];
            }).toList(),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: milestones.map((m) =>
              Text(m.$2, style: AppTextStyles.caption(c).copyWith(fontSize: 9)),
            ).toList(),
          ),
        ],
      ),
    );
  }
}
```

---

## 4. Birthday Packages Browse — `lib/features/birthday/birthday_packages_screen.dart`

### 4.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Choose a package             │
├─────────────────────────────────────┤
│ SUB-HEADER                          │
│ "All packages include 2hr exclusive │
│ play time, decor, food, and a host."│
├─────────────────────────────────────┤
│ PACKAGE CARDS (vertical stack,      │
│ equal weight per locked decision)   │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ [HERO IMAGE STRIP]              │ │
│ │ Birthday Basics      ₹15,000    │ │
│ │ from                             │ │
│ │ [Mixed heroes]                  │ │
│ │ ✓ 2hr exclusive play             │ │
│ │ ✓ Themed decor                   │ │
│ │ ✓ Kids' meal                     │ │
│ │ ✓ 1 host                         │ │
│ │ Up to 15 kids • 10 adults       │ │
│ │ [See details]                    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ [Most Booked badge]             │ │
│ │ ... Hero Adventure              │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ [Premium badge]                 │ │
│ │ ... Legendary                   │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ FOOTER                              │
│ Not sure? Chat with our team        │
└─────────────────────────────────────┘
```

### 4.2 Package card

```dart
class _PackageCard extends StatelessWidget {
  final BirthdayPackage package;
  final bool isMostBooked;
  final bool isPremium;

  @override
  Widget build(BuildContext c) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.lightBorder, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0,2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AspectRatio(
                  aspectRatio: 16/8,
                  child: CachedNetworkImage(
                    imageUrl: package.coverImageUrl ?? '',
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.gold.withOpacity(0.2),
                      child: Center(child: PhosphorIcon(PhosphorIcons.cake(), size: 48)),
                    ),
                  ),
                ),
              ),
              if (isMostBooked || isPremium)
                Positioned(
                  top: 12, right: 12,
                  child: _Badge(
                    label: isMostBooked ? "Most Booked" : "Premium",
                    color: isMostBooked ? AppColors.gold : AppColors.navy,
                  ),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + price
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(package.name, style: AppTextStyles.h3(c)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("from", style: AppTextStyles.caption(c)),
                        Text(
                          Money.fromPaise(package.pricePaise),
                          style: AppTextStyles.h2(c, color: AppColors.gold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Hero theme chip
                _HeroThemeChip(theme: package.heroTheme),
                const SizedBox(height: 16),

                // Inclusions
                ...(_extractInclusions(package.inclusions)
                  .take(4)
                  .map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        PhosphorIcon(PhosphorIcons.check(), size: 14, color: AppColors.activeGreen),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line, style: AppTextStyles.caption(c))),
                      ],
                    ),
                  ))),
                const SizedBox(height: 12),

                // Capacity
                Text(
                  "Up to ${package.maxKids} kids • ${package.maxAdults} adults",
                  style: AppTextStyles.caption(c).copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),

                // CTA
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: "See details",
                    onPressed: () => context.push('/birthday/reserve/${package.id}'),
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

The "Most Booked" and "Premium" badges are venue-controlled (admin can mark which package gets which badge — add column to schema if not already). For v1, hardcode: tier='hero_adventure' = Most Booked, tier='legendary' = Premium.

---

## 5. Package Detail + Reserve — `lib/features/birthday/package_detail_screen.dart`

The conversion screen.

### 5.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Hero Adventure               │
├─────────────────────────────────────┤
│ HERO MEDIA SECTION (~280 high)     │
│ [Carousel of 3-5 reference photos]  │
│ [Dots indicator]                    │
├─────────────────────────────────────┤
│ PRICE BAR (sticky-ish)              │
│ ₹25,000              20 kids • 15  │
│ All-inclusive • No surprises  adults│
├─────────────────────────────────────┤
│ WHAT'S INCLUDED                     │
│ ✓ 2 hours exclusive play time       │
│   "Whole play area, just for you"   │
│ ✓ Hero Adventure decor              │
│   "Themed setup with Rafi as star"  │
│ ✓ FIT party platter for kids        │
│ ✓ Coffee Diaries spread for adults  │
│ ✓ Themed birthday cake (1kg)        │
│ ✓ One trained host                  │
├─────────────────────────────────────┤
│ NOT INCLUDED (transparency)         │
│ – Return gifts                      │
│ – Custom photographer               │
│ – Outside food                      │
├─────────────────────────────────────┤
│ HOW BOOKING WORKS                   │
│ 1. Tell us roughly when, how many   │
│ 2. We'll WhatsApp you within 24hrs  │
│ 3. We confirm date and collect ₹8K  │
│    deposit (cash/UPI to our team)   │
├─────────────────────────────────────┤
│ YOUR PREFERENCES                    │
│ Roughly when?                       │
│ [Last weekend of March             ▼]│
│                                     │
│ Number of kids?                     │
│ [-] 15 [+]                          │
│                                     │
│ Number of adults?                   │
│ [-] 10 [+]                          │
│                                     │
│ Anything special? (optional)         │
│ [Allergies, themes, surprises...   ]│
├─────────────────────────────────────┤
│ STICKY BOTTOM CTA                   │
│ [Reserve interest]    PRIMARY        │
│ "No payment yet — we'll WhatsApp"   │
└─────────────────────────────────────┘
```

### 5.2 Submission

```dart
Future<void> _submit() async {
  setState(() => _isLoading = true);
  final idempotencyKey = const Uuid().v4();

  try {
    final result = await Supabase.instance.client.rpc(
      'birthday_reservation_create',
      params: {
        'p_venue_id': await ref.read(currentVenueIdProvider.future),
        'p_family_id': Supabase.instance.client.auth.currentUser!.id,
        'p_child_id': _selectedChildId,
        'p_package_id': widget.packageId,
        'p_preferred_month': _preferredMonth,
        'p_preferred_window': _preferredWindow,
        'p_num_kids': _numKids,
        'p_num_adults': _numAdults,
        'p_special_requests': _specialRequests.text.trim(),
        'p_triggered_by': widget.triggeredBy ?? 'manual',
        'p_idempotency_key': idempotencyKey,
      },
    );

    if (mounted) {
      context.go('/birthday/status/${result['reservation_id']}');
    }
  } on PostgrestException catch (e) {
    setState(() => _isLoading = false);

    if (e.message.contains('reservation_exists')) {
      _showError("You already have an active reservation for this child's birthday.");
    } else {
      _showError("Couldn't submit. Please try again.");
    }
  }
}
```

### 5.3 Image carousel

Use `PageView` for swipeable photos. Photos are admin-curated for each package (3-5 reference shots from past parties). Stored in `birthday_packages.gallery_image_urls` array.

---

## 6. Reservation Status — `lib/features/birthday/reservation_status_screen.dart`

The most complex screen in this session — 6 status variants.

### 6.1 Status header card variants

| Status | Header bg | Title |
|---|---|---|
| `interested` | gold gradient | "Reservation request received" |
| `admin_contacted` | navy | "Our team has reached out" |
| `confirmed` | green gradient | "You're confirmed! 🎉" |
| `confirmed (day-of)` | full celebration | "It's [child]'s birthday!" |
| `completed` (album pending) | muted celebration | "Thank you for celebrating" |
| `completed` (album ready) | full celebration palette | "Album is ready!" |

### 6.2 Implementation

```dart
class ReservationStatusScreen extends ConsumerWidget {
  final String reservationId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final reservation = ref.watch(reservationByIdProvider(reservationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Your reservation"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'cancel') _confirmCancel(c, ref);
              if (v == 'help') _openHelp();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'help', child: Text('Get help')),
              const PopupMenuItem(value: 'cancel', child: Text('Cancel reservation')),
            ],
          ),
        ],
      ),
      body: reservation.when(
        data: (r) => SingleChildScrollView(
          child: Column(
            children: [
              _StatusHeader(reservation: r),
              _ReservationSummaryCard(reservation: r),
              _PipelineTimeline(currentStatus: r.status, hasAlbum: r.albumReadyAt != null),
              _ActionCard(reservation: r),
              if (r.status == 'confirmed') _PartyDetailsCard(reservation: r),
              _ContactCard(),
              const SizedBox(height: 16),
              if (r.status != 'completed') _CancelLink(),
              const SizedBox(height: 24),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-BSTAT', userMessage: 'Couldn\'t load'),
      ),
    );
  }
}
```

### 6.3 Pipeline timeline

```dart
class _PipelineTimeline extends StatelessWidget {
  final String currentStatus;
  final bool hasAlbum;

  @override
  Widget build(BuildContext c) {
    final steps = [
      ('interested',          'Interest received',     null),
      ('admin_contacted',     'Team reaching out',     null),
      ('confirmed',           'Date confirmed',        null),
      ('confirmed_locked',    'Deposit collected',     'admin marks this externally'),
      ('completed',           'Party day',             null),
      ('album_ready',         'Album ready',           'Photos coming in 3-5 days'),
    ];

    final currentIndex = _statusIndex(currentStatus, hasAlbum);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(c).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final (id, label, hint) = entry.value;
          final isPast = i < currentIndex;
          final isCurrent = i == currentIndex;

          return _PipelineStep(
            label: label,
            hint: hint,
            isPast: isPast,
            isCurrent: isCurrent,
            isLast: i == steps.length - 1,
          );
        }).toList(),
      ),
    );
  }

  int _statusIndex(String status, bool hasAlbum) => switch (status) {
    'interested' => 0,
    'admin_contacted' => 1,
    'confirmed' => 2, // we don't actually know if deposit collected from app side; admin tracks it
    'completed' => hasAlbum ? 5 : 4,
    _ => 0,
  };
}
```

### 6.4 Action card per status

```dart
class _ActionCard extends StatelessWidget {
  final BirthdayReservation reservation;
  @override
  Widget build(BuildContext c) {
    final actionContent = switch (reservation.status) {
      'interested' => "We'll WhatsApp you within 24 hours to confirm available dates.",
      'admin_contacted' => "Our team has been in touch. Check your WhatsApp.",
      'confirmed' => "Confirmed for ${_formatDate(reservation)}. See you then!",
      'completed' => reservation.albumReadyAt == null
        ? "Album coming in 3-5 days. We'll let you know!"
        : "Tap below to see the album.",
      _ => null,
    };

    if (actionContent == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Text(actionContent, style: AppTextStyles.body(c)),
          if (reservation.status == 'completed' && reservation.albumReadyAt != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: "View album →",
                onPressed: () => context.push('/birthday/album/${reservation.id}'),
              ),
            ),
          ],
          if (reservation.status == 'confirmed') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: PhosphorIcon(PhosphorIcons.calendar()),
                label: const Text("Add to calendar"),
                onPressed: () => _addToCalendar(reservation),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

## 7. Post-Event Album — `lib/features/birthday/birthday_album_screen.dart`

### 7.1 Layout

```
┌─────────────────────────────────────┐
│ APP BAR                             │
│ [back] Aarav's birthday    [share]  │
├─────────────────────────────────────┤
│ HERO COVER (~35% height)            │
│ [admin-picked best photo, full]     │
│ Aarav's 6th birthday                │
│ March 15 • Hero Adventure           │
├─────────────────────────────────────┤
│ BIRTHDAY HERO CARD SECTION          │
│ "A special card for Aarav"          │
│ "Earned only on his birthday"       │
│ [Card centered, foil treatment]     │
│ [Save to Adventure] [Share card]    │
├─────────────────────────────────────┤
│ PHOTO GRID                          │
│ "12 photos from the celebration"    │
│ [3-column grid of thumbnails]       │
├─────────────────────────────────────┤
│ STICKY FOOTER                       │
│ [Download all]    [Share album]     │
└─────────────────────────────────────┘
```

### 7.2 Implementation

```dart
class BirthdayAlbumScreen extends ConsumerWidget {
  final String reservationId;
  @override
  Widget build(BuildContext c, WidgetRef ref) {
    final reservation = ref.watch(reservationByIdProvider(reservationId));
    final photos = ref.watch(birthdayPhotosProvider(reservationId));

    return Scaffold(
      appBar: AppBar(
        title: reservation.value != null
          ? Text("${(ref.watch(childByIdProvider(reservation.value!.childId)).valueOrNull?.name ?? '')}'s birthday")
          : const Text("Album"),
        actions: [
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.shareNetwork()),
            onPressed: () => _shareAlbum(reservationId),
          ),
        ],
      ),
      body: reservation.when(
        data: (r) => CustomScrollView(
          slivers: [
            // Hero cover photo
            SliverToBoxAdapter(child: _HeroCover(reservation: r, photos: photos.value ?? [])),

            // Hero card section
            if (r.birthdayHeroCardId != null)
              SliverToBoxAdapter(child: _BirthdayCardSection(cardId: r.birthdayHeroCardId!)),

            // Photo grid
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: photos.when(
                data: (ps) => _PhotoGrid(photos: ps),
                loading: () => const SliverToBoxAdapter(child: CircularProgressIndicator()),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorScreen(code: 'E-ALB', userMessage: 'Couldn\'t load'),
      ),
      bottomSheet: _AlbumFooter(reservationId: reservationId),
    );
  }
}
```

### 7.3 Photo grid

```dart
class _PhotoGrid extends StatelessWidget {
  final List<BirthdayPartyPhoto> photos;
  @override
  Widget build(BuildContext c) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4,
      ),
      delegate: SliverChildBuilderDelegate(
        (c, i) => GestureDetector(
          onTap: () => _openLightbox(c, photos, i),
          onLongPress: () => _showPhotoMenu(c, photos[i]),
          child: photos[i].isInAlbum
            ? CachedNetworkImage(
                imageUrl: photos[i].photoUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.lightBorder),
              )
            : Container(
                color: AppColors.lightBorder,
                alignment: Alignment.center,
                child: Text("Hidden",
                  style: AppTextStyles.caption(c, color: Colors.white)),
              ),
        ),
        childCount: photos.length,
      ),
    );
  }
}
```

### 7.4 Lightbox

Fullscreen swipeable photo viewer with caption + share.

```dart
class PhotoLightbox extends StatefulWidget {
  final List<BirthdayPartyPhoto> photos;
  final int initialIndex;

  @override
  State<PhotoLightbox> createState() => _PhotoLightboxState();
}

class _PhotoLightboxState extends State<PhotoLightbox> {
  late final PageController _controller;
  late int _currentIndex;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showChrome ? AppBar(
        backgroundColor: Colors.black,
        title: Text("${_currentIndex + 1} of ${widget.photos.length}",
          style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: PhosphorIcon(PhosphorIcons.shareNetwork(), color: Colors.white),
            onPressed: _shareCurrent,
          ),
        ],
      ) : null,
      body: GestureDetector(
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.photos.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (_, i) => InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(imageUrl: widget.photos[i].photoUrl),
            ),
          ),
        ),
      ),
      bottomSheet: _showChrome && widget.photos[_currentIndex].caption != null
        ? Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Text(widget.photos[_currentIndex].caption!,
              style: const TextStyle(color: Colors.white)),
          )
        : null,
    );
  }
}
```

### 7.5 Share

Two share modes:
1. **Single photo share** — direct image share via system share sheet.
2. **Album share** — generates a Branch deep link (`https://diariesclub.app.link/album/:id`) that opens the album for friends/family. Friends without the app see a web view of the album hosted at `diariesclub.com/album/:id` (Edge Function).

---

## 8. Hero-Progression Triggered Birthday Nudges

When a child crosses a stage transition (handled in Session 6's `xp_credit_with_split`), check if their birthday is approaching:

```sql
-- After applying XP and detecting stage transition in xp_credit_with_split:
IF jsonb_array_length(v_transitions) > 0 THEN
  -- Check if birthday within 90 days and no reservation yet
  DECLARE
    v_dob DATE;
    v_days_until INTEGER;
    v_already_sent BOOLEAN;
  BEGIN
    SELECT date_of_birth INTO v_dob FROM children WHERE id = p_child_id;

    -- Compute days until next birthday
    v_days_until := (
      DATE_PART('year', AGE(NOW())) * 365 +
      EXTRACT(DOY FROM (DATE_PART('year', NOW())::TEXT || '-' ||
        DATE_PART('month', v_dob)::TEXT || '-' ||
        DATE_PART('day', v_dob)::TEXT)::DATE) -
      EXTRACT(DOY FROM CURRENT_DATE)
    );

    -- Within window AND no active reservation AND haven't sent this trigger yet
    SELECT COALESCE(hero_progression_trigger_sent, false) INTO v_already_sent
    FROM birthday_journey_state WHERE child_id = p_child_id;

    IF v_days_until BETWEEN 14 AND 90
      AND NOT v_already_sent
      AND NOT EXISTS(SELECT 1 FROM birthday_reservations
        WHERE child_id = p_child_id AND status IN ('interested','admin_contacted','confirmed'))
    THEN
      INSERT INTO notifications(family_id, type, title, body, deep_link, reference_id)
      VALUES (
        p_family_id, 'birthday_hero_progression_trigger',
        v_child_name || ' just hit a new milestone!',
        'Their birthday is in ' || v_days_until || ' days. Want to celebrate at Diaries?',
        '/birthday', p_child_id
      );

      -- Mark sent
      INSERT INTO birthday_journey_state(child_id, hero_progression_trigger_sent)
      VALUES (p_child_id, true)
      ON CONFLICT (child_id) DO UPDATE SET hero_progression_trigger_sent = true;
    END IF;
  END;
END IF;
```

---

## 9. Files to Create

```
lib/
└── features/
    └── birthday/
        ├── birthday_discovery_screen.dart
        ├── birthday_packages_screen.dart
        ├── package_detail_screen.dart
        ├── reservation_status_screen.dart
        ├── birthday_album_screen.dart
        ├── widgets/
        │   ├── birthday_card.dart                  // Home tab variant
        │   ├── journey_progress_bar.dart
        │   ├── package_card.dart
        │   ├── badge.dart
        │   ├── hero_theme_chip.dart
        │   ├── status_header.dart
        │   ├── reservation_summary_card.dart
        │   ├── pipeline_timeline.dart
        │   ├── pipeline_step.dart
        │   ├── action_card.dart
        │   ├── party_details_card.dart
        │   ├── contact_card.dart
        │   ├── hero_cover.dart
        │   ├── birthday_card_section.dart
        │   ├── photo_grid.dart
        │   ├── photo_lightbox.dart
        │   └── album_footer.dart
        └── providers/
            ├── birthday_card_state_provider.dart
            ├── reservation_by_id_provider.dart
            ├── birthday_photos_provider.dart
            └── birthday_packages_provider.dart
```

---

## 10. Acceptance Tests

```
TEST 1 — Discovery → Packages → Detail flow
  1. Tap birthday card on Home (or notification)
  2. Discovery screen loads with progress bar
  3. Tap "See packages" → 3 package cards visible
  4. Tap a package → detail screen with all sections

TEST 2 — Reserve interest
  1. On detail screen, fill preferences (rough month, kids, adults)
  2. Tap "Reserve interest"
  3. RPC succeeds → /birthday/status/:id
  4. Status header shows "Reservation request received"
  5. Pipeline shows step 1 done, step 2 pulsing
  6. Notification added: "We'll WhatsApp you within 24 hours"

TEST 3 — Reservation status updates via Realtime
  1. On status screen
  2. Admin marks status='admin_contacted' in DB
  3. Status flips within 5s
  4. New status header shown

TEST 4 — Confirmed party day
  1. Status='confirmed', slot_date=today
  2. Card shows "It's [child]'s birthday!" with celebration anim
  3. "Get directions" + "Call venue" actions visible

TEST 5 — Hero card auto-award on completion
  1. Status='confirmed', admin marks completed via admin RPC
  2. birthday_reservation_complete fires:
     - hero_card_collection row added (birthday-exclusive)
     - xp_events row added (birthday_hosted, +1000 split)
     - notifications row: "Thank you for celebrating"
  3. Adventure tab → cards screen → birthday card visible with cake icon
  4. Reservation status screen → "Album coming in 3-5 days"

TEST 6 — Album publish
  1. Admin uploads photos via admin web (Session 11)
  2. Admin clicks "Publish album" → birthday_album_publish RPC
  3. notifications row: "Album is ready!"
  4. Birthday card on Home morphs to "View album"
  5. Tap → album screen with photos + birthday hero card

TEST 7 — Photo lightbox
  1. Tap a photo in album grid
  2. Fullscreen viewer opens
  3. Swipe left/right between photos
  4. Tap to toggle chrome
  5. Share button opens system share sheet

TEST 8 — Hide a photo (parent control)
  1. Long-press a photo thumbnail
  2. Menu: "Hide this photo"
  3. is_in_album set to false in DB
  4. Photo replaced with grey "Hidden" placeholder
  5. Other family members (same family_id) also see it hidden

TEST 9 — Hero-progression-triggered nudge
  1. Child age has birthday in 60 days, no reservation
  2. Birthday journey state has hero_progression_trigger_sent = false
  3. Submit reflection that causes Rafi: Explorer → Adventurer
  4. Stage transition processed
  5. Notification fires: "Aarav just hit a new milestone! Birthday in 60 days..."
  6. hero_progression_trigger_sent = true
  7. Repeat: subsequent stage transitions don't fire this nudge again

TEST 10 — Cancel reservation
  1. Status='interested' or 'admin_contacted'
  2. Tap menu → Cancel reservation
  3. Confirmation dialog
  4. Confirm → status='cancelled', cancellation_reason captured
  5. Returns to Discovery screen

TEST 11 — Existing-reservation guard
  1. Family already has interested/admin_contacted/confirmed reservation for child
  2. Try to create another → RPC raises 'reservation_exists'
  3. Show error sheet: "You already have an active reservation. View status?"

TEST 12 — Album share via Branch
  1. Status='completed', album_ready_at set
  2. Tap Share Album button
  3. Branch deep link generated
  4. Share sheet opens with link + preview text
```

---

## 11. Open Items for Founder

- [ ] Confirm 3 birthday package final pricing: ₹15,000 / ₹25,000 / ₹45,000
- [ ] Confirm 3 reference photos per package (collect post-launch from first parties)
- [ ] Approve "How booking works" copy (3-step explanation)
- [ ] Approve "Not included" transparency list per package
- [ ] Confirm deposit amounts admin will collect offline: ₹5K / ₹8K / ₹15K (or other)
- [ ] Decide: should "Most Booked" badge be data-driven (top reservations count) or admin-flagged manually? (For v1: admin flag is fine)
- [ ] Approve birthday-exclusive hero card art (assets 2.4 — 4 cake-themed cards, one per hero)
- [ ] Confirm "auto-cancel after 72h if no admin contact" rule (or change duration)
- [ ] Decide if Branch album share should require app or open in web (recommend web for max reach)

---

## What's NOT in this session

- Admin web for managing birthday pipeline (Session 11)
- Admin photo uploader (Session 11)
- Razorpay deposit (REMOVED by decision)
- Staff app birthday photo capture (REMOVED by decision)
- Birthday journey D-N cron triggers (Session 13 — Edge Functions)
- Birthday hero card share image generator Edge Function (Session 13)
