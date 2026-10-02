# v4.2 validation

## Verified

- GitHub main baseline bca0e383bf7e146592cb25a0529bc30cd3dfb3bc. Live v4.1 static assets HTTP 200 and byte-equal before edits. Existing authenticated admin login, empty My Match/Tracker/watchlist, Mis datos forms and Admin controls observed in the prior acceptance continuation.
- Historical integrity before/after DDL: 36 imported profiles, 338 detailed invitation rows, 14 matches; zero exact duplicate payload groups (excluding generated row ID/timestamps). Repeated same-program reports may be distinct historical rows; no import identifier or row was rewritten.
- Transactional SQL fixtures rolled back: A/B/anonymous isolation, notification content write denial, unread/read controls, server-only outbox, admin authorization, Radar specialty/state filtering and deterministic deduplication, first status baseline/change/formatting semantics, generic private reminders, overnight quiet hours including DST, daily digest deduplication, transient backoff and five-attempt terminal failure.
- Existing production privacy/role/admin and season A/B/admin SQL suites rerun after 029 pass (rolled-back fixtures). Existing calendar DST/ICS/privacy tests, personal declared-total tests, private Tracker/watchlist/calendar DOM CRUD/cycle/signout tests pass.
- Full anonymous DOM startup, directory, five-program compare, hash profile, session selection persistence pass without script errors.
- Notification DOM: badge/read controls, escaping, unsafe-route fallback, preference/quiet/digest persistence, Radar filters and signout clearing pass. These DOM sessions are simulated, not real authenticated browser sessions.
- Edge dispatcher authenticated cron request responds HTTP 200. VAPID initialized privately; push-ready true, email-ready false. Unauthorized requests cannot invoke privileged config/claim APIs.
- Advisors reviewed after migration 028; ownership/send-time fix 029 adds a unique endpoint index and narrows delivery eligibility. New internal tables intentionally deny ordinary access with RLS/no policies. Public Radar and authenticated channel/operations RPCs intentionally use narrow SECURITY DEFINER; operations checks admin. No new private-table exposure. Notification accreditation FK index added. New unused-index information is expected before real traffic. Prior Auth leaked-password warning and older RLS/permissive-policy warnings remain baseline findings.

## Pending acceptance / external dependencies

- Resend connection, server secret provisioning and verified branded sender domain/DNS. No actual email send or receipt/SPF/DKIM/DMARC verification.
- Real supported-browser push opt-in, multi-device subscriptions, background receipt/click and terminal 404/410 integration. Backend terminal handling implemented; SQL/DOM simulation is not actual push transport.
- Full production mobile/Android PWA acceptance, console inspection where browser credential protection allows, installed-v4.1 service-worker upgrade path.
- Signup confirmation and recovery actual delivered-email links, normal-user real UI CRUD and regression acceptance. Working production Auth configuration is unchanged.
- Production Vercel Ready/alias and post-deploy source-byte checks are recorded after deployment.

## Advisor references

- https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Production publication evidence

- Initial v4.2 source commit `c513c706d229f6b06cca9d6f455dc95c87e0968f`; Vercel project overview displayed Production Deployment, Ready, main and matching source. Deployment `dpl_9umy9EMoyNBw851hmsq1La6Sdpvb`. Production alias unchanged: https://cuba-match-explorer.vercel.app/ .
- Eight principal assets returned HTTP 200 and byte-equal to v4.2 source. Browser displayed v4.2 and authenticated navigation, including Notifications and preferences. The first private-center attempt failed because private RPCs inherited anonymous mode; the follow-up fix explicitly passes authenticated mode and a DOM regression asserts it. Native credential protection prevented technical console inspection; real post-fix center/push acceptance remains pending.
- Historical integrity reconfirmed after publication: 36 | 338 | 14.
