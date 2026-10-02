-- Cover the composite owner/cycle FK; replace the redundant single-column index.
create index if not exists interview_events_cycle_owner on public.interview_events(applicant_cycle_id,user_id);
drop index if exists public.interview_events_cycle;
