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

683 RE entries map uniquely to the existing ACGME directory by normalized name, city and specialty. All 119 MAR entries map by normalized ACGME ID. The 19 unresolved RE entries remain separately browsable, with their own RE link and no attributed community metrics. Location fills only missing states when linked sources agree. No historical applicant/report identifiers were rewritten.

Every supplied RE entry retains its individual source URL. The four MAR programs without a linked RE entry have institutional websites verified against primary sources. Other institutional websites were not individually researched; source links are labeled accurately. External rates are shown separately and have no supplied sample-size denominator. They do not receive community confidence labels or drive alerts.

## Database changes

- 030_wave_signal_intelligence: private canonical observations; program_season_intelligence_v43; specialty_wave_overview_v43.
- 031_program_source_catalog: private program-only source catalog; program_resources_v43; program_source_directory_v43.
- 032_wave_alerts: wave_activity preference; private deduplicated generator; existing notification tick and claim integration; admin-only intelligence_health_v43.

All three migrations applied successfully. Existing migrations were not rerun or renumbered. Import JSON batches and the location enrichment statement are versioned under supabase/imports.

See ANALYTICS-v4.3.md and VALIDATION-v4.3.md for formulas, tests and acceptance limits. Production acceptance is recorded after deployment; a commit alone is not deployment verification.

MAR enrichment preserves 1,676 program-only core competency, supplemental and highlight fields. Individual survey/comments and personal connections remain excluded.
