# v4.3 validation

Baseline inspected: main ee173de7b4f1a9d951ab5add270f149320f7ed48, live v4.2 at https://cubamatchexplorer.org, migrations through 029. Current architecture and Auth preserved. Owner reported the recovery email link worked before this upgrade.

## Applied and tested

- Migrations 030–032 applied successfully; no historical migration rerun.
- Program import: RE 702 entries, 683 linked; MAR 119 entries, all linked. Source keys prevent duplicate imports. Unresolved RE entries remain unattributed.
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

Security/performance advisors reviewed after DDL. The new private source table deliberately has RLS with no user policies and revoked schema/table privileges. Public SECURITY DEFINER aggregate endpoints have explicit empty search_path, bounded arguments and safe output; the admin endpoint checks is_admin. These are expected advisory warnings, not unrestricted raw access. No new missing foreign-key index was reported; the source catalog FK has an index. Its initially unused index is retained for joins and future imports. Preexisting Auth leaked-password protection, RLS initplan and moderation-FK warnings were not introduced by v4.3.

Advisor references: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable and https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy .

## Production acceptance

Deployment, HTTP, browser, layout and final data-regression results will be appended after the v4.3 main commit becomes Ready/Production. The local browser could not access the workspace's localhost server; DOM tests ran in the workspace, and visual acceptance uses the actual production site.

## Known limits

- Production currently has no source=user community application reports; 338 historical invitation rows lack dates. Real wave/signal views correctly show insufficient data. Synthetic transaction tests prove threshold behavior without publishing invented observations.
- 19 RE identity mappings remain unresolved. Individual RE links are available; no community attribution is guessed.
- Most institutional program websites are not individually verified; all 702 RE source URLs are retained, and the four MAR-only link gaps have verified institutional fallbacks.
- Real Android Chrome/PWA background push, signup-confirmation inbox acceptance and a new owner-password change are not automated in this release. Recovery link success was reported by the owner; production Auth settings remain unchanged.
