# Birthday Booking Flow — Wireframe Briefs

> **How to use:** Open Claude design with your "Diaries Club Design System" file loaded. For each screen below, copy the entire brief (from "## SCREEN N" down to the next divider) and paste as a single message. Generate the wireframe, iterate, then move to the next screen.
>
> All five screens form a single connected flow: **Discovery → Packages → Detail → Status → Album**.

---

## Common context (Claude design will need this once at the start of your session)

```
I am building wireframes for "Diaries Club" — a Flutter mobile app for a kids
play area in Hyderabad. Use the Diaries Club Design System I have loaded.

Platform: iOS + Android, mobile only (no tablet, no web).
Viewport: 390×844 (iPhone reference frame).
Audience: parents booking birthday parties for their kids (ages 3–10).
Tone: warm, premium, celebratory but not cheesy.

Apply system tokens, components, and typography throughout. If a component
I describe doesn't exist in the system, propose how to extend it (don't
invent a one-off style).

Hero traits used in this flow:
  - Rafi (Brave, coral red)
  - Ellie (Kind, sky blue)
  - Gerry (Curious, amber)
  - Zena (Creative, green)
A "hero theme" means the package's visual is anchored on one of these heroes
(or "mixed" for all four).

Currency formatting: Indian comma format with ₹ symbol (e.g., ₹15,000 not ₹15000).
Generate light mode wireframes. (Dark mode comes later.)
```

---

## SCREEN 1 — Birthday Discovery / Hub

**Paste this into Claude design:**

```
Generate wireframe: "Birthday Discovery" screen.

PURPOSE
This is the landing screen when a parent taps the persistent birthday card on the
Home tab. It's the entry point to the entire birthday booking funnel. The parent
arrives here interested but not yet committed. The screen's job is to make the
party feel imaginable — turn "should we?" into "let's see what's available."

ROUTE: /birthday
ENTRY POINTS:
  - Home tab persistent birthday card (always visible if child has birthday in next 90 days)
  - Hero progression notification ("Aarav reached Champion — celebrate at his birthday?")
  - Day-minus-90, -60, -30, -14, -7, -3 push notifications

LAYOUT (top to bottom):

1. APP BAR
   - Back arrow (left)
   - Title: "Birthday"
   - No right action

2. HERO SECTION (large, ~30% of screen height)
   - Background: warm gradient (use system color: navy-to-gold or similar celebration palette)
   - Centered content:
     - Child's photo in circular avatar (96×96), warm border ring
     - Child's first name in display text: "Aarav's birthday"
     - Subtitle in body large: "32 days to go" (auto-calculated from DOB)
     - Confetti or subtle celebratory decoration (use system illustration style, not emoji)

3. JOURNEY PROGRESS BAR
   - Horizontal stepper showing 6 milestones: D-90, D-60, D-30, D-14, D-7, Day 0
   - Past milestones filled (gold), current pulsing, future muted
   - Caption below: "We're here →" pointing at current

4. PRIMARY CTA CARD (full width, prominent)
   - Background: navy with gold accent
   - Headline: "Plan Aarav's birthday with us"
   - Body: "3 packages, every detail handled — from decor to cake to host."
   - Button: "See packages" → navigates to /birthday/packages
   - Hero illustration in card right side: small group of all 4 heroes around a cake

5. PACKAGE TEASER ROW (horizontal scroll, 3 cards)
   - Each card ~140×180:
     - Package name ("Birthday Basics", "Hero Adventure", "Legendary")
     - Hero theme indicator (small avatar)
     - Starting price ("from ₹15,000")
     - Tap → /birthday/packages with that package preselected

6. SOCIAL PROOF STRIP
   - Caption: "Recently celebrated"
   - 3 anonymised mini cards: "A.'s birthday — 24 happy kids", "R.'s birthday — Hero Adventure theme"
   - Greyscale photos with light overlay

7. SECONDARY CTA (de-emphasized, bottom)
   - Text link: "Have questions? Chat with our team"
   - Tap → opens WhatsApp deep link

8. BOTTOM NAV
   - Standard 4-tab bar (Home / Club / Adventure / Profile)
   - Home tab visually active (this screen is reached from Home)

STATES TO WIREFRAME (3 variants):

VARIANT A — Default discovery (no reservation yet)
  - Everything above, journey at "we're here"

VARIANT B — Reservation already exists
  - Hero section replaced with: "Aarav's birthday is reserved!"
  - Subtitle: "March 15, 4:00 PM • Hero Adventure package"
  - Primary CTA changes to: "View reservation status"
  - Package teaser row hidden
  - Social proof strip stays

VARIANT C — Birthday > 90 days away
  - Hero section subtitle: "Coming up in 4 months"
  - Primary CTA changes to: "Save the date — see packages anyway"
  - All other sections same

INTERACTION NOTES
  - Pull-to-refresh updates days-to-go counter
  - Tapping child's photo opens edit child screen (existing flow)
  - Hero illustration should feel hand-drawn, not corporate
  - All transitions should be 300ms standard ease

COPY VOICE
Warm, second-person, no exclamation marks except in headlines. Treat the parent
as a co-conspirator planning a surprise, not a customer being upsold.
```

