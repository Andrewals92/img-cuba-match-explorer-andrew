-- Production indexes used by Applicant Explorer / all-cycle cohort comparisons.
create index if not exists program_reports_applicant_cycle_idx
  on public.program_reports (applicant_cycle_id);

create index if not exists applicant_cycles_cohort_lookup_idx
  on public.applicant_cycles (specialty, match_cycle, consent_public, step2_ck)
  where consent_public = true;
