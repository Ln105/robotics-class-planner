# Robotics Class Planner

A shared, access-controlled planner for **Noah R — Teacher**, covering September 2026 through August 2027.

## Open it

Configure Supabase, then deploy the files to an HTTPS static host. Open the deployed URL in any current desktop, tablet, or phone browser.

## What it includes

- Home, 12-month year plan, month plans, weekly plans, and dated session/day records
- A deep-indigo, warm-orange glassmorphism interface inspired by the provided reference
- Shared Supabase database and storage for planner content and photos
- Public view-only access plus a single authenticated administrator/editor
- Add up to two additional weeks to any month
- Delete a selected week as the administrator after a detailed confirmation; its sessions and photo records are removed safely by database cascades
- Add up to four compressed, shared project photos to each week
- Add only the sessions that actually take place, each with activity notes, observations, and up to two photos
- Print / export to PDF using the browser's print dialog
- Responsive desktop, tablet, and iPhone-friendly layout with safe-area support

Planner data and photos are not stored in localStorage. Supabase Row Level Security protects writes independently of the interface; visitors can read published content but cannot create, modify, or delete it.

Existing installations should run [supabase-sessions-migration.sql](supabase-sessions-migration.sql) once before deploying this version. The migration is additive and preserves all existing weekly planning and weekly photos.

For the Delete Week upgrade, also run [supabase-delete-week-migration.sql](supabase-delete-week-migration.sql) before deploying the matching site files. The migration is non-destructive and preserves existing planner content.

See [SUPABASE_SETUP.md](SUPABASE_SETUP.md) for the one-time administrator and deployment steps.
