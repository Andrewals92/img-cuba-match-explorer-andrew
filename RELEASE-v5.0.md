# Cuba Match Explorer v5.0

Created and owned by Andrew A Lopez Sanchez, MD, MBA  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.

## Release status

Release candidate; production inference and authenticated browser acceptance are pending. The currently verified production source is v4.3 commit `21b031ba71a6f93b13a660491af797611c585269`. Do not label v5.0 complete until the production deployment and live provider tests are recorded here.

## Changes

- Match Intelligence: own selected cycle, editable similarity ranges, explicit missing-field policy, counts before/after, completed/in-progress separation, protected cohort characteristics, program/state observations, uncertainty and filter explanations.
- Program Discovery: specialty, state, query, sample, signal and activity controls; stable identities, reasons, pagination, save/compare/research actions. No quality score, winner or personal probability.
- Authenticated natural-language assistant with cited catalog, program-guide, community and minimal owner-context evidence. Context buttons in profiles, compare, cohorts, saved programs, My Match and waves/signals.
- Evidence selection uses AI; final sentences are constructed from verified tool results. Provider failures show a clearly labeled direct-data fallback. Official websites are linked, not silently treated as freshly read pages.
- Feedback and aggregate AI Operations. No persistent chat; no notes, meeting URLs, rank positions or verification evidence in AI context.
- Cohort RPC no longer returns individual imported or current applicant records. Counts under five and small/complementary results are protected internally. Current cycles never imply No Match.
- Cache version `cuba-match-explorer-v5.0-r1`; private API responses bypass the PWA cache.

## Database and regression checks

038 and 039 applied successfully. Six transactional suites passed: AI privacy, existing privacy/RLS, season tracker, notifications, wave/signal privacy and program guide. Historic integrity remains **36 profiles | 338 detailed invitations | 14 matches**, with no duplicate historical payloads. The existing 821 guide records/702 program identities retain their verified links and signal information.

15 gateway tests and four DOM suites passed, along with personal totals and calendar/DST tests. Advisor review added only the expected private deny-all metadata table and five deliberately authenticated SECURITY DEFINER functions with explicit owner/admin checks and empty search paths. No new performance finding. Existing Auth leaked-password protection and historical RLS/index advice remain unchanged.

## Remaining acceptance

- Preview/production browser checks and real AI Gateway inference.
- Authenticated owner/admin interaction and production 200/Ready status.
- Actual Android-device acceptance and signup-confirmation inbox receipt are not represented by desktop mobile-width testing. Existing owner-confirmed recovery is preserved, not newly exercised by sending unsolicited email.
- Provider data processing is explained at first use; no claim of provider zero retention. No paid credits or automatic reload were purchased/enabled.
