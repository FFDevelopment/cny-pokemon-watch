# CNY Pokémon Watch — Production Setup and QA

CNY Pokémon Watch is independent of FFDPackLabs and AFewBuds. Only operate on Supabase project `jrwsbiqxppjcyhgncztf`.

## Current deployed architecture (2026-10-22)
- GitHub Pages: `https://ffdevelopment.github.io/cny-pokemon-watch/` redirects to `production/`
- Production frontend: `production/index.html`, `production/app.js`, `production/config.js`
- Backend: dedicated Supabase PostgreSQL/Auth project (`cny-pokemon-watch`, region us-east-1)
- Schema installed: `supabase/schema.sql` + `supabase/offer_integrity.sql` (already applied)
- Admin: verified owner account initialized; member approvals available in production Admin tab
- Catalog: 30 seeded entries, 14 store directory records. **No real-time availability provider is connected.**
- Notifications: in-app database entries triggered by qualifying manually confirmed offers; no email, Discord, or push sender yet
- Continuous inventory scanning: **not implemented**; do not claim live restock monitoring

## Critical operational settings to finish

1. Supabase Dashboard > Authentication > URL Configuration:
   - Site URL: `https://ffdevelopment.github.io/cny-pokemon-watch/production/`
   - Additional Redirect URLs: add the same exact URL.
2. Supabase Dashboard > Authentication > SMTP Settings:
   - Configure an independently managed transactional email SMTP provider. Default Supabase SMTP does **not** send to arbitrary public recipients.
   - Test email verification and password reset with a disposable external address before public invitation.
   - Keep SMTP passwords in Supabase configuration only; NEVER place secrets in GitHub.
3. Supabase Auth > Email settings:
   - Keep Confirm Email enabled.
   - Configure strong password requirements through Auth settings (frontend minimum is 12).
   - Supabase leaked password protection requires an eligible paid plan; security advisor currently flags it as disabled.
4. Set up database backups/restore procedures and verify a restoration. Current free plan may not offer scheduled backups.
5. Configure actual permitted retailer APIs or licensed structured stock feeds, with allowed polling rates and current store-level inventory evidence; implement and validate a hosted scheduler. News/RSS articles are **not** stock evidence.
6. Add real push/email/Discord alert delivery with rate limits and unsubscribe controls if desired.

## Admin workflow

1. Owner account is already initialized, approved, and email-verified.
2. At `/production/`, sign in and choose Admin.
3. New confirmed users remain `pending`. Select Approve to give them access.
4. Rejection or disablement immediately blocks member data at the RLS layer, including for sessions that remain signed in.

Only one profile can be initial owner. Never assign admin roles based on signup metadata.

## Verification results and limitations

Checks run inside transactions which were rolled back, preserving live users and watches:
- User registration trigger created a pending member profile.
- Pending member could read only their own profile, not product or store data.
- Pending member could not approve themselves.
- Existing approved administrator could approve a transaction-only test member and access protected catalog.
- New manually verified in-stock evidence generated a matching notification.
- A price decrease crossing a watch's maximum-price threshold generated a qualifying alert.
- No fake offers, alerts, users, or price changes persisted after tests.
- RLS was confirmed enabled on all six tables, and indexes added for the referenced foreign keys.
- GitHub Actions validates production app JS module syntax and HTML element IDs before its deploy workflow.
- Actual external email delivery, two-device authenticated browser sign-in, and real retailer-feed stock updates are NOT covered by those tests.

### If account registration fails
Check SMTP authorization/rate limits, Auth Site URL + Redirect URLs, browser console, and Supabase Auth logs. Never disable email verification or RLS to hide a configuration issue.

### If member approvals appear not to work
Confirm current account role is `admin` and status is `approved`; verify the member is not already `admin`. Admin actions now confirm the returned updated row instead of silently displaying success.

### If no restock alerts appear
There are no live stock feeds or recorded offers. Add a genuinely verified retailer offer through Admin. The app cannot detect inventory just because a retailer name or official product URL exists.

### Release standards
Complete SMTP, actual external-member signup approval, iPhone/Android/Windows smoke tests, monitored stock source(s), external notifications, backups, and incident logging before labeling this a feature-complete public release.
