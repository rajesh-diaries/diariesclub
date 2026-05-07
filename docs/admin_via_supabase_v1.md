# Admin via Supabase Dashboard — v1 soft-launch cheat sheet

The Flutter admin web has known hit-test glitches on Chrome (BUG-031 family — deferred to v1.1). Until that's rebuilt, do common admin operations directly via the Supabase dashboard's **SQL Editor**.

How to use this doc:
- Open https://supabase.com/dashboard/project/stpxtenyatjwcazuxhtu/sql/new
- Paste the SQL block from the relevant section, edit the values, click Run.
- Every section uses the Kondapur venue id `00000000-0000-0000-0000-000000000001`.

---

## 1. Create a workshop

When a workshop is published, customers see it in the Club tab.

```sql
INSERT INTO workshops (
  venue_id, title, description, cover_image_url,
  scheduled_at, duration_minutes,
  age_group_min, age_group_max,
  capacity, spots_remaining, price_paise,
  primary_trait, xp_award,
  status, is_published
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Pottery for Beginners',
  'Hands-on clay shaping, glazing tips, take-home piece.',
  'https://placehold.co/800x500.png?text=Pottery',
  '2026-05-14 16:00:00+05:30',          -- IST start
  90,                                    -- duration in minutes
  6, 10,                                 -- age range
  12, 12,                                -- capacity, spots_remaining (must match on create)
  50000,                                 -- ₹500 in paise
  'zena',                                -- one of rafi / ellie / gerry / zena
  100,                                   -- XP award per attendance
  'upcoming',
  true
);
```

Notes:
- `spots_remaining` must equal `capacity` on create — registrations decrement it.
- `is_published=true` makes it customer-visible immediately. Set false to hold a draft.
- To unpublish a live workshop: `UPDATE workshops SET is_published=false WHERE id='<uuid>';`

---

## 2. Edit pricing / config

`venue_config` is one row per venue. UPDATE the columns you want — leave others unchanged.

```sql
-- Pricing (rupees stored as paise — multiply by 100)
UPDATE venue_config
   SET session_1hr_price_paise              = 80000,    -- ₹800
       session_2hr_price_paise              = 110000,   -- ₹1,100
       session_extension_per_hour_paise     = 80000,
       overtime_per_min_paise               = 200       -- ₹2/min after grace
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- GST percent (decimal, e.g. 18 for 18%)
UPDATE venue_config SET gst_percent = 18, walkin_food_gst_percent = 5
 WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Topup offer quick-picks (JSONB array)
UPDATE venue_config SET topup_offers = '[
  {"amount_paise":50000,  "bonus_paise":2500,  "label":"₹500 + ₹25 bonus", "badge":"5%"},
  {"amount_paise":100000, "bonus_paise":7500,  "label":"₹1000 + ₹75 bonus","badge":"7.5%"},
  {"amount_paise":200000, "bonus_paise":20000, "label":"₹2000 + ₹200 bonus","badge":"10%"}
]'::jsonb
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Cashback %
UPDATE venue_config SET cashback_percent = 5
 WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- XP economy (per-trait amounts)
UPDATE venue_config
   SET xp_per_session_minute    = 1,
       xp_healthy_bite          = 25,
       xp_workshop_attendance   = 100,
       xp_birthday_hosted       = 1000,
       xp_first_session         = 50
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Visit milestones (JSONB array — sorted ascending by visits)
UPDATE venue_config SET visit_milestones = '[
  {"visits":5,  "reward_xp":50,  "reward_paise":0},
  {"visits":10, "reward_xp":100, "reward_paise":10000},
  {"visits":25, "reward_xp":200, "reward_paise":25000}
]'::jsonb
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Birthday flow timing
UPDATE venue_config
   SET birthday_reservation_autocancel_hours = 24,
       birthday_home_card_threshold_days     = 28,
       birthday_interest_ttl_hours           = 48,
       birthday_booking_enabled              = true
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- Session timing
UPDATE venue_config
   SET session_grace_period_minutes         = 5,
       session_grace_max_minutes            = 15,
       session_pre_scan_timeout_minutes     = 15,
       reflection_window_hours              = 24
WHERE venue_id = '00000000-0000-0000-0000-000000000001';

-- App version control (force-update gate)
UPDATE venue_config
   SET ios_min_supported_version     = '1.0.0',
       ios_latest_version            = '1.0.5',
       android_min_supported_version = '1.0.0',
       android_latest_version        = '1.0.5',
       force_update_message          = 'Please update Diaries Club to keep things smooth.'
WHERE venue_id = '00000000-0000-0000-0000-000000000001';
```