---

## SCREEN 2 — Birthday Packages Browse

**Paste this into Claude design:**

```
Generate wireframe: "Birthday Packages" browse screen.

PURPOSE
The parent sees all 3 packages side-by-side and chooses one to learn more.
Equal visual weight for theme + price + inclusions per your direction —
this is a comparison screen, not a hard-sell screen.

ROUTE: /birthday/packages
ENTRY: Tap "See packages" CTA from Birthday Discovery screen.

LAYOUT (top to bottom):

1. APP BAR
   - Back arrow
   - Title: "Choose a package"
   - No right action

2. SUB-HEADER STRIP
   - Body text: "All packages include 2 hours of exclusive play time, decor,
     food, and a host. Pick the experience that fits."
   - Slightly muted color, 2 lines max

3. PACKAGE CARDS — STACKED VERTICALLY (not horizontal scroll, full width each)
   Three cards, equal visual weight as decided:

   CARD A — "Birthday Basics" (₹15,000)
   CARD B — "Hero Adventure" (₹25,000) — MARKED "Most Booked"
   CARD C — "Legendary Birthday" (₹45,000) — MARKED "Premium"

   EACH CARD STRUCTURE (all three identical layout, different content):

   ┌─────────────────────────────────────┐
   │  HERO IMAGE STRIP (top, ~120 high)  │
   │  - Themed illustration showing      │
   │    decor + hero character           │
   │  - Tier badge top-right corner      │
   │  - For Hero Adventure: Rafi promo   │
   │  - For Legendary: all 4 heroes      │
   │  - For Basics: confetti, no hero    │
   ├─────────────────────────────────────┤
   │  NAME & PRICE ROW                   │
   │  "Birthday Basics"     ₹15,000      │
   │  caption: "from"  small,            │
   │  navy bold             gold large   │
   ├─────────────────────────────────────┤
   │  THEME ROW                          │
   │  Avatar chip(s) + label             │
   │  e.g., [Rafi] "Brave Hero theme"    │
   │  or [4 mini] "Mixed heroes"         │
   ├─────────────────────────────────────┤
   │  INCLUSIONS LIST (3-4 lines max)    │
   │  ✓ 2hr exclusive play               │
   │  ✓ Themed decor                     │
   │  ✓ Kids' meal + party platter       │
   │  ✓ 1 host                           │
   │  (use system check icon, not emoji) │
   ├─────────────────────────────────────┤
   │  CAPACITY ROW                       │
   │  "Up to 15 kids • 10 adults"        │
   │  caption text                        │
   ├─────────────────────────────────────┤
   │  PRIMARY BUTTON                     │
   │  "See details" → /birthday/         │
   │  reserve/:packageId                 │
   └─────────────────────────────────────┘

   SPACING: 16px gap between cards.

4. BOTTOM HELP STRIP (fixed at bottom or scrolled)
   - Caption: "Not sure? Our team can help you choose."
   - Text link: "Chat on WhatsApp"

5. NO bottom nav on this screen (it's a focused decision flow — full screen attention)

STATES (just one main state, but include these edge cases):
  - All 3 packages active and bookable (default)
  - One package marked "Currently unavailable" — entire card muted, button disabled with caption "Back soon"

INTERACTION NOTES
  - Cards are NOT tappable as a whole — only the "See details" button. This
    prevents accidental navigation while scrolling.
  - "Most Booked" badge is gold pill, top-right of card image
  - "Premium" badge is navy pill, top-right
  - Scroll behavior: standard, no parallax

COPY VOICE
Plain, factual, confident. No FOMO. Trust the parent to pick what fits.
```

---

## SCREEN 3 — Package Detail + Reserve Interest

**Paste this into Claude design:**

