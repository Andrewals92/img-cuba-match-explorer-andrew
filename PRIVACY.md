# Privacy — v4.0

Existing applicant-cycle and program-report tables retain RLS. Imported applicants have no ordinary user owner and remain unreadable through raw-table queries to anonymous/normal accounts. Existing Applicant Explorer's threshold-protected anonymized cohort behavior remains; Program Profiles and Compare never return applicant rows.

The new public aggregate endpoint accepts 1–5 program UUIDs and an optional cycle. It requires consent, excludes rejected/inconsistent-cycle reports, deduplicates program reports per applicant cycle and counts distinct contributors for disclosure thresholds. Application counts and characteristic medians need at least 5 contributors; individual characteristic fields independently need 5 non-null contributors. Interview and completed-cycle Match counts and dated months need 3. Rates require valid application denominators and protect small outcome complements. Visa percentages require at least 5 people in each boolean category. Signal distributions are suppressed when a nonzero category has fewer than 3 contributors.

Suppressed and absent values are null, not zero. Imported invitation-only reports do not establish an application denominator. Monthly dates and latest visible activity are exposed only from eligible months, never from an individual's exact latest report timestamp. Public official-directory update dates are separate.

Personal totals and details remain on the authenticated own-data path. Only compare UUIDs and selected personal profile UUIDs are added to localStorage; v4 does not copy applicant data into a new browser store. Existing authentication storage remains unchanged. Compare URLs contain program IDs and cycle only.

The private identity registry stores reporting labels, specialty and state, with generated UUIDs. It stores no applicant IDs. Labels are not asserted to be official programs. New manual labels are registered only from consented profiles. Removing consent excludes their report data from aggregates; non-personal program metadata can remain in the directory.

Threshold suppression reduces disclosure risk; it is not differential privacy. Existing public analytics and anonymized comparable-cohort APIs remain under their prior policies. Do not interpret absence of activity as evidence about an individual.