Notes:
- All money columns end in `_paise` and are integers (paise = rupees × 100).
- `gst_percent` is the inclusive customer-facing rate; walk-in food GST is exclusive (added on top).
- After saving, the customer app re-reads on next session create / wallet refresh — no deploy needed.

---

## 3. Create + push an announcement

Announcements show in the customer app's announcements feed (home screen). They reach customers via realtime stream — INSERT alone is enough; no separate push call needed for the in-app feed.

```sql
INSERT INTO announcements (
  venue_id, title, body, type,
  cta_label, cta_route, photo_url,
  visible_from, visible_until,
  is_published
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Mother''s Day Special',
  'Free hot chocolate for moms with any 2-hour booking this Sunday.',
  'promo',                              -- one of: workshop / general / event / promo / closure
  'Book now',                           -- CTA label (optional)
  '/club',                              -- in-app deep link (optional)
  'https://placehold.co/800x500.png?text=Mothers+Day',
  '2026-05-08 06:00:00+05:30',
  '2026-05-12 23:59:59+05:30',
  true                                  -- false = draft
);
```

If you want **FCM push** (mobile lock-screen notification) on top of the in-app feed update, that's a separate flow. The push fanout for announcements is **not currently wired** for v1 (only sessions/birthday/recap notifications fire push). If you need a push send during the soft-launch window, paste the announcement title + body into a manual `notifications` row per family, or wait for v1.1 where the announcement → push fanout will be added.

To unpublish: `UPDATE announcements SET is_published=false WHERE id='<uuid>';`

---

## 4. Edit hero card image_url

28 cards exist already (`hero_card_definitions`). Only the `image_url` column should change in v1 (real art swapping in for placeholders).

```sql
-- 1) Upload the PNG to the hero-cards storage bucket via Supabase
--    dashboard → Storage → hero-cards → Upload. Use a slug-style filename
--    like 'birthday-brave.png'.
-- 2) Get the public URL: dashboard shows the row, right-click → Get URL.
-- 3) Update the row:

UPDATE hero_card_definitions
   SET image_url = 'https://stpxtenyatjwcazuxhtu.supabase.co/storage/v1/object/public/hero-cards/birthday-brave.png'
 WHERE name = 'Birthday Brave';

-- See all cards + current URLs:
SELECT hero, name, is_rare, is_birthday_exclusive, image_url
FROM hero_card_definitions
WHERE is_active = true
ORDER BY hero, is_rare, name;
```

Notes:
- The bucket `hero-cards` is public-read (already configured); no signed URL needed.
- Card names + rarity + hero assignment should not change post-launch (would invalidate existing collections).

---

## 5. Add a staff member

Staff sign in via PIN on the staff app. The `pin_hash` column is bcrypt — use the `extensions.crypt` function with a generated salt.

```sql
-- Replace '4729' with the actual 4-digit PIN you want to issue.
INSERT INTO staff (
  venue_id, name, phone, role,
  pin_hash, is_active, force_pin_change
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Anjali Sharma',
  '+919876543210',
  'staff',                              -- one of: staff / manager
  extensions.crypt('4729', extensions.gen_salt('bf')),
  true,
  true                                  -- forces PIN reset on first sign-in
);
```

Notes:
- `extensions.crypt(...)` produces the same `$2a$...` bcrypt format the `verify_staff_pin` RPC expects.
- `force_pin_change=true` makes the staff app prompt for a new PIN on first use.
- To deactivate: `UPDATE staff SET is_active=false WHERE id='<uuid>';`

### Add an admin web user (different table)

Admin web sign-in uses Supabase Auth (email/password). The auth user must already exist in `auth.users` (use Supabase dashboard → Authentication → Users → Add user). Then:

```sql
INSERT INTO admin_users (
  auth_user_id, name, email, role, is_active, audit_metadata
) VALUES (
  '<auth.users.id from the dashboard>',
  'Priya Founder',
  'priya@diariesclub.in',
  'super_admin',                        -- one of: super_admin / admin / manager
  true,
  '{}'::jsonb
);
```

---

## 6. Edit reflection moment text

24 reflection moments seeded already. Edit the displayed text (e.g. tone tweaks) without changing tag/trait — those are referenced by hash for stable card ordering.

```sql
-- Change just the display_text:
UPDATE reflection_moments
   SET display_text = 'Tried something new even when nervous'
 WHERE tag = 'tried_new_thing';

-- See all moments grouped by trait:
SELECT primary_trait, tag, display_text, xp_weight, is_active
FROM reflection_moments
ORDER BY primary_trait, sort_order;

-- Toggle active/inactive (rare — affects card pool):
UPDATE reflection_moments SET is_active = false WHERE tag = '<tag>';
```

