# Connect the shared planner

1. Create a Supabase project and open its **SQL Editor**.
2. Run [supabase-schema.sql](supabase-schema.sql). It creates the planner tables, photo bucket, and Row Level Security policies.
3. In **Authentication → Users**, create the single administrator using email and password.
4. Copy that user's UUID and run the final `insert into public.admin_users ...` command shown in the SQL file.
5. In **Project Settings → API**, copy the Project URL and publishable/anon key into [supabase-config.js](supabase-config.js).
6. Deploy the website files to any HTTPS static host. Do not use `file://` for the production site.
7. Open the site, select **Admin login**, and sign in. The first edit or added week creates the shared planner records.

The browser's anon key is not a secret. Supabase Row Level Security independently grants writes only when `public.is_admin()` identifies the authenticated administrator. Visitors have read-only database and photo access.

## Verify before sharing

- Open the site in a private/incognito window: planner content and photos should be visible, with no edit fields or upload controls.
- Sign in as the administrator: editing fields and photo controls should appear.
- Try an unauthenticated insert in Supabase's API docs or a browser console: it must be rejected by RLS.
