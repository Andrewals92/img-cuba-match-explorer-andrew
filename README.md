# Cuba Match Explorer v4.1

Created and owned by Andrew A Lopez Sanchez, MD, MBA  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.

Production: https://cubamatchexplorer.org/ (https://cubamatchexplorer.com/ redirects with HTTP 308). The previous Vercel alias remains available.  
Repository: Andrewals92/img-cuba-match-explorer-andrew · production branch `main`.

Static HTML, CSS and vanilla JavaScript; Supabase supplies Auth, RLS-protected storage and aggregate RPCs. No frontend build or framework migration is required.

## Workspace

- Program Explorer searches the official catalog and separately identified community reporting labels. Each profile uses a stable UUID route: `#/program/<uuid>?cycle=2026`.
- Program Compare supports 2–5 selected programs, a persistent browser tray, cycle selection, shareable URLs and a horizontally scrollable mobile comparison. It does not rank programs.
- My Match shows only the signed-in account's selected cycle/specialty profile. Declared application/invitation totals take precedence over detailed rows, including declared zero. Personal cycle selection is independent of community and comparable-cohort filters.
- Community analytics, Program Intelligence, Applicant Explorer, Match Map, Mis datos, account flows, administration, exports and PWA support remain.

The 2026 import has 36 profiles, 338 detailed invitations and 14 matches. Its 136 distinct program labels originally had no program UUIDs. v4 assigns stable reporting-label identities without changing those rows or asserting an official ACGME mapping. Use the “Nombres comunitarios (incluye 2026)” filter to find them. Official program profiles can legitimately have no linked community data.

## Run and deploy

Serve this directory over HTTP, for example `python -m http.server 8000`. Public Supabase configuration lives in `cloud-config.js`; never add a service-role key. Vercel uses Framework Other, root `./`, no build/install/output override, and GitHub `main`.

Migrations 002–012 are historical files preserved from the handoff; do not rerun or renumber them. The supplied baseline did not contain a numbered 007 file. Apply new migrations once, in order: `013_program_workspace.sql`, `014_program_identity_maintenance.sql`, then `015_directory_specialty_case.sql`. They are additive and designed to tolerate repeated DDL where practical. Applied migration history in Supabase is authoritative.

`program_compare_stats` serves both profiles and comparisons in one request; no redundant personal dashboard RPC is required because existing own-data queries explicitly filter by authenticated user ID and enforce RLS. Directory search is paginated at 40 entries.

## Validation

Run `node tests/personal-summary.test.cjs`. `tests/privacy-rls.sql` exercises database privacy and permissions inside a transaction which rolls back synthetic fixtures. Run it only through an authorized database connection. It never changes the historical import.

See `RELEASE-v4.0.md`, `SECURITY.md`, `PRIVACY.md` and `VALIDATION-v4.0.md` for release behavior and verification status. Raw imported spreadsheets and row-level import SQL are deliberately excluded from the public source and production bundle.

## v4.1 Interview season

See RELEASE-v4.1.md and VALIDATION-v4.1.md. Additive migrations are 016, 017, 018 and 019; run only new migrations on an existing v4.0 installation. calendar-utils.js converts IANA wall time to fixed UTC instants and exports calendars; season.js manages owner-only private interviews and global watchlists. No frontend dependencies or framework migration were added. Unit checks: `node tests/calendar.test.cjs` (run from the repository root; the test resolves source relative to itself) and `node tests/personal-summary.test.cjs`. SQL acceptance fixtures require a database transaction and always roll back; they must never be converted into persistent seed data.

## v4.2 communication layer

See RELEASE-v4.2.md and VALIDATION-v4.2.md for implementation and readiness. Public Radar is `#/radar`; signed-in Notification Center is `#/notification-center`, preferences `#/notification-settings`.

Existing notifications are extended, not replaced. ACGME change events and explicit Radar/watchlist matching produce canonical private notification records. `cme_private.notification_tick()` runs every five minutes, generates current reminders/digests and dispatches at most five claimed channel jobs. Owner RLS and column-level read-state grants protect user data. Quiet hours defer delivery in the chosen IANA timezone. Daily digest is 09:00 local; weekly is Monday 09:00. Interview reminders keep their separate timing and expire at event start.

Backend source: `supabase/functions/notification-dispatcher`, `supabase/functions/acgme-program-monitor`. New migrations 020–029. Dispatcher requires its internally generated cron token; no frontend invocation or provider secrets. Built-in Supabase server credentials stay in Edge runtime. VAPID initialization uses private storage and serialization. Web Push supports FCM Chrome/Android, Mozilla and Apple endpoints; unsupported endpoint hosts are rejected. Maximum ten stored devices per account. Other services can be deliberately added after validation.

Email provider setup: Resend has verified cubamatchexplorer.org with DKIM and SPF; DMARC is configured in monitoring mode (p=none). Opens and clicks tracking are disabled. Server sending credentials have been stored privately; the dispatcher now advertises email readiness. Auth custom SMTP is configured through Resend on port 465. Actual end-to-end delivery acceptance remains pending. Required server settings are `RESEND_API_KEY`, `NOTIFICATION_EMAIL_FROM` and `NOTIFICATION_EMAIL_DOMAIN_VERIFIED=true` in Supabase Edge secrets. Never put values in frontend, README, GitHub or chat. Branded alerts and Supabase Auth emails are separate. Site URL is https://cubamatchexplorer.org; exact returns for .org and the previous Vercel alias are preserved. The dispatcher advertises email readiness only after server configuration; queues remain unsent while unavailable. Verify provider/domain separately before setting the verified flag. No webhook is deployed or trusted.

Tests: `NODE_PATH=<directory containing jsdom> node tests/notifications-dom.test.cjs`, calendar/personal/season tests; transactional SQL in `tests/notifications-rls.sql`. Local notification DOM test currently expects the `v42/` source directory, as does the production smoke script. No fixture is imported into production permanently.


## v4.3 Interview Wave Tracker and Signal Intelligence

The static frontend adds intelligence.js and batched privacy-safe RPCs, with source provenance for owner-supplied IM program lists. See RELEASE-v4.3.md, ANALYTICS-v4.3.md and VALIDATION-v4.3.md. Production remains https://cubamatchexplorer.org; .com redirects to .org. Migrations 030–033 extend the existing production schema.
