# v4.3 analytics and sources

Canonical community observation: latest valid, consented source=user report for a person/program/Match cycle, ordered by updated_at then report UUID. Person identity uses user_id, then anon_id, then cycle ID. Program uses an existing UUID or the established exact community-label identity. Duplicate rows cannot inflate any v4.3 denominator. Original reports remain unchanged.

Invitation date means program_reports.interview_date, labeled Fecha invitación in Mis datos. No interview start time, private interview_events column or report creation timestamp substitutes for it. Only dates from July 1 before the Match year through June 30 of the Match year, and not in the future, qualify. Imported 2026 invitation rows contain no dates and cannot populate waves.

Weekly buckets start Monday using timestamp-without-timezone date_trunc. A program/cycle with no disclosed weekly bucket falls back to monthly buckets. Each disclosed bucket has at least 3 distinct people. Below-threshold buckets are absent, never zero-valued counts. No week/signal/applicant-characteristic intersection endpoint is exposed.

Activity labels use the latest disclosed bucket's start date: Active now if within 13 days, Recent activity if within 41 days, Earlier activity otherwise; Insufficient data if no bucket is disclosed. These labels refer to observed qualifying periods, not real program operating status. First/latest visible periods describe the community sample, not the program's true invitation season boundaries.

Signal denominator: distinct canonical people with applied=true in the selected program/cycle/signal group. Numerator: the same cohort with interview=true. Rate = 100 * numerator / denominator, rounded to one decimal. Disclosure requires denominator >=5 and each outcome subgroup either zero or >=3. If a subgroup fails, denominator, numerator and rate all return null. This preserves existing complementary-outcome privacy. Gold/Silver/None/Signal stay mutually exclusive because one latest row is selected. All-cycles signals are suppressed to avoid incompatible season rules. Unknown signal allocations are never inferred.

Community sample wording: fewer than 10 disclosed applications = limited; 10–29 = moderate sample; >=30 = more community data available. These descriptions concern sample size, not reliability, model confidence or personal odds. Match rates in the existing endpoint continue to use match_cycle_completed.

Source catalog: source_key is the stable RE source URL or MAR normalized ACGME key. Upsert preserves one row per source entry. 821 source entries are not 821 unique residency programs. The raw XLSX files and applicant-specific columns are not committed. Sanitized program JSON is split into 25-row batches. The extraction allowlist is auditable; raw comments and personal connection/compatibility sections are excluded wholesale. Source rates are decimal fractions displayed as percentages and cannot be combined with community numerators. Missing denominators remain unknown.

Official fallback links verified October 2, 2026: Trident (ACGME 1404500407), NHS Tahlequah/OMECO (1403900355, linked by NRMP), PCOM Internal Medicine (1404100902), Rochester (1403511313). URLs are preserved in the program-only JSON fields, with their verification date. No bulk scraping of protected services occurred.

No materialization or additional refresh job is needed at current scale. The 30-program overview measured 45.834 ms server execution during validation. Profiles/Compare make three independent batched calls concurrently. Saved-program summaries use batches of up to 50; the existing private season metadata loader remains unchanged.

MAR enrichment preserves 1,676 program-only core competency, supplemental and highlight fields. Individual survey/comments and personal connections remain excluded.