```
Generate wireframe: "Package Detail" screen with reserve action.

PURPOSE
This is where intent converts to a reservation. The parent has picked a package
from the browse screen and now sees the full picture before committing. We
collect minimum info (just guest counts and a preferred week) and submit
"reserve interest" — admin schedules the actual date via WhatsApp afterward.

NO IN-APP DATE/TIME PICKER. Admin handles slot scheduling outside the app.

ROUTE: /birthday/reserve/:packageId
ENTRY: Tap "See details" from a package card on Packages browse.

LAYOUT (top to bottom):

1. APP BAR
   - Back arrow
   - Title: package name (e.g., "Hero Adventure")
   - Right action: heart icon (save for later) — secondary, optional

2. HERO MEDIA SECTION (~45% screen height)
   - Large themed illustration full bleed
   - For Hero Adventure: Rafi mid-action, decor in background
   - Image carousel dots below (3-5 reference photos from past parties)
   - Photos should feel like real-event documentation, anonymised

3. PRICE BAR (sticky below hero media, scrolls with content but always visible above CTA)
   - Left side: "₹25,000"  (display text size, gold)
     - Below in caption: "All-inclusive • No surprises"
   - Right side: capacity chip
     - "20 kids • 15 adults max"

4. WHAT'S INCLUDED (the heart of the page)
   - Section header "What's included"
   - 6-8 inclusion rows, each with icon + title + 1-line description:
     ✓ 2 hours exclusive play time
        "Whole play area, just for your guests"
     ✓ Hero Adventure decor
        "Themed setup with [Rafi] as the star"
     ✓ FIT party platter for kids
        "Healthy snacks our kids actually love"
     ✓ Coffee Diaries spread for adults
        "Beverages and savouries while you relax"
     ✓ Themed birthday cake (1kg)
        "Custom design, dietary needs accommodated"
     ✓ One trained host
        "Runs games, manages timing, takes photos"

5. NOT INCLUDED (transparent honesty)
   - Section header "Not included"
   - 2-3 rows, muted style:
     – Return gifts
     – Custom photographer (we have one in Legendary)
     – Outside food

6. WHAT HAPPENS NEXT (sets expectations for the no-picker model)
   - Section header "How booking works"
   - Numbered list (3 steps):
     1. Tell us roughly when (a week or two), how many kids, how many adults
     2. Our team will WhatsApp you within 24 hours with available dates and timings
     3. We confirm the date and collect a deposit (₹8,000 for this package)

7. PREFERENCES FORM (the only input the parent gives)
   - Section header "Your preferences"
   - Field 1: "Roughly when?" — text field with placeholder "e.g., last weekend of March"
     OR a simple month picker (just month, no specific date)
   - Field 2: "Number of kids?" — stepper, default 15, min 5 max 25
   - Field 3: "Number of adults?" — stepper, default 10, min 0 max 20
   - Field 4 (optional): "Anything special we should know?" — multiline text, placeholder "Allergies, themes, surprises..."

8. RESERVE CTA (sticky bottom bar, always visible)
   - Full-width button, navy with gold text
   - Label: "Reserve interest"
   - Below button in caption: "No payment yet — we'll WhatsApp you to confirm"

9. NO bottom nav (focused flow)

POST-RESERVE STATE (after parent taps "Reserve interest"):
  - Button transforms to loading spinner
  - On success: toast "Reservation request sent! Our team will WhatsApp you within 24 hours."
  - Auto-navigate to Reservation Status screen (next wireframe)

STATES TO WIREFRAME (just two):

VARIANT A — Default state (form empty/default values)
VARIANT B — Form filled, ready to submit
  - All preference fields populated
  - Button shows engaged state

INTERACTION NOTES
  - Image carousel: swipeable, dots are taps too
  - Steppers: + / – buttons with haptic feedback
  - "Roughly when" field is intentionally vague — admin will refine
  - The "Not included" section is critical for trust — don't shrink it

COPY VOICE
Set expectations clearly. The parent should leave this screen knowing exactly
what they're signing up for and what happens next. Use "we" for the venue,
"you" for the parent.
```

---

## SCREEN 4 — Reservation Status

**Paste this into Claude design:**

