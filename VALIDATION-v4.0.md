# v4.0 validation — deployed; authenticated acceptance pending

- Baseline source verified against GitHub main a71efdc39e618558e585ebd23a44bf8cc6d36f20.
- Migrations 013, 014 and 015 applied successfully.
- Baseline remains 36 imported profiles / 338 invitations / 14 matches, zero duplicate imported report tuples.
- Transactional SQL tests passed: n=2 suppression; n=6 counts/medians/rates; consent exclusion; incomplete cycles; own-data read/update; RLS isolation; self-promotion denied; admin RPC denied to normal users; public aggregates available. Synthetic rows rolled back.
- Personal-summary tests passed: declared totals including zero, detail deduplication, selected-cycle isolation and invalid-rate handling.
- Five-program aggregate EXPLAIN ANALYZE: approximately 41 ms before the join indexes, no disk spill.
- Production source commit: e381430ae4e04d3f6033b0d53cbbe7eaa5087a9a on main.
- Vercel deployment dpl_7DNXFLgfU9Hy7VaCu1BQjKWrgP8X was verified Ready / Production / Current on 2026-10-01.
- Production URL: https://cuba-match-explorer.vercel.app/ (production domain unchanged).
- Production HTTP 200 and byte-for-byte checks passed for index.html, app.js, workspace.js and service-worker.js against released source. The service-worker source uses the v4.0 cache namespace; a device retaining a previously installed v3.7 worker was not available for an upgrade-path test.
- Live production Chrome smoke: community dashboard, program profiles and two-program comparison rendered correctly with real privacy-safe aggregates. No application-origin fatal console errors were observed.
- Community dashboard declared invitation total (362) is distinct from the imported detailed invitation-row invariant (338).
- Source hashes were compared with every GitHub tree blob before promotion; temporary mobile QA harness is absent from production.

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

- Supabase dashboard login succeeded on 2026-10-01. URL Configuration was found to contain the baseline default http://localhost:3000 and an empty redirect allowlist. After production health was verified, Site URL was corrected to https://cuba-match-explorer.vercel.app and the exact redirect https://cuba-match-explorer.vercel.app/ was added. Both values were verified after reload. No wildcard preview domains were added.
- Supabase Emails shows default templates and no custom SMTP configuration. Delivered confirmation/recovery links remain unverified.
- A production app sign-in attempt through secure browser authentication returned “Failed to fetch”; it did not establish a session. Public community data still loaded afterward. This is not evidence of incorrect credentials; the authenticated browser acceptance tests remain pending.
- Public Auth settings confirm signup is enabled and email autoconfirm is disabled.
- End-to-end normal-user login, form submission in a real session, Admin browser controls and delivered-email recovery/confirmation remain unverified. Database RLS, own-data update, self-promotion denial and admin-RPC denial have been verified separately; these do not substitute for the missing end-to-end tests.
- v4.0 must not be described as fully satisfying the Definition of Done until these authenticated checks are completed.