Notes:
- Don't change `tag` — it's the stable identifier referenced in `xp_events.metadata`.
- Don't move a moment between traits without thinking; existing recaps will look weird.
- `xp_weight` (default 1.0) tunes how much XP that moment contributes when tapped during reflection.

---

## 7. Create a FIT meal template

Two-step: insert the template, then link it to existing meal categories (e.g. Protein, Dip, Salad) via the join table.

```sql
-- Step 1: the template
WITH new_template AS (
  INSERT INTO fit_meal_templates (
    venue_id, name, description, base_price_paise,
    photo_url, is_subscribable, is_published, is_available, sort_order
  ) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Build-Your-Own Wrap',
    'Choose a protein, dip, salad. Wrapped in spinach roti.',
    25000,                              -- ₹250 base
    'https://placehold.co/600x400.png?text=BYO+Wrap',
    false,                              -- true if it's a subscription option
    true,                               -- is_published
    true,                               -- is_available right now
    10                                  -- sort_order — lower numbers show first
  )
  RETURNING id
)
-- Step 2: link to categories. Each row says "this template uses
-- this category, with these override flags". category_id values come
-- from `fit_meal_categories` (one per Protein, Dip, Salad, etc).
INSERT INTO fit_meal_template_categories (
  template_id, category_id, is_required, selection_type_override, display_order
)
SELECT t.id, c.id,
       CASE c.slug WHEN 'protein' THEN true ELSE false END,
       NULL,                            -- inherit selection_type from category
       CASE c.slug WHEN 'protein' THEN 1
                   WHEN 'dip'     THEN 2
                   WHEN 'salad'   THEN 3
                   ELSE 99 END
FROM new_template t
CROSS JOIN fit_meal_categories c
WHERE c.venue_id = '00000000-0000-0000-0000-000000000001'
  AND c.slug IN ('protein','dip','salad');
```

Notes:
- `fit_meal_categories` is currently empty (`SELECT count(*) FROM fit_meal_categories;`). Create at least one category before this step, e.g.:

```sql
INSERT INTO fit_meal_categories (venue_id, name, slug, selection_type, default_required, display_order)
VALUES
  ('00000000-0000-0000-0000-000000000001','Protein','protein','single',true,1),
  ('00000000-0000-0000-0000-000000000001','Dip','dip','multi',false,2),
  ('00000000-0000-0000-0000-000000000001','Salad','salad','multi',false,3);
```

- After creating categories, populate `fit_meal_options` (the actual choices like "Chicken", "Paneer", "Hummus") before linking.
- Customer-facing query reads `fit_meal_templates WHERE is_published=true AND is_available=true`.

---

## Verification queries

After any of the above, sanity-check what the customer/staff will see:

```sql
-- Live workshops customers see
SELECT title, scheduled_at, capacity, spots_remaining, price_paise
FROM workshops WHERE is_published = true AND status = 'upcoming'
ORDER BY scheduled_at;

-- Live announcements
SELECT title, type, visible_from, visible_until
FROM announcements WHERE is_published = true
  AND visible_from <= now() AND (visible_until IS NULL OR visible_until > now())
ORDER BY visible_from DESC;

-- Active staff
SELECT name, role, force_pin_change, last_pin_used_at
FROM staff WHERE is_active = true AND venue_id = '00000000-0000-0000-0000-000000000001';

-- Live FIT templates with their category requirements
SELECT t.name, t.base_price_paise/100.0 AS rupees,
       array_agg(c.name ORDER BY tc.display_order) AS categories
FROM fit_meal_templates t
LEFT JOIN fit_meal_template_categories tc ON tc.template_id = t.id
LEFT JOIN fit_meal_categories c ON c.id = tc.category_id
WHERE t.is_published = true AND t.is_available = true
GROUP BY t.id, t.name, t.base_price_paise;
```

---

## When to escalate to v1.1 admin web

This SQL workflow is for soft-launch (~2 weeks). For ongoing operations, the rebuilt admin web (v1.1 — see `docs/v1_1_backlog.md`) is the right tool. Use SQL only when:

- The Flutter admin web tab is blank or unresponsive (BUG-031 family).
- You need to do a one-off batch operation (e.g. seed 12 workshops at once).
- You're debugging customer-reported data inconsistencies.

Don't use SQL for:
- Refunds — use the staff app's refund flow (audit-logged through the right RPC).
- Wallet adjustments — go through `manual_wallet_adjust` RPC, not direct UPDATE on `wallets`.
- Anything destructive without a `BEGIN; ... ROLLBACK;` first to preview the effect.