```
Generate wireframe: "Reservation Status" tracking screen.

PURPOSE
Once a parent has reserved interest, they need to track where their booking
stands. This screen replaces uncertainty with visibility — it shows what's
happened, what's pending, and what's next, without forcing the parent to
chase the team.

ROUTE: /birthday/status/:reservationId
ENTRY:
  - Auto-navigate after reserve interest submission
  - Tap "View reservation status" from Birthday Discovery (Variant B)
  - Tap deep link in WhatsApp message from admin
  - Tap birthday-related notification

LAYOUT (top to bottom):

1. APP BAR
   - Back arrow
   - Title: "Your reservation"
   - Right action: 3-dot overflow menu (Cancel reservation / Help)

2. STATUS HEADER CARD (large, dominant)
   - Background: depends on status (see states below)
   - Content varies by status — see STATES section

3. RESERVATION SUMMARY CARD (below status)
   - "Hero Adventure Package"
   - Child name + birthday avatar
   - "Aarav's 6th birthday"
   - Date row: confirmed date OR "We'll confirm with you" if pending
   - Time row: confirmed time OR "—"
   - Guests: "20 kids • 15 adults"

4. PIPELINE TIMELINE (vertical stepper showing all stages)
   Steps:
     1. ✓ Interest received (always done if you're on this screen)
     2. ⏳ Team reaching out (pending or done)
     3. ⏳ Date confirmed (pending or done)
     4. ⏳ Deposit paid (pending or done)
     5. ⏳ Confirmed by team (pending or done)
     6. ⏳ Party day (the big one — special styling when reached)
     7. ⏳ Album ready (post-event)
   - Past steps: filled checkmark, gold
   - Current: pulsing dot, navy
   - Future: outlined dot, muted

5. ACTION CARD (varies by status — see states below)

6. PARTY DETAILS CARD (only visible after status = confirmed)
   - Title: "Party details"
   - Date, time, slot duration
   - Number of guests
   - Package inclusions (collapsed list, expandable)
   - "Edit details" link → opens WhatsApp to admin

7. CONTACT CARD (always visible)
   - "Need to talk to us?"
   - WhatsApp button (full width, green)
   - Phone button (full width, navy outline)

8. CANCEL RESERVATION (very bottom, de-emphasized)
   - Text link only, muted color: "Cancel this reservation"
   - Tap opens confirmation sheet

NO bottom nav.

STATES TO WIREFRAME (5 variants — this is the most important one):

VARIANT A — Just submitted (status: 'reserved')
  - Status header: gold gradient
  - Status text: "Interest received — we'll be in touch within 24 hours"
  - Subtitle: "Submitted just now"
  - Pipeline: step 1 done, step 2 pulsing
  - Action card: "We'll WhatsApp you within 24 hours to confirm available dates."
  - Party details card: HIDDEN

VARIANT B — Admin contacted, deposit pending (status: 'deposit_paid' is wrong here;
             use 'admin_contacted' meaning step 2 done, step 3 in progress)
  - Status header: navy
  - Status text: "Date proposed — pay deposit to confirm"
  - Subtitle: "Our team proposed: Saturday March 15, 4:00 PM"
  - Pipeline: steps 1-2 done, step 3 pulsing
  - Action card: BIG button "Pay ₹8,000 deposit" in gold
    - Below: "Once paid, your slot is locked in"
  - Party details: HIDDEN

VARIANT C — Confirmed (status: 'confirmed')
  - Status header: green gradient — celebratory
  - Status text: "You're confirmed! 🎉"
       (this is one of the very few places we use an emoji — celebration moment)
  - Subtitle: "Saturday March 15, 4:00 PM — see you then"
  - Pipeline: steps 1-5 done, step 6 (party day) pulsing
  - Action card: "Add to calendar" button
  - Party details card: VISIBLE, expanded by default

VARIANT D — Party day (status: 'confirmed' on the actual date)
  - Status header: full celebration treatment, animated
  - Status text: "It's Aarav's birthday! 🎉"
  - Subtitle: "We're ready when you are"
  - Pipeline: steps 1-5 done, step 6 highlighted
  - Action card: "Get directions" + "Call venue"

VARIANT E — Completed, album processing (status: 'completed', album_ready_at = null)
  - Status header: muted celebration
  - Status text: "Thank you for celebrating with us"
  - Subtitle: "Album coming in 3-5 days"
  - Pipeline: steps 1-6 done, step 7 pulsing
  - Action card: "Got feedback? Tell us" → simple feedback form

VARIANT F — Album ready (status: 'completed', album_ready_at set)
  - Status header: full celebration palette
  - Status text: "Album is ready!"
  - Subtitle: "Aarav's birthday photos + a special hero card"
  - Pipeline: all 7 steps done
  - Action card: BIG button "View album" → /birthday/album/:reservationId
  - Cancel option: HIDDEN (event is over)

INTERACTION NOTES
  - Status header uses Lottie animation for celebration variants (B, C, D, F)
  - Pipeline timeline updates in real-time via Supabase Realtime subscription
  - Pull-to-refresh on the whole screen
  - Cancel sheet has firm copy: "Are you sure? Your deposit (if paid) is refundable up to 7 days before the date."

COPY VOICE
Reassuring without being saccharine. Treat each milestone as a real moment
worth marking, but never inflate it.
```

