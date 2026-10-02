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

## v4.1 private productivity records

interview_events and user_program_watchlist grant CRUD to authenticated only, guarded by owner USING and WITH CHECK policies with `(select auth.uid())`. There is no admin bypass. Composite cycle ownership FK, optional report ownership validation and immutable owner checks reject spoofed linking. A private, non-executable DEFINER trigger validates directory identities and IANA zones with empty search_path; it returns no applicant data. The existing delete_my_data function now includes these records with explicit own-UID predicates and empty search_path. Existing public aggregate RPCs do not join new private tables.

Private data is held in memory only and cleared between sessions; the worker caches static assets and never Supabase API responses. The UI does not print records/errors to developer logs. Meeting URLs accept HTTP(S) only, anchors use noopener/noreferrer. Notes, impressions and rank positions never enter ICS or Google URLs. Meeting URLs require an explicit export checkbox; users choose whether to share them with their calendar provider.

Advisor review after v4.1 DDL: the new composite FK index notice was fixed with 017. New indexes may initially appear unused on empty tables; do not remove ownership/duplicate/FK indexes merely for low initial traffic. Existing baseline advisor issues remain as documented above. Review guidance: https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection .

## v4.2 alerts

Notifications have owner-only SELECT and UPDATE(read_at); admin no longer has a direct notification-content bypass. Preferences, Radar filters and devices use owner CRUD with USING/WITH CHECK. Outbox/delivery/change-event tables have no ordinary client grants. Internal runtime keys have no public schema exposure or role grants. Service-only worker RPCs require execution grants; config additionally validates a generated cron token. No API keys or VAPID private material enter the frontend/ZIP. Private interview payloads are generic and omit all notes, meeting links and rank positions.

Push endpoints allow only established HTTPS push-service hosts; device count is capped, preventing arbitrary server fetches and runaway fan-out. Click routes are constrained on server, frontend and service worker. Email text is escaped in HTML; server payload is built from canonical limited notifications, not user-provided private JSON. Resend uses a stable per-job idempotency key; retries are bounded at five with exponential delays. Processing leases and per-device success records prevent normal successful redelivery. A transport timeout after push provider acceptance may still be at-least-once; stable notification tag/topic replaces the visible duplicate. Do not claim exactly-once push delivery.

Readiness configuration is not domain verification by itself. Review Resend DNS/provider status and perform receipt testing before setting the server verified flag. No email provider webhook was added; any future webhook must verify its signature before state updates.

Web Push endpoints have one global owner. When the browser has a subscription absent from the signed-in user's own RLS-visible devices, explicit activation unsubscribes it and creates a fresh endpoint; it does not reveal or transfer the previous owner. Send-time eligibility rechecks Radar filters, removed/muted saved programs, follow-up and digest opt-outs.


## v4.3

Private canonical view and program source catalog have no anonymous/authenticated raw access. The catalog uses RLS deny-by-default. New public aggregate/resource RPCs set search_path to empty and expose only program metadata or internally suppressed aggregates. Admin diagnostics require is_admin. Wave alerts default off and reuse existing channels, mute, digest, dedupe, delivery limits and send-time opt-out protection. No new credentials, Auth redirect changes or raw private tracker aggregation.
