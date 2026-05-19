-- 0158 — Repoint workshop notification deep links to the Workshops tab
-- inside Club (/club/workshops) rather than the Past Workshops profile
-- page (/profile/workshops). When a parent taps a workshop push they
-- expect to land on the live tab, not a history list.
UPDATE notification_templates
   SET deep_link_template = '/club/workshops'
 WHERE type IN ('workshop_registered',
                'workshop_starting_soon',
                'workshop_attended');
