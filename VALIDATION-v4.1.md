# v4.1 validation — release acceptance in progress

Baseline: GitHub main 2f139663d527c44647661f7141fb06c179f1f024, verified against every local v4.0 blob before edits. Latest historical migration was 015. Production source of truth and prior Auth limitations were reviewed.

- Migrations 016–019 applied successfully; no historical migration was rerun.
- Historical baseline before upgrade: 36 imported profiles, 338 invitation rows, 14 matches.
- Real transactional PostgreSQL tests passed: own CRUD, scheduling/status/thank-you/rank/impressions, duplicate rejection, social at the same time allowed, wrong-user cycle denied, user B SELECT/UPDATE/DELETE isolation, forged owner rejected, admin isolation and anonymous permission denial. Synthetic data rolled back.
- Calendar tests passed: New York summer/winter offsets, spring DST gap, autumn repeated hour first/second choice, month/year boundary, multiple events including social, cancelled ICS, CRLF/UTF-8 line folding, stable IDs, no notes/impressions/rank leakage and correct Google dates/timezone.
- Simulated private DOM workflow passed: save program, create/edit interview, private notes, completion, thank-you, rank, dashboard metrics/next event, calendar view, cycle change and session clearing. These are integration fixtures, not a real account login.
- Anonymous DOM regression passed: startup, directory, stable UUID profile route, Compare 2–5/max-sixth rejection, selection persistence, no fatal application script errors.
- Security/performance advisors reviewed. No new public DEFINER productivity API; private validator is revoked from public/anon/authenticated. Composite FK index notice corrected by 017. Existing baseline public aggregate DEFINER notices, unrelated missing FK indexes, older RLS performance notices and disabled leaked-password protection remain documented in SECURITY.md.

## Pending acceptance

Real authenticated browser CRUD/normal-user/admin, delivered signup confirmation/recovery, mobile browser rendering, preview/production smoke, final deployment/ZIP hashes remain to be recorded. Prior v4.0 secure browser login returned Failed to fetch; it must not be treated as an authenticated pass. Supabase URL Configuration was corrected and reload-verified in the preceding v4.0 work: Site URL https://cuba-match-explorer.vercel.app, exact redirect https://cuba-match-explorer.vercel.app/. No Auth configuration change is introduced by v4.1.
