# v4.3 validation

Baseline inspected: main ee173de7b4f1a9d951ab5add270f149320f7ed48, live v4.2 at https://cubamatchexplorer.org, migrations through 029. Current architecture and Auth preserved. Owner reported the recovery email link worked before this upgrade.

## Applied and tested

- Migrations 030–033 applied successfully; no historical migration rerun.
- Program import: 702 interview-rate entries and 119 complements, all 821 linked to 702 unique programs after migration 034. Source keys prevent duplicate imports.
- intelligence-privacy.sql PASS: wave 2 suppressed/3 disclosed; Gold 4 suppressed/5 valid; complement suppression; duplicate observation dedup; active/historical cycles; no pooled signal rates; cross-filter behavior; private schema/tracker ACLs; admin diagnostic ACL.
- wave-alerts.sql PASS: explicit opt-in; sufficient period; cycle/week dedupe; muted saved programs; no unintended email/push. All synthetic users/reports/notifications rolled back.
- Existing privacy-rls.sql PASS: consent, small cells, totals, completed cycles, own-data update, role escalation and admin RPC denial.
- season-rls.sql PASS: private CRUD, foreign-cycle denial, duplicate protection and A/B/admin/anonymous isolation.
- notifications-rls.sql PASS: isolation, read state, Radar filtering/dedupe, private reminders, DST quiet hours and bounded retry.
- Calendar and personal summary tests PASS: DST, ICS, authoritative totals, zero, detail dedup and cycle isolation.
- Notification/season DOM suites rerun against v4.3 PASS: CRUD, escaped content, private cycle isolation, signout clearing, preferences and calendar.
- New intelligence DOM suite PASS: cycle semantics, suppressed UI, text escaping, external percentage formatting, authenticated dashboard guard, visible denominators and error/retry.
- Function query plan: 30-program overview 45.834 ms execution. No N+1 calls introduced.

## Advisor review

Security/performance advisors reviewed after DDL and again after migration 033 on October 2, 2026. The new private source table deliberately has RLS with no user policies and revoked schema/table privileges. Public SECURITY DEFINER aggregate endpoints have explicit empty search_path, bounded arguments and safe output; the admin endpoint checks is_admin. These are expected advisory warnings, not unrestricted raw access. No new missing foreign-key index was reported; the source catalog FK has an index. Its initially unused index is retained for joins and future imports. Preexisting Auth leaked-password protection, RLS initplan and moderation-FK warnings were not introduced by v4.3.

Advisor references: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable and https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy .

## Production acceptance

On October 2, 2026, source commit 3c90fcc3006f1e4054119a2a00f312ae3102ed81 deployed to the existing Vercel project and was observed Ready / Production / Current (deployment dpl_7R3FLbhEBsRAWBESnYkDNRKZDtHf). Browser acceptance used the actual production site, not fixtures. Interview Waves loaded; program profiles opened by stable UUID; Compare retained two selections after reload and successfully displayed five programs; cycle context and suppressed values were visible. The production source catalog retains program-only metadata and provenance. No application-origin fatal JavaScript error was observed; browser-extension metadata errors were excluded.

Actual production views rendered inside 390 px and 360 px Chrome iframe viewports on a preview-only QA branch. Document widths matched scroll widths (375/375 and 345/345 after scrollbar space). This verifies responsive layout, not a physical Android device. A small source-search touch target found during this check is enlarged to at least 44 px in the final patch. The final patch also prioritizes supplied individual Residency Explorer links, adds migration 033 to source control, and advances the service-worker cache to v4.3-r2.

Final production database regression after migrations 030–033: **36 imported profiles | 338 detailed interview invitation rows | 14 matches | 0 duplicate imported report payloads**. Synthetic tests were rolled back. No historical import was rewritten.

## Known limits

- Production currently has no source=user community application reports; 338 historical invitation rows lack dates. Real wave/signal views correctly show insufficient data. Synthetic transaction tests prove threshold behavior without publishing invented observations.
- All 19 previously unresolved aliases are now verified and linked by official ACGME code.
- All 702 programs have an institutional link. Broader institutional pages are explicitly labeled; an automated HTTP audit identified and repaired obsolete links. Regional/security restrictions and timeouts prevent a universal HTTP-200 guarantee for third-party sites.
- Real Android Chrome/PWA background push, signup-confirmation inbox acceptance and a new owner-password change are not automated in this release. Recovery link success was reported by the owner; production Auth settings remain unchanged.

## v4.3-r3 guide acceptance

Migration 034 applied successfully after a rollback-only dry run. `program-guide.sql` PASS: 821 linked records, 702 unique identities and links, all pages without duplicates/loss, no provider provenance in public responses, no personal prediction fields, anonymous/normal-role ACLs, 36 profiles / 338 invitations / 14 matches and zero duplicate historical payloads. `intelligence-privacy.sql` and `privacy-rls.sql` rerun PASS with rolled-back fixtures. DOM regression PASS for neutral labels, percentage formatting, zero vs unavailable, bounded descriptive differences, safe links, one directory request and existing privacy/cycle behavior. Calendar and personal-summary regressions PASS.

Security/performance advisors reviewed after 034; no new actionable finding. Existing deliberately private deny-all tables and restricted definer RPC warnings are unchanged. The enriched 30-program directory measured 12.254 ms execution.

The release receipt accompanying the ZIP records the final main commit and production/browser verification. Historical v4.3-r2 source-link wording above describes the prior release and is superseded by this integrated guide. Real Android hardware and new email signup inbox acceptance remain outside this incremental program-data update.

Migration 035 repairs two program links that redirect to sign-in, one soft-404 relocation, and retains a meaningful program URL query parameter. No applicant data or permissions change.
