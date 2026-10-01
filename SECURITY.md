# Security — v4.0

No service-role credential belongs in the browser, GitHub or bundle. The committed Supabase publishable key is public by design. Auth uses the existing production-origin redirects, session refresh and password-recovery handling.

New SECURITY DEFINER functions set an empty search_path, fully qualify tables, revoke default PUBLIC execution and grant only necessary roles. Public directory/identity APIs return program metadata only. `program_compare_stats` returns only protected aggregates. `program_workspace_health_v4` requires the existing admin/moderator authorization check; it is not executable by anon. Its authenticated grant alone does not authorize a normal user.

`cme_private` is not an exposed schema; anon/authenticated have neither schema usage nor table privileges. Its identity table has RLS with intentionally no user policies. Trigger functions are not granted to API roles. Existing application-table RLS and role-change/verification triggers are preserved.

All frontend program names and metadata are escaped. External links allow HTTPS only in the v4 workspace; existing safe-link behavior elsewhere is retained. Hash UUIDs are validated and compare requests are bounded to five IDs in both client and database. No private raw report rows are returned by the new public APIs.

## Advisor review

The existing project has warnings for intentional public SECURITY DEFINER aggregates, authenticated admin RPCs with internal authorization, leaked-password protection disabled, and pre-existing RLS performance/index opportunities. New public aggregate/directory functions are intentional allowlisted APIs, reviewed with threshold tests. No user privilege is granted to the private schema. 014 adds indexes on program_reports(program_id,match_cycle) and program_external_sources(program_id), covering v4 joins identified by advisors. Unrelated historical policies are not rewritten in this release.

Advisor guidance:
- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

See VALIDATION-v4.0.md for executed checks and remaining verification limits. Do not describe untested email delivery or browser account flows as verified.
