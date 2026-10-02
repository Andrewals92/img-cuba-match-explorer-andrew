# v4.1 validation — deployed; browser acceptance pending

Baseline: GitHub main 2f139663d527c44647661f7141fb06c179f1f024, verified against every local v4.0 blob before edits. Latest historical migration was 015. Production source of truth and prior Auth limitations were reviewed.

- Migrations 016–019 applied successfully; no historical migration was rerun.
- Historical baseline before upgrade: 36 imported profiles, 338 invitation rows, 14 matches.
- Real transactional PostgreSQL tests passed: own CRUD, scheduling/status/thank-you/rank/impressions, duplicate rejection, social at the same time allowed, wrong-user cycle denied, user B SELECT/UPDATE/DELETE isolation, forged owner rejected, admin isolation and anonymous permission denial. Synthetic data rolled back. Own delete-my-data erasure also passed.
- Calendar tests passed: New York summer/winter offsets, spring DST gap, autumn repeated hour first/second choice, month/year boundary, multiple events including social, cancelled ICS, CRLF/UTF-8 line folding, stable IDs, no notes/impressions/rank leakage and correct Google dates/timezone.
- Simulated private DOM workflow passed: save program, create/edit interview, private notes, completion, thank-you, rank, dashboard metrics/next event, calendar view, cycle change and session clearing. These are integration fixtures, not a real account login.
- Anonymous DOM regression passed: startup, directory, stable UUID profile route, Compare 2–5/max-sixth rejection, selection persistence, no fatal application script errors.
- Security/performance advisors reviewed. No new public DEFINER productivity API; private validator is revoked from public/anon/authenticated. Composite FK index notice corrected by 017. Existing baseline public aggregate DEFINER notices, unrelated missing FK indexes, older RLS performance notices and disabled leaked-password protection remain documented in SECURITY.md.

- After migrations, historical integrity remains 36 | 338 | 14 with zero duplicate import tuples.
- Anonymous real REST reads of both new tables return HTTP 401.
- Preview 5404704 was verified Ready in Vercel and its v4.1 homepage opened in Chrome. Further interactions were blocked by native credential protection in the shared browser; public/private visual QA is not claimed.
- Vercel connector can list the team, but deployment reads return 404/403 and get_project exposes an input-mapping error. Production readiness must be verified through a permitted live UI or deployment status plus alias/source checks.

## Production verification

- Source release 9cb7273cb3902c5f4ddc7534ad2479a1434edbb6 was promoted to main after every GitHub blob matched local source (43 files). Preview-only synthetic QA pages were excluded.
- Vercel dpl_9bMYptdkMYH9Vh29Kx9FXaRrraTn was directly observed Ready / Production with source main 9cb7273 and alias cuba-match-explorer.vercel.app.
- Production HTTP 200 and exact source-byte comparisons passed for index.html, app.js, workspace.js, season.js, calendar-utils.js, styles.css and service-worker.js. Production domain is unchanged.
- Cache namespace and versioned frontend URLs are v4.1. A device retaining a previous worker is not available for an installed-PWA upgrade-path test.

## Pending acceptance

Real authenticated browser CRUD/normal-user/admin, delivered signup confirmation/recovery, Full mobile browser workflow and delivered-email/authenticated acceptance remain unverified. ZIP SHA-256 is supplied with the final artifact. Prior v4.0 secure browser login returned Failed to fetch; it must not be treated as an authenticated pass. Supabase URL Configuration was corrected and reload-verified in the preceding v4.0 work: Site URL https://cuba-match-explorer.vercel.app, exact redirect https://cuba-match-explorer.vercel.app/. No Auth configuration change is introduced by v4.1.

## Responsive verification and follow-up

A preview-only synthetic harness without any credential forms loaded the actual season.js, calendar-utils.js and styles.css in a 390 × 844 iframe (375 CSS px after scrollbar). Tracker and edit form rendered, time was correctly shown as Oct 14 at 10:00 America/New_York, and document width equaled viewport width (375 px) in both views. The harness contains no real user data, makes no production database requests, and is excluded from main/ZIP. This is responsive simulation, not Android hardware or an authenticated session.

Visual inspection identified low contrast in newly added cards because their initial fallback background was white in the dark theme. The production CSS was corrected to the existing --panel color, error text to --danger, and all season buttons to 44 px minimum touch height. Further shared-browser inspection then hit native credential protection again, including the credential-free harness. Full watchlist/calendar/dashboard mobile interaction and visual reinspection after that correction remain pending; those checks are not represented as passed.
