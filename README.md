# CNY Pokémon Watch

A standalone Pokémon TCG product watchlist and Central New York retailer directory for phone and desktop. Independent of FFDPackLabs and AFewBuds.

## Application URLs

- **Main app:** https://ffdevelopment.github.io/cny-pokemon-watch/
- Direct production portal: https://ffdevelopment.github.io/cny-pokemon-watch/production/
- Legacy **browser-local demo only**: https://ffdevelopment.github.io/cny-pokemon-watch/demo/

The root URL redirects to the real Supabase-backed portal. Demo browser accounts are not real accounts.

## What's implemented

- Real Supabase Auth: email/password signup and sign-in, confirmation resend and password reset UI
- Persistent accounts, case-insensitive unique usernames, pending/approved/rejected/disabled statuses
- Database-enforced role-based access with row-level security (RLS)
- Mobile/desktop admin panel for member approvals and deactivation
- Product catalog (initial set of 30 catalog entries; **not a guarantee of completeness or current stock**)
- Central New York retailer directory (14 records, online and local)
- Personal cross-device watchlists with maximum price and selected towns
- Admin-entered retailer offers with source URL, price, status, verification timestamp
- Updates to existing offers without duplicating the same product/store/link
- In-app notifications triggered by qualifying recent in-stock evidence and price thresholds
- Stale-offer warning after one hour
- GitHub Actions production JavaScript syntax check and UI element contract check before deployment

## Not yet production complete

- **No automated retailer stock polling** or live store inventory providers are connected. A product listing is not proof of availability.
- Email, push, and Discord *restock deliveries* are not connected; in-app notification rows are supported. App refreshes its own alerts while open.
- Supabase's default SMTP is limited to project-team addresses; configure **custom SMTP** before inviting unrelated public testers. Ensure the production redirect URL is allowed in Auth settings.
- Leaked-password protection is flagged in Supabase's security advisor and requires an eligible paid plan.
- A full end-to-end multi-device browser smoke test and production backup/restore test are still required.

## Approving users

1. Register and verify your email, then have a project owner bootstrap the first administrator (see `PRODUCTION_SETUP.md`).
2. Sign in at the production portal. Select **Admin**.
3. Under **Member approvals**, choose **Approve**, **Pending**, **Rejected**, or **Disabled**.
4. Members refresh their approval status or sign in again; only approved members can access protected content.
5. Never give any user your Supabase service role key. All approval decisions are enforced in the database.

## Development

Frontend lives in `production/`; database migration scripts in `supabase/`; regression checks in `tests/`.
GitHub Pages deploys from `main` after syntax and control checks in `.github/workflows/pages.yml`.
Never commit email SMTP passwords, webhook tokens, admin passwords, or Supabase secret keys.

**Status:** Beta for approved members. Do not describe stock reports as continuous real-time inventory or open unrestricted public signups until the remaining services and operational checks are finished.
