-- Reject ambiguous abbreviations such as EST; use an IANA region or UTC.
do $$begin
 if not exists(select 1 from pg_constraint where conname='interview_events_iana_zone') then
 alter table public.interview_events add constraint interview_events_iana_zone check(timezone='UTC' or timezone ~ '^[A-Za-z_+-]+/[A-Za-z0-9_+/-]+$');
 end if;
end $$;
