# Robotics Class Planner

A shared, access-controlled planner for **Noah R — Teacher**, covering September 2026 through August 2027.

## Open it

Configure Supabase, then deploy the files to an HTTPS static host. Open the deployed URL in any current desktop, tablet, or phone browser.

## What it includes

- Home, 12-month year plan, month plans, and weekly detail views
- A deep-indigo, warm-orange glassmorphism interface inspired by the provided reference
- Shared Supabase database and storage for planner content and photos
- Public view-only access plus a single authenticated administrator/editor
- Add up to two additional weeks to any month
- Add up to four compressed, shared project photos to each week
- Print / export to PDF using the browser's print dialog
- Responsive desktop, tablet, and iPhone-friendly layout with safe-area support

Planner data and photos are not stored in localStorage. Supabase Row Level Security protects writes independently of the interface; visitors can read published content but cannot create, modify, or delete it.

See [SUPABASE_SETUP.md](SUPABASE_SETUP.md) for the one-time administrator and deployment steps.
