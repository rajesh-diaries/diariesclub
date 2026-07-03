# Safari Club Tab Redesign

## Goal
Turn the Safari tab into a clear, warm information + interest-capture page for parents whose children are not yet enrolled in Safari Club.

## Audience
Parents of 2–5 year olds browsing the app, wondering what Safari Club is and whether to express interest.

## Design

### 1. Admin-configurable banner (keep existing)
- Reuse the existing `SafariAnnouncementCard` at the very top.
- Default text: **"Safari Club — a morning club where little explorers build Brave, Curious, Kind & Creative traits through play. Coming soon."**
- No backend change.

### 2. Hero
- **Title:** Safari Club
- **Subtitle:** A morning club
- **Badges:** Ages 2–5 · Mon–Fri · 9:30 AM – 12:30 PM
- **Background:** Warm safari/jungle illustration or soft gradient.
- **Primary CTA:** "I’m interested" (scrolls to the interest form).

### 3. What is it?
- Safari Club is **not a school, not a Montessori, and not an activity class**.
- It is a **trait-first play space** for 2–5 year olds inside Play Diaries.
- It follows **The Safari Method** — a play-first approach where children grow the four life traits they need most: **Brave, Curious, Kind, and Creative**.
- In a world where knowledge is one click away, we believe children need relationships, confidence, and character far more than another worksheet.

### 4. Why Safari Club?
- 3 benefit cards with icons:
  - **Built around four life traits** — Every session grows Brave, Curious, Kind, and Creative through guided play.
  - **Real-world skills through play** — Sharing, communication, routines, independence, and empathy learned naturally.
  - **Real skills for life — traits they keep forever** — We focus on growth and abilities that stay with children long after they leave the classroom.

### 5. A typical morning
- Vertical timeline inside the play area (no outdoor step).
- Framed around learning through play while building the four traits.
- Example:
  - 9:30 AM — Arrival & free play
  - 10:00 AM — Guided play activity (sensory / creative / social)
  - 11:00 AM — Snack & story circle
  - 11:30 AM — Movement & character-trait game
  - 12:15 PM — Wind-down
  - 12:30 PM — Pickup

### 6. The Four Traits
- Compact cards using the four heroes:
  - Brave like Rafi
  - Curious like Gerry
  - Kind like Ellie
  - Creative like Zena
- Each with a one-line description tied to Safari Club activities.

### 7. FAQ
- Collapsible items (5):
  - **Is this a school or Montessori program?** — No. Safari Club is a play-based morning club using The Safari Method. We focus on character traits and life skills, not academics.
  - **How is this different from activity classes?** — Most activity classes teach one skill. Safari Club uses play to build the four traits that help in every part of life.
  - **What should my child bring?** — Just a water bottle and a small snack if needed. We handle the activities.
  - **Can we visit before enrolling?** — Yes. We’ll invite interested families for a visit once enrollment opens.
  - **When does Safari Club start?** — We’re preparing to launch soon. Tap “I’m interested” to be the first to know.

### 8. Interest form
- Fields:
  - Parent name
  - Phone
  - Child name
  - Child age
  - Optional note
- Submit inserts into existing `safari_waitlist` table.
- Success state: "Thanks for your interest — we’ll reach out when enrollment opens."
- CTA label on the button: "I’m interested".

### 9. Footer
- Safari Club · Play Diaries

## Visual style
- Use existing `SafariColors` (soft cream, jungle green, warm accents).
- Rounded cards, friendly hero illustrations, consistent with the rest of the app.

## Data & backend
- Reuse `safari_waitlist` table — no schema changes.
- Reuse admin-configurable announcement banner — no schema changes.

## Out of scope
- Enrolled-member dashboard
- Payments / enrollment flow
- Scheduling / attendance
- Push notifications for Safari Club
