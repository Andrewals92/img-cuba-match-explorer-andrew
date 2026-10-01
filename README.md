# Cuba Match Explorer v4.0

Created and owned by Andrew A Lopez Sanchez, MD, MBA  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.

Production: https://cuba-match-explorer.vercel.app/  
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
