# Cuba Match Explorer v4.0

Release date: 2026-10-01. Deployment verification is recorded separately in VALIDATION-v4.0.md.

## Changes

Program Profiles expose stable UUID hash links, catalog/accreditation information, official service links, a cycle selector, privacy-safe community metrics, signal summaries, characteristic medians and dated monthly activity. Unknown/suppressed data is never fabricated.

Program Compare selects 2–5 programs, persists UUIDs in localStorage, supports shared URLs and cycle filtering, warns about cross-specialty comparisons, and provides an intentional horizontal scrolling region on small screens. No winners, predictions or overall scores are generated.

My Match uses the user's own selected profile. It displays declared totals separately from detailed records, signal usage with unknown quotas explicitly labeled, attended/ranked programs, reported Match status, a CSS progression visualization and non-blocking completeness prompts. An absent completed-cycle result is labeled “Sin resultado reportado”, not assumed No Match.

Program names link to profiles from the directory, intelligence, community tables and personal reports where a UUID or unique composite identity is available. Ambiguous identities open directory search rather than silently choosing a program.

The existing comparable-cohort RPC now receives the signed-in session so its existing server-side exclusion of the caller's own profiles actually applies. Anonymous access remains available as before. Auth endpoints, production redirect construction and Admin operations are preserved.

## Database and privacy

013 adds a private stable identity registry and narrow aggregate/directory/health RPCs. 014 maintains identities for newly consented manual reports and adds indexes for program/source joins identified by the performance advisor. 015 normalizes directory specialty filtering across official/community capitalization. No existing migration or import identifier is rewritten. No raw applicant API is added.

Historical reporting labels remain separate from official identities. The import lacks invitation dates and complete application denominators, so timelines and rates can correctly be unavailable. Matching a reporting label to an official program requires future verified curation.

Cache version is `cuba-match-explorer-v4.0`; versioned script/CSS URLs use `v=4.0`. The service worker caches same-origin static assets only and no longer returns HTML for a missing offline JavaScript asset.

## Scope and limitations

No framework migration, FREIDA/Residency Explorer scraping, auth redesign, or large Admin redesign. Signal quotas are not stored, so availability is unknown. Monthly activity includes only cells with at least three distinct contributors; a missing cell does not mean zero invitations. Directory freshness and visible activity freshness are different measures.

All-cycle aggregates count applicant-cycle reports; thresholds count distinct people where identity is available. Community self-reports are not representative population statistics or predictions.

Created and owned by Andrew A Lopez Sanchez, MD, MBA.  
© 2026 Andrew A Lopez Sanchez, MD, MBA. All rights reserved.
