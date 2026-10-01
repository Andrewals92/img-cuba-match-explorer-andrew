# v4.0 validation — in progress

- Baseline source verified against GitHub main a71efdc39e618558e585ebd23a44bf8cc6d36f20.
- Migrations 013, 014 and 015 applied successfully.
- Baseline remains 36 imported profiles / 338 invitations / 14 matches, zero duplicate imported report tuples.
- Transactional SQL tests passed: n=2 suppression; n=6 counts/medians/rates; consent exclusion; incomplete cycles; own-data read/update; RLS isolation; self-promotion denied; admin RPC denied to normal users; public aggregates available. Synthetic rows rolled back.
- Personal-summary tests passed: declared totals including zero, detail deduplication, selected-cycle isolation and invalid-rate handling.
- Five-program aggregate EXPLAIN ANALYZE: approximately 41 ms before the join indexes, no disk spill.
- Production/browser/auth verification is pending. This document must be finalized after deployment smoke tests.

## Preview verification completed

- Corrected preview bb610a5 and subsequent specialty fix loaded successfully in Chrome. A truncated HTML transfer in the first preview was fixed before any production update; all repository blob hashes were then checked against local files.
- Real Supabase anonymous REST checks: existing community APIs, paginated directory and 5-program batch all worked. Raw applicant_cycles/program_reports access returned HTTP 401.
- Browser: Program Explorer loads; profiles open; a profile survives reload; selections survive navigation/reload; 2-program Compare renders; adding a sixth program is rejected; cross-specialty warning is visible. Only browser-extension metadata errors were observed, not application errors.
- Headless DOM integration using captured public API fixtures: startup, directory, 5-column comparison, UUID routing and selection persistence passed. These are simulated DOM tests, not a real authenticated browser session.
- Personal DOM fixture tests: declared totals, independent cycle selector, completeness prompt, reported Match, create-profile CTA and anonymous state passed.
- Admin database test passed: role detection, existing moderation RPC and v4 health. Synthetic report and audit changes rolled back.
- Database comparable-cohort regression verifies the current caller and a non-consenting peer are excluded. Transactional fixtures rolled back.
- Responsive Chrome iframe viewport: 390 × 844 outer frame, 375 CSS px inner content after scrollbar. Profile and Compare document width equals viewport width; horizontal overflow is confined to the intentional compare region (299 px viewport / 1291 px content). This is responsive simulation, not an Android hardware test.
- Advisors reviewed after 015: no new unreviewed actionable security issue. Intentional public aggregate/metadata DEFINER grants and the deny-by-default private identity table produce expected notices. Two v4 join indexes resolve the relevant foreign-key index notices; unrelated baseline notices remain documented.

## Checks requiring authenticated access

- Supabase URL Configuration currently redirects this browser to sign-in. Site URL / redirect allowlist and delivered confirmation/recovery email links have not been verified in this run. Auth configuration has not been changed.
- Public Auth settings confirm signup is enabled and email autoconfirm is disabled.
- End-to-end normal-user login, form submission in a real session, Admin browser controls and delivered-email recovery/confirmation remain unverified. Database RLS, own-data update, self-promotion denial and admin-RPC denial have been verified separately; these do not substitute for the missing end-to-end tests.
- v4.0 must not be described as fully satisfying the Definition of Done until these authenticated checks are completed.
