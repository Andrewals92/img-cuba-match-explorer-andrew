# Cuba Match Explorer v5.0

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

Serve this directory over HTTP, for example `python -m http.server 8000`. Public Supabase configuration lives in `cloud-config.js`; never add a service-role key. Vercel uses Framework Other, root `./`, no build/output override; installation is `npm ci --omit=dev --ignore-scripts` for the server-only OIDC dependency, and GitHub `main`.

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

Email provider setup: Resend has verified cubamatchexplorer.org with DKIM and SPF; DMARC is configured in monitoring mode (p=none). Opens and clicks tracking are disabled. Server sending credentials have been stored privately; the dispatcher now advertises email readiness. Auth custom SMTP is configured through Resend on port 465. The owner confirmed the recovery email link worked; signup-confirmation inbox acceptance has not been automated. Required server settings are `RESEND_API_KEY`, `NOTIFICATION_EMAIL_FROM` and `NOTIFICATION_EMAIL_DOMAIN_VERIFIED=true` in Supabase Edge secrets. Never put values in frontend, README, GitHub or chat. Branded alerts and Supabase Auth emails are separate. Site URL is https://cubamatchexplorer.org; exact returns for .org and the previous Vercel alias are preserved. The dispatcher advertises email readiness only after server configuration; queues remain unsent while unavailable. Verify provider/domain separately before setting the verified flag. No webhook is deployed or trusted.

Tests: `NODE_PATH=<directory containing jsdom> node tests/notifications-dom.test.cjs`, calendar/personal/season tests; transactional SQL in `tests/notifications-rls.sql`. Local notification DOM test currently expects the `v42/` source directory, as does the production smoke script. No fixture is imported into production permanently.


## v4.3 Interview Wave Tracker and Signal Intelligence

The static frontend adds intelligence.js and batched privacy-safe RPCs, with an integrated IM program guide. See RELEASE-v4.3.md, ANALYTICS-v4.3.md and VALIDATION-v4.3.md. Production remains https://cubamatchexplorer.org; .com redirects to .org. Migrations 030–037 extend the existing production schema.

### Complete program guide (v4.3-r3)

The 702 IM programs are grouped by verified ACGME identity, with 119 expanded records attached to the same profiles. All 19 previously unresolved names are linked; no applicant report identity was rewritten. Each program has a program/institution link. Gold, Silver and no-signal interview rates, documented requirements, reference-sample application trends and program videos are visible in the guide and profiles; Compare includes the three rates and descriptive percentage-point differences. Missing values stay unavailable, and observed rates are never personal predictions. The UI uses neutral section names; technical provenance remains auditable in private storage and `supabase/imports/program-guide-v43/`.

Migration 034 adds institutional metadata, resolves the 19 source aliases by ACGME code, adds program-only trend/video fields, and replaces the two existing metadata RPCs with grouped, bounded responses. It is idempotent and does not change Auth, RLS, applicant cycles or program reports. Source extraction remains allowlisted. Regression: `tests/program-guide.sql` and `tests/intelligence-dom.test.cjs`.

Migration 035 repairs two program links that redirect to sign-in, one soft-404 relocation, and retains a meaningful program URL query parameter. No applicant data or permissions change.

Migration 036 fills missing program-directory states from unambiguous, ACGME-linked program locations. All 702 guide programs now have a state and institutional URL; applicant records remain untouched.

Migration 037 refines 53 program website destinations/labels using official residency pages. Coverage is 688 program-specific pages plus 14 clearly labeled institutional pages (702 total). It changes only website metadata; supplied rates, program identities and private applicant data are unchanged. See `supabase/imports/program-guide-v43/residency-links-037.json` for review evidence and HTTP limitations.


## v5.0 Match Intelligence

`#/match-intelligence` is an authenticated decision-support workspace with explainable, aggregate-only cohorts; independent profile/cycle and temporary discovery filters; and a grounded assistant. Program Profile, Compare, Applicant Explorer, My Match, saved programs and wave/signal sections include contextual entry points. No framework migration.

The assistant runs at `/api/match-assistant` in a Vercel Node function. `server/match-ai.cjs` validates Supabase access tokens, routes only approved reads and builds cited evidence. A model selects evidence IDs; displayed facts always come from server-constructed records. It never runs arbitrary SQL or supplies new numbers. Vercel OIDC is the default server credential; `AI_GATEWAY_API_KEY` is an optional server-only fallback. `CME_AI_MODEL` defaults to `openai/gpt-5-mini`, verified with real inference on 2026-10-02 using the existing free-credit allowance. GPT-5.4 mini was rejected by the free tier and is not the default. Model availability can change; failures use the labeled direct-data fallback.

Migrations 038 and 039 were applied after the existing 037 migration. They replace `similar_cohort` individual rows with privacy-safe aggregates, add an owner-scoped discovery RPC, and add minimal operational metadata/feedback with atomic limits. All 002–037 files and historical imported rows remain untouched. Do not rerun old imports.

`npm ci` installs the pinned server dependency; plain HTTP hosting still supports static tools but cannot run the assistant endpoint. Test with `node tests/ai-gateway.test.cjs`; DOM tests use a separate QA installation of jsdom 30.1.1. SQL suites roll back synthetic fixtures. See `RELEASE-v5.0.md`, `AI-DATA-AND-GROUNDING.md`, `AI-EVALUATION.md`, and `ADMIN-AI-OPS.md` for scope and validation limits.


Migration 040 additionally protects the community overview and Step 2 histogram with distinct-person thresholds and safe adjacent-bin grouping. No historical row is changed. Tests in `tests/community-summary-privacy.sql` pass; protected totals are displayed as unavailable, never zero, and current cycles do not produce a completed Match outcome.
