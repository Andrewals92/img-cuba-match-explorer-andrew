# Cuba Match Explorer v4.3

Interview Wave Tracker and Signal Intelligence extend the existing static application, Program Profiles, Compare, My Match and Watchlist. No framework or Auth migration.

## Release behavior

- Interview Waves filters specialty, cycle, state and program. Weekly Monday buckets have a monthly fallback when a program/cycle has no qualifying weeks. Tables remain readable without relying on color.
- Signal groups follow the existing Gold, Silver, None and Signal taxonomy. Rates appear only for one selected cycle; no cross-cycle signal pooling, causal claims, ranking or probability model.
- Program Profiles and Compare batch community metrics, v4.3 intelligence and external program sources concurrently. Compare supports 2–5 selected programs.
- My Match and Watchlist summarize qualifying observations for the logged-in user's saved programs. Private calendar events and notes never enter these aggregates.
- Wave alerts require a new explicit opt-in, default false. Existing watchlist mute, channels, digest, quiet hours, queue limits and send-time opt-out checks remain effective. One event per program/cycle/week.
- Service-worker cache and asset query versions are v4.3.

## Program sources

Owner supplied 702 Residency Explorer entries for cycle 2026 and 119 Match A Resident complements. Personal likelihoods, alignment, compatibility/order, personal connections, similar-profile outcomes and interview comments were excluded. Only program fields were imported.

All 702 interview-rate entries and 119 complements now map to 702 existing program identities. The final 19 aliases were resolved against official ACGME codes in migration 034. Original aliases and provenance remain internal for audit. No historical applicant/report identifiers were rewritten. Migration 036 fills only missing directory states when linked program locations agree.

Every supplied source URL is retained privately. The public guide groups records by program and exposes institutional websites with neutral labels. All 702 programs have a website; broader institution pages are identified explicitly. Program rates remain separate from community aggregates and have no supplied sample-size denominator. They do not receive community confidence labels or drive alerts.

## Database changes

- 030_wave_signal_intelligence: private canonical observations; program_season_intelligence_v43; specialty_wave_overview_v43.
- 031_program_source_catalog: private program-only source catalog; program_resources_v43; program_source_directory_v43.
- 033_cycle_context: clarifies that all available cycles may include ongoing cycles; timelines remain separate.
- 032_wave_alerts: wave_activity preference; private deduplicated generator; existing notification tick and claim integration; admin-only intelligence_health_v43.

Migrations 030–037 applied successfully. Existing migrations were not rerun or renumbered. Import JSON batches and the location enrichment statement are versioned under supabase/imports.

See ANALYTICS-v4.3.md and VALIDATION-v4.3.md for formulas, tests and acceptance limits. Production acceptance is recorded after deployment; a commit alone is not deployment verification.

MAR enrichment preserves 1,676 program-only core competency, supplemental and highlight fields. Individual survey/comments and personal connections remain excluded.

## v4.3-r3 · Complete IM program guide

- Resolved all 19 remaining source aliases using official ACGME identities. Overland Park uses current participating ID 1402800917; legacy 1401900141 stays separate. Name changes retain original import aliases.
- 821 sanitized records now form 702 unique program cards; 119 complements appear alongside the same program's rates.
- Added 702 institutional links, with explicit institution-level labels when the linked page is broader than a residency page. Known 404/obsolete links found in the audit were replaced. Some institutions block automated requests; the audit records this without claiming all links returned HTTP 200.
- Prominent Gold/Silver/no-signal interview percentages, percentage-point comparisons and a descriptive signals decision aid. No personal likelihood is imported or calculated. No causal claim, winner or program ranking.
- Neutral public labels replace provider branding and extraction-origin notices. Backend provenance remains preserved for maintenance.
- Preserved all program-only clinical requirements, cohort ranges, contact information, highlights and supplemental fields; added program videos and reference-sample application trends. Personal scores, compatibility, personal connections, interview narratives and surveys with undocumented privacy cohorts remain excluded.
- Applied migration 034. Refreshed service-worker cache to v4.3-r3. No Auth/domain changes.

Migration 035 repairs two program links that redirect to sign-in, one soft-404 relocation, and retains a meaningful program URL query parameter. No applicant data or permissions change.

Migration 036 fills missing directory states for all 702 guide programs using their resolved ACGME-linked locations. Guide, direct profile reload and five-program Compare were verified on production; the 360 px layout has no horizontal overflow. The final commit/deployment identifiers are recorded in the accompanying validation receipt.

## Residency website maintenance · migration 037

Verified 53 program-specific destinations, including six existing program homepages previously labeled as broader institutions. The guide now has 688 program-specific and 14 institutional links. URLs were matched to existing ACGME identities, with campus/name checks where needed. Regional restrictions, 403/406 responses and transient gateway failures are recorded separately from evidence establishing a page’s program identity. No access-control bypass or site-content copying was performed. Only URL, website scope and review date changed in the database; rates and applicant data are unchanged. Frontend assets and the v4.3-r3 service-worker cache remain unchanged because this is live metadata maintenance.