---

## SCREEN 5 — Post-Event Album

**Paste this into Claude design:**

```
Generate wireframe: "Birthday Album" screen.

PURPOSE
This is the post-event amplification artifact — the parent shows up D+7 to find
a curated album of party photos AND a birthday-exclusive hero card their child
earned. Both are shareable, which is the whole point: the parent posts on
WhatsApp/Instagram, and that becomes our best marketing.

ROUTE: /birthday/album/:reservationId
ENTRY:
  - Tap "View album" from Reservation Status (Variant F)
  - Tap album-ready notification (D+7)

LAYOUT (top to bottom):

1. APP BAR
   - Back arrow
   - Title: "Aarav's birthday"
   - Right action: SHARE icon (system share sheet) — primary action

2. HERO COVER (~35% height)
   - Large featured photo (admin-picked best shot from party)
   - Overlay text bottom-left:
     - "Aarav's 6th birthday"
     - "March 15 • Hero Adventure"
   - Soft gradient over photo bottom for text readability

3. BIRTHDAY HERO CARD SECTION (the special exclusive)
   - Section header "A special card for Aarav"
   - Caption: "Earned only on his birthday"
   - Centered card visual:
     - Birthday-exclusive hero card (use system hero card component, with
       "BIRTHDAY EDITION" foil/gold treatment)
     - Card hero matches package theme (Hero Adventure → Rafi card)
     - Tap to flip / view fullscreen
   - Below card: row of two buttons:
     - "Save to Adventure" (already in collection, but reinforces) — secondary
     - "Share card" — primary — opens share sheet with card image preset

4. PHOTO GRID
   - Section header "Party photos"
   - Caption: "12 photos from the celebration"
   - 3-column grid, square thumbnails
   - Tap any thumbnail → opens fullscreen lightbox with swipe

5. LIGHTBOX (separate state, see Variant B below)

6. SHARE FOOTER (sticky at bottom)
   - Two buttons side-by-side:
     - "Download all" (downloads zip to device)
     - "Share album" (opens system share with link to web-hosted album)

NO bottom nav.

STATES TO WIREFRAME:

VARIANT A — Album view (default)
  - Everything described above

VARIANT B — Lightbox (photo fullscreen)
  - Black background
  - Full photo, swipe left/right between photos
  - Top bar: close X (left), photo counter (center, "3 of 12"), share icon (right)
  - Bottom bar: caption (admin-added, e.g., "Cake time!")
  - Tap photo to hide/show chrome

VARIANT C — Photo hidden by parent
  - Parent can long-press a thumbnail → "Hide this photo" option
  - Hidden photos show in grid as muted placeholder with "Hidden" caption
  - Tap to "Show" again

INTERACTION NOTES
  - Share share share — every share button is one tap
  - Hero card share image is pre-composed by Edge Function (square format with watermark)
  - Album share creates a Branch link to the web-hosted version (so non-app friends/family can see it)
  - Photos load progressively (low-res first, then full)
  - "Download all" zips client-side; show progress toast

COPY VOICE
Celebratory but final — this is a closing chapter. Don't push for next steps;
let the album speak for itself. The next-birthday push happens elsewhere.
```

---

## After all 5 screens are wireframed

Once you have wireframes for all 5, here's what to validate before moving to Tier 2:

**Cross-screen flow check:**
- Can a parent get from Home tab → Album in fewer than 6 taps?
- Does each screen's primary CTA lead to the next screen in the funnel?
- Is the back navigation always reversible (no lost state)?

**Edge case audit:**
- What does Birthday Discovery look like for a child whose birthday is **today**?
- What does Status look like if the parent reserved but never paid the deposit and the 24h window expired?
- What does the album look like if zero photos were uploaded? (Probably a "Photos coming soon" empty state.)

**Design system validation:**
- Did Claude design have to invent any components? If so, those need to be added to the system file before you build.
- Are color/spacing/typography tokens being used everywhere, or did anything sneak in as a one-off?

**Once validated, send the wireframes back here and I'll fold the screen-by-screen specs into Session 9 (Birthday Funnel) of Tier 2 with references to your wireframe files.**
