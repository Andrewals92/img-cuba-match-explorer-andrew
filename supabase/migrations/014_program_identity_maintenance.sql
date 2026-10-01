-- Support new manual reports without rewriting report UUIDs or inferring official identity.
create or replace function cme_private.register_program_label()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='program_reports' then
  insert into cme_private.program_labels(name,specialty,state)
  select new.program_name_snapshot,coalesce(new.specialty,''),coalesce(new.state_snapshot,'')
  where new.program_id is null and exists(select 1 from public.applicant_cycles c where c.id=new.applicant_cycle_id and c.consent_public)
  on conflict(name,specialty,state) do nothing;
 elsif new.consent_public then
  insert into cme_private.program_labels(name,specialty,state)
  select distinct r.program_name_snapshot,coalesce(r.specialty,''),coalesce(r.state_snapshot,'')
  from public.program_reports r where r.applicant_cycle_id=new.id and r.program_id is null
  on conflict(name,specialty,state) do nothing;
 end if;
 return new;
end;
$$;
revoke all on function cme_private.register_program_label() from public,anon,authenticated;
drop trigger if exists v4_report_program_label on public.program_reports;
create trigger v4_report_program_label after insert or update of program_id,program_name_snapshot,specialty,state_snapshot
on public.program_reports for each row execute function cme_private.register_program_label();
drop trigger if exists v4_cycle_program_labels on public.applicant_cycles;
create trigger v4_cycle_program_labels after update of consent_public on public.applicant_cycles
for each row execute function cme_private.register_program_label();
-- Advisor-identified foreign-key joins used by the v4 profile endpoint.
create index if not exists program_reports_program_v4_idx on public.program_reports(program_id,match_cycle);
create index if not exists program_external_sources_program_v4_idx on public.program_external_sources(program_id);
notify pgrst,'reload schema';
