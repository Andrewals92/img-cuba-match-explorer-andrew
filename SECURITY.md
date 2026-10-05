> Current cohort behavior: v5.1 / migration 041 supersedes the aggregate-only and minimum-five cohort descriptions below. Publicly shared profiles and documented programs/signals are available pseudonymously for any cohort size. Private fields and opt-out rows remain excluded. See RELEASE-v5.1.md.

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

### v4.3-r3 guide review

Migration 034 keeps the private catalog RLS enabled with no user access. The existing public metadata functions retain empty search_path, explicit grants and bounded pagination/ID arrays; they disclose only program metadata. Institutional anchors accept only HTTP(S), reject embedded credentials and `.local` hosts, escape text and use noopener/noreferrer. Advisors reviewed after 034: existing private deny-all table and intentionally anonymous-safe SECURITY DEFINER notices remain expected. No new actionable security/performance issue was introduced. Tests cover anonymous metadata access, private ACLs, personal-field exclusion and unchanged 36/338/14 historical counts.


## v5.0 gateway and aggregate privacy

The prior similar_cohort RPC returned anonymous individual profile records. Migration 038 replaces that output with aggregate-only summaries and empty members, enforces distinct-person thresholds and complementary suppression, excludes all owned profiles, and does not silently widen ranges. Imported row payloads and historical identifiers remain unchanged.

The gateway authenticates every request with Supabase Auth, uses only the same user's token for data reads, and validates origin/body/program IDs. No service-role or provider secret enters the browser. Models select from fixed tools/evidence IDs and cannot create SQL, fetch URLs, mutate records or render unverified prose. Personal values never enter shared caches or logs. See AI-DATA-AND-GROUNDING.md.

Post-DDL security/performance advisors were reviewed: one new private deny-all metadata table (expected RLS/no-policy notice), five authenticated DEFINER APIs (expected execution notices; auth/owner/admin checks tested), no new performance finding. Existing leaked-password protection and historical policy/index advice are not falsely reported as resolved. Guidance: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy and https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable .


Migration 040 additionally protects the community overview and Step 2 histogram with distinct-person thresholds and safe adjacent-bin grouping. No historical row is changed. Tests in `tests/community-summary-privacy.sql` pass; protected totals are displayed as unavailable, never zero, and current cycles do not produce a completed Match outcome.

## v5.2 — scraping and account-abuse controls

- All application data and Auth requests use the same-origin `/api/gateway`.
- BotID Basic is required on gateway and built-in assistant requests. All bot classifications, including verified bots, are rejected. Verification errors fail closed; no development bypass in deployed handlers. No paid Deep Analysis mode is enabled.
- An explicit edge rule denies known AI crawler/user-fetch signatures and common headless-browser signatures. Signatures alone are spoofable. Managed Vercel AI Bots/Bot Protection could not be configured through the connected API (404); this deployment does not claim those managed rules are enabled.
- The Data API pre-request guard requires a server-only proof for anonymous and authenticated requests. User JWTs are forwarded unchanged; existing RLS and ownership rules remain authoritative. Trusted service-role maintenance remains permitted. The proof is stored only in a sensitive Vercel variable; Postgres stores its SHA-256 digest. No service-role credential is introduced.
- Gateway routes, methods and headers are allowlisted. Public directory queries remain capped at 1,000 rows and RPC pagination/ID limits remain in place. Historical public profiles and small cohorts remain visible through normal website queries.
- Atomic Postgres quota reservations apply per HMAC-hashed IP and verified user ID, with separate data, session, authentication and assistant buckets. Requests rejected by upstream Auth still consume their reserved quota. IP addresses, credentials and query bodies are not stored in the quota table. Quotas expire and are purged hourly after two hours.
- This release grants only schema USAGE and EXECUTE on the two new narrow `cme_private` request helpers. All private-table privileges remain revoked; no private API schema is exposed. Prior text saying there is no schema USAGE is superseded for those helpers.
- Static publishing uses an explicit file allowlist. Database imports, migration scripts, server code, documentation and tests are not deployed as downloadable assets.
- CSP, frame isolation, no-snippet/no-index directives, no-store API responses and browser-session token storage reduce exposure. The service worker does not cache API or BotID challenge requests.
- Copy/context-menu/drag and print restrictions plus per-tab watermarks are **deterrents**, not access controls. Form fields remain editable; users can export their own tracker data. Public links remain shareable.

### Limits and outstanding settings

A website cannot prevent OS screenshots, screen recording, external cameras, browser extensions or an authorized viewer copying rendered data. `display-capture=()` only prevents this page from initiating the browser Screen Capture API; it does not stop another application recording the display. Hiding content when the document becomes hidden does not prevent foreground recordings. There is no honest guarantee of detecting every AI-controlled browser or preventing users giving their password to an assistant.

The GitHub repository was confirmed public and contains program import files in its history. Making the repository private requires GitHub account administration in an authenticated session; the connected GitHub tools do not provide a visibility mutation. Merely removing files from the website does not remove public GitHub copies, forks or previously downloaded content. No public Git history is rewritten by this release.

### Deployment order and rollback

1. Apply 042; create a random server secret, store only its SHA-256 in the disabled gateway config, and set the matching sensitive Vercel variable.
2. Deploy the gateway, BotID client, static allowlist and frontend. Verify allowed web requests and reject unsigned automated requests.
3. Activate the Data API pre-request guard only after the deployed gateway is operational. No user data is deleted or rewritten.
4. If the gateway fails, restore the prior frontend only after authorized operators evaluate the gate. Do not silently disable the guard or introduce a public bypass. The previous `authenticator` settings had no `pgrst.db_pre_request`.

Tests: `npm run test:security`, `npm run test:ai`, `tests/web-gateway.sql` (transactional rollback), public-cohort DOM checks, and production HTTP/UI checks. Record production outcomes in the release notes; unit checks are not proof that every browser is correctly classified.
