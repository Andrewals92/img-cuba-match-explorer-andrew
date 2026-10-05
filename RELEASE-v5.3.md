# v5.3 · Professional education and institutional presence

Find programs by documented medical education in Cuba, independently of nationality. Latino presence is institutional aggregate evidence only. No person-level ethnicity/national-origin classification, nationality filters or derived nationality scores are collected or published.

The first reviewed sources document 30 distinct professionals, 32 program affiliations, 9 programs with education evidence and 1 additional program with a Latino aggregate. Ten of 7,469 official programs have partial reviews; none is represented as exhaustively reviewed. The separate 136 community labels retain their identities. Research of the entire catalog remains unfinished and the UI says so.

- Finder: specialty, state/city, time, role, school, educational evidence, class/period, minimum people, institutional Latino data, Non-US IMG interview rate, signal-group interview rate.
- Program Explorer: presence filters and cards. Program profiles: current/historical/uncertain affiliations, schools, PGY/class, sources, dates, confidence and LinkedIn identity matches. Compare: counts and evidence beside existing community, signal and program data.
- Guide, Dashboard and Match Intelligence link this evidence to existing program context. Professional presence does not alter applicant compatibility calculations, predict Match outcomes or serve as a program-quality ranking.
- Analytics: documented programs/people, states, specialties, schools, most-documented programs and Florida shortcut. Counts describe all documented cases at matching programs. Distinct-person counts avoid inflation across affiliations; current and historical sets may overlap.
- Supabase: private RLS tables, audit history, read-only bounded public wrappers, explicit execution grants. All requests still require the existing gateway, BotID and rate limits. The service worker never caches API responses.
- Missing data is unknown. Unverified people never become confirmed results. Source confidence is separate from research completeness. Current evidence older than 365 days or a passed class year becomes uncertain, not silently graduated or deleted.

Five LinkedIn URLs were matched against publicly indexed professional profiles using names and professional institutions/training. Direct LinkedIn page retrieval was unavailable; those links do not supply primary education or affiliation evidence. Other links remain unassigned. University of Miami's 36% institutional Latino figure has no explicit reporting period or unambiguous denominator; the UI preserves that limitation and does not derive individual identities or headcounts.

## Research maintenance

Curated production JSON is excluded from this public repository and the static deployment. It is stored with the private research material and in private database tables; the repository contains only the importer and synthetic validation fixtures.

Run `node scripts/presence-import.cjs /path/to/reviewed-evidence.json` to produce SQL for review. It does not execute it. The importer resolves official ACGME identifiers to current database IDs, rejects sensitive/unknown fields, duplicate identities and invalid LinkedIn URLs, refuses confidence downgrades or older observations, upserts only explicitly reviewed entries, and never deletes absent people. Audit triggers retain prior records. Identity uncertainty requires separate records/manual review; names alone are not sufficient to merge.

A maintenance reviewer should use `presence_reviews.next_review_at <= current_date` to queue due programs, plus new/pending programs from the directory. Sources should be checked for new classes, alumni evidence and staff changes. A disappearance from a roster does not prove graduation; retain the record with `last_seen_unknown` until evidence resolves it. First next-review dates are 2027-01-03. No automatic web-research job or recurring external automation was activated.

The 14-school vocabulary includes manually curated aliases and a separate historical University of Havana faculty. Alias matching supplies candidates for review, not automatic evidence of a person's degree or nationality. Add verified variants with provenance when reviewing new sources.

## Validation

- Transactional SQL assertions (rollback): combined school/role/time filters, no cross-person matches, all 22 Larkin records, distinct-person totals across roles, unverified-row exclusion, aging current evidence, unknown counts, pagination limits, private-table privileges and audit retention.
- DOM checks: school deep links, combined filters, unsafe URLs and HTML escaping, historical sections and unknown-state labels.
- Import checks: public professional evidence only, duplicate detection, evidence requirements, URL identity constraints and nondestructive update rules.
- Existing gateway/security and AI regression suites, static build, and public cohort regression.

GitHub remains public; the separate GitHub visibility and managed Vercel bot-rule decisions from v5.2 have not been changed by this release.
