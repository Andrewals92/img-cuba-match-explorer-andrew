# Cuba Match Explorer v5.0

Created and owned by Andrew A Lopez Sanchez, MD, MBA  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.

## Release status

Release candidate; production acceptance is pending. The currently verified production source is v4.3 commit `21b031ba71a6f93b13a660491af797611c585269`. Do not label v5.0 complete until the production deployment and live provider tests are recorded here.

## Changes

- Match Intelligence: own selected cycle, editable similarity ranges, explicit missing-field policy, counts before/after, completed/in-progress separation, protected cohort characteristics, program/state observations, uncertainty and filter explanations.
- Program Discovery: specialty, state, query, sample, signal and activity controls; stable identities, reasons, pagination, save/compare/research actions. No quality score, winner or personal probability.
- Authenticated natural-language assistant with cited catalog, program-guide, community and minimal owner-context evidence. Context buttons in profiles, compare, cohorts, saved programs, My Match and waves/signals.
- Evidence selection uses AI; final sentences are constructed from verified tool results. Provider failures show a clearly labeled direct-data fallback. Official websites are linked, not silently treated as freshly read pages.
- Feedback and aggregate AI Operations. No persistent chat; no notes, meeting URLs, rank positions or verification evidence in AI context.
- Cohort RPC no longer returns individual imported or current applicant records. Counts under five and small/complementary results are protected internally. Current cycles never imply No Match.
- Cache version `cuba-match-explorer-v5.0-r3`; private API responses bypass the PWA cache.

## Database and regression checks

038 and 039 applied successfully. Six transactional suites passed: AI privacy, existing privacy/RLS, season tracker, notifications, wave/signal privacy and program guide. Historic integrity remains **36 profiles | 338 detailed invitations | 14 matches**, with no duplicate historical payloads. The existing 821 guide records/702 program identities retain their verified links and signal information.

17 gateway tests and four DOM suites passed, along with personal totals and calendar/DST tests. Advisor review added only the expected private deny-all metadata table and five deliberately authenticated SECURITY DEFINER functions with explicit owner/admin checks and empty search paths. No new performance finding. Existing Auth leaked-password protection and historical RLS/index advice remain unchanged.

## Remaining acceptance

- Preview/production browser checks and real AI Gateway inference.
- Authenticated owner/admin interaction and production 200/Ready status.
- Actual Android-device acceptance and signup-confirmation inbox receipt are not represented by desktop mobile-width testing. Existing owner-confirmed recovery is preserved, not newly exercised by sending unsolicited email.
- Provider data processing is explained at first use; no claim of provider zero retention. No paid credits or automatic reload were purchased/enabled.


## Candidate r2 — community summary review

Migration 040 applied on 2026-10-02. The existing community histogram showed cells of one and two people. The summary now combines adjacent Step 2 ranges only when every resulting nonempty cell has at least five distinct contributors; otherwise the histogram is suppressed. Small community totals are protected, matches use completed cycles, and the v5 frontend shows an em dash for protected values. The chart title now correctly says community profiles, not interviewed applicants.

The additional transactional `community-summary-privacy.sql` suite passed, including small totals, coarse-bin sum preservation, future-cycle outcome suppression and unchanged 36/338/14. Security/performance advisor counts did not change after 040.

Preview reached Ready. Browser checks passed: actual program profile and guide rates, Compare with five programs and cross-specialty warning, persistent selection, anonymous assistant gate, 360/390px layouts with no body overflow. Owner/admin login is now verified; the account has no cycle profile and correctly sees the create-profile CTA. Feedback save/withdraw and aggregate AI Operations were verified. Cache r3 assets loaded after refresh.

Live provider diagnosis found HTTP 403 for GPT-5.4 mini: the model is not eligible for this team's free-credit tier. No tokens or costs were reported for those requests. GPT-5 mini is explicitly eligible in Vercel's current public provider catalog, and is now the default. Real research, free-question routing and five-program comparison succeeded with GPT-5 mini. Sources, exact rates, missing denominators, protected activity and cross-specialty/no-winner cautions were verified. Every selected program identity is retained by the server even if omitted by model selection. Only fixed diagnostic codes are returned; raw provider bodies and credentials never leave the server. No paid credit or automatic reload was enabled.
