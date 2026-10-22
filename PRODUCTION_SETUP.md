# CNY Pokémon Watch — Separate Production Application

This repository is independent of **FFDPackLabs** and must use its own Supabase project. The root `index.html` is a **browser-local demo**, not secure production. The `production/` directory contains the new Supabase-backed frontend.

## Current status
- GitHub Pages: static hosting works.
- Production frontend: source prepared, **not connected** to a Supabase project.
- Secure database schema: `supabase/schema.sql`, **not applied** yet.
- Real accounts and admin approvals: implemented in code, **not verified on a live database**.
- Product catalog: existing browser-demo entries are separate from the database; production catalog requires seeding/administration.
- Retailer monitoring: **not implemented**. Current offers are entered manually by administrators, and in-app notifications follow verified offer events. Push/Discord/email delivery and scheduled monitoring are still future work.

## Dedicated database provisioning
1. Create a **new** Supabase project named `cny-pokemon-watch` in the intended organization. **Do not run this SQL in AFewBuds or FFDPackLabs databases.**
2. Configure Supabase Auth email/password, verified-email settings, rate limits, authorized site and redirect URL for `https://ffdevelopment.github.io/cny-pokemon-watch/production/`.
3. Review and apply `supabase/schema.sql` in the *new* project's SQL editor. Keep RLS enabled.
4. Copy only that project's **public project URL and publishable key** into `production/config.js`. Never commit a secret, service-role key, database password, or admin password.
5. Publish the `production/` directory through existing GitHub Pages workflow, and verify in a browser on iPhone, Android, and desktop.

## Secure initial admin creation
Admin permissions do **not** come from signup metadata. First register your own account with your intended username and email; verify the email. In the dedicated CNY Supabase project's SQL editor, with project owner privileges, run the following **only after replacing the exact email**:

```sql
UPDATE public.cny_profiles AS p
SET role = 'admin', status = 'approved'
FROM auth.users AS u
WHERE p.id = u.id
  AND lower(u.email) = lower('REPLACE_WITH_YOUR_VERIFIED_ADMIN_EMAIL')
  AND u.email_confirmed_at IS NOT NULL
  AND p.role = 'member'
RETURNING p.id, p.username, p.role, p.status;
```

Verify that **exactly one row** is returned, and retain a separate recovery procedure through Supabase's owner-only SQL console.

## End-to-end acceptance checks
1. Register a new member and verify email (if enabled).
2. Confirm account is **pending** and cannot read products, watches, stores, offers, or notifications using the Data API.
3. Sign in as the independently bootstrapped admin. Confirm the admin can list pending members.
4. Approve a test account. Verify that it gains the ability to browse products and manage **only its own** watches.
5. Attempt direct Data API requests from one member to another member's watches and notifications. Expect access denied or no rows.
6. Disable a user. Confirm the next requests to protected data fail, including from an already signed-in session.
7. Test case-insensitive duplicate usernames.
8. Add a real product and store, then record an **actually verified** in-stock offer. Verify matching in-app alert(s), town filters, and max-price constraints.
9. Verify cross-device session sign-in with the same account, and recovery/sign-out.
10. Run Supabase security advisors, review permissions, and implement backups/uptime monitoring before production launch.

### Limitations and security notes
- Manual retailer reports are not real-time monitoring. Do not represent a source as verified unless checked.
- GitHub Pages will not run the existing `app.py` FastAPI server; do not assume those endpoints are active.
- `production/index.html` runs as a static frontend but is **not active production** until separate Supabase creation, schema migration, seeded catalog, configured client, and live security tests are complete.
- Use officially permitted retailer APIs/feeds for future monitoring; do not bypass bot defenses or fabricate inventory.
