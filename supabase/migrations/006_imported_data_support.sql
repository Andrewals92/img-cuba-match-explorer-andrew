-- Cuba Match Explorer v3.5 — support for community data imported by an admin
-- Safe to run more than once. Run AFTER 005_admin_delete_user.sql.
--
-- Imported rows (e.g. from the CubaMatch_2026.xlsx community sheet) do not
-- belong to any user account: user_id is NULL and `source` identifies the batch
-- ('import:CubaMatch_2026'). Normal users cannot read them (RLS), they only
-- feed the privacy-protected aggregates; admins can see and delete them.

-- ---------- applicant_cycles ----------
alter table public.applicant_cycles add column if not exists source text not null default 'user';
alter table public.applicant_cycles add column if not exists programs_applied integer check (programs_applied is null or programs_applied between 0 and 2000);
alter table public.applicant_cycles add column if not exists interview_invites integer check (interview_invites is null or interview_invites between 0 and 2000);
alter table public.applicant_cycles alter column user_id drop not null;
-- Unknown values in imported data stay NULL instead of a misleading 0.
alter table public.applicant_cycles alter column yog drop not null;
alter table public.applicant_cycles alter column usce_months drop not null;
alter table public.applicant_cycles alter column us_lors drop not null;
alter table public.applicant_cycles alter column us_physician_lors drop not null;
alter table public.applicant_cycles alter column publications drop not null;
alter table public.applicant_cycles alter column research_projects drop not null;
alter table public.applicant_cycles drop constraint if exists applicant_cycles_owner_check;
alter table public.applicant_cycles add constraint applicant_cycles_owner_check
  check (user_id is not null or source <> 'user');
create index if not exists applicant_cycles_source_idx on public.applicant_cycles(source);

-- ---------- program_reports ----------
alter table public.program_reports add column if not exists source text not null default 'user';
alter table public.program_reports alter column user_id drop not null;
alter table public.program_reports drop constraint if exists program_reports_owner_check;
alter table public.program_reports add constraint program_reports_owner_check
  check (user_id is not null or source <> 'user');
-- 'Signal' = single-tier signal (Family Medicine, Neurology, Pediatrics, ...).
alter table public.program_reports drop constraint if exists program_reports_signal_check;
alter table public.program_reports add constraint program_reports_signal_check
  check (signal in ('None','Silver','Gold','Signal'));
create index if not exists program_reports_source_idx on public.program_reports(source);

-- ---------- Triggers ----------
-- Users (and the REST API) can never create or relabel rows as imported.
create or replace function public.force_user_source() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'UPDATE' then new.source := old.source; else new.source := 'user'; end if;
  end if;
  return new;
end$$;
drop trigger if exists trg_cycles_force_source on public.applicant_cycles;
create trigger trg_cycles_force_source before insert or update on public.applicant_cycles
  for each row execute function public.force_user_source();
drop trigger if exists trg_reports_force_source on public.program_reports;
create trigger trg_reports_force_source before insert or update on public.program_reports
  for each row execute function public.force_user_source();

-- Report insert: unchanged for users; a trusted SQL-editor import (no JWT,
-- source <> 'user', cycle without owner) keeps the values it provides.
create or replace function public.prepare_report_insert() returns trigger
security definer set search_path=public language plpgsql as $$
declare c public.applicant_cycles%rowtype; p public.programs%rowtype;
begin
  select * into c from public.applicant_cycles where id=new.applicant_cycle_id;
  if auth.uid() is null and new.source <> 'user' and c.id is not null and c.user_id is null then
    new.user_id := null;
    new.match_cycle := coalesce(new.match_cycle, c.match_cycle);
    new.specialty := coalesce(new.specialty, c.specialty);
    return new;
  end if;
  if c.id is null or c.user_id is distinct from auth.uid() then
    raise exception 'Applicant cycle does not belong to current user';
  end if;
  new.user_id:=auth.uid(); new.match_cycle:=c.match_cycle; new.specialty:=c.specialty;
  if new.program_id is not null then
    select * into p from public.programs where id=new.program_id;
    if p.id is not null then new.program_name_snapshot:=p.name; new.state_snapshot:=p.state; new.specialty:=p.specialty; end if;
  end if;
  if new.verification_requested then new.verification_status:='pending'; else new.verification_status:='unverified'; end if;
  new.verified_at:=null; new.verified_by:=null;
  return new;
end$$;

create or replace function public.protect_report_update() returns trigger
security definer set search_path=public language plpgsql as $$
declare critical boolean;
begin
  if public.is_admin() or (auth.uid() is null and old.user_id is null) then return new; end if;
  if old.user_id is distinct from auth.uid() then raise exception 'Not allowed'; end if;
  new.user_id:=old.user_id; new.applicant_cycle_id:=old.applicant_cycle_id; new.match_cycle:=old.match_cycle; new.specialty:=old.specialty;
  critical := old.program_id is distinct from new.program_id or old.program_name_snapshot is distinct from new.program_name_snapshot or old.applied is distinct from new.applied or old.signal is distinct from new.signal or old.interview is distinct from new.interview or old.interview_date is distinct from new.interview_date or old.ranked is distinct from new.ranked or old.matched is distinct from new.matched or old.track is distinct from new.track;
  if critical then new.verification_status:=case when new.verification_requested then 'pending' else 'unverified' end; new.verified_at:=null; new.verified_by:=null;
  else new.verification_status:=old.verification_status; new.verified_at:=old.verified_at; new.verified_by:=old.verified_by; end if;
  return new;
end$$;

-- ---------- Aggregates aware of applicant-level totals ----------
-- Imported applicants report "programs applied" and "invitations" as totals,
-- not one row per application. Overview uses the larger of the two sources.
create or replace function public.community_overview(p_cycle integer default null) returns jsonb
security definer set search_path=public language sql stable as $$
with c as (select * from applicant_cycles where consent_public and (p_cycle is null or match_cycle=p_cycle)),
r as (select pr.* from program_reports pr join c on c.id=pr.applicant_cycle_id),
per as (
  select c.id,
    greatest(coalesce(c.programs_applied,0), (select count(*) from r where r.applicant_cycle_id=c.id and r.applied)) apps,
    greatest(coalesce(c.interview_invites,0), (select count(*) from r where r.applicant_cycle_id=c.id and r.interview)) ints
  from c),
bins as (select jsonb_build_array(
  jsonb_build_object('label','≤220','count',count(*) filter(where step2_ck<=220)),
  jsonb_build_object('label','221–230','count',count(*) filter(where step2_ck between 221 and 230)),
  jsonb_build_object('label','231–240','count',count(*) filter(where step2_ck between 231 and 240)),
  jsonb_build_object('label','241–250','count',count(*) filter(where step2_ck between 241 and 250)),
  jsonb_build_object('label','251+','count',count(*) filter(where step2_ck>=251))) j from c)
select jsonb_build_object(
  'applicants',(select count(*) from c),
  'applications',(select coalesce(sum(apps),0) from per),
  'programs',(select count(distinct coalesce(program_id::text,program_name_snapshot)) from r),
  'interviews',(select coalesce(sum(ints),0) from per),
  'matches',(select count(*) from r where matched),
  'step_bins',(select j from bins));
$$;

-- Program level: imported data only lists interview invitations, so the
-- per-program application count and interview rate come from user reports only
-- (NULL when there is no such data, shown as "—").
drop function if exists public.program_stats(integer,text);
create function public.program_stats(p_cycle integer default null,p_specialty text default null)
returns table(program_name text,state text,specialty text,applicants bigint,applications bigint,interviews bigint,matches bigint,interview_rate numeric,median_step2 numeric,median_usce numeric,median_lors numeric)
security definer set search_path=public language sql stable as $$
with c as (
  select * from applicant_cycles
  where consent_public and (p_cycle is null or match_cycle=p_cycle)
), j as (
  select pr.*, c.step2_ck, c.usce_months, c.us_lors
  from program_reports pr join c on c.id=pr.applicant_cycle_id
  where (p_specialty is null or pr.specialty=p_specialty)
)
select program_name_snapshot,
       max(state_snapshot),
       max(j.specialty),
       count(distinct applicant_cycle_id),
       count(*) filter(where applied and source='user'),
       count(*) filter(where interview),
       count(*) filter(where matched),
       round(100.0*count(*) filter(where interview and source='user')/nullif(count(*) filter(where applied and source='user'),0),1),
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by step2_ck) filter(where step2_ck is not null))::numeric end,
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by usce_months) filter(where usce_months is not null))::numeric end,
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by us_lors) filter(where us_lors is not null))::numeric end
from j
group by program_name_snapshot, j.specialty
having count(*) filter(where applied or interview)>0
order by 6 desc, 5 desc;
$$;

drop function if exists public.similar_programs(integer,text,integer,numeric,integer,integer,boolean);
create function public.similar_programs(p_cycle integer default null,p_specialty text default null,p_step2 integer default null,p_usce numeric default null,p_lors integer default null,p_yog integer default null,p_visa_required boolean default null)
returns table(program_name text,state text,applications bigint,interviews bigint,matches bigint,cohort_size bigint,median_step2 numeric,median_usce numeric,median_lors numeric)
security definer set search_path=public language sql stable as $$
with ranked as (
  select c.*,
    coalesce(abs(c.step2_ck-p_step2),0)/5.0 + coalesce(abs(c.usce_months-p_usce),0)/2.0 + coalesce(abs(c.us_lors-p_lors),0)*1.5 + coalesce(abs(c.yog-p_yog),0)/3.0
    + case when p_visa_required is not null and c.visa_required<>p_visa_required then 4 else 0 end as dist
  from applicant_cycles c
  where c.consent_public and (p_cycle is null or c.match_cycle=p_cycle) and (p_specialty is null or c.specialty=p_specialty)
    and c.step2_ck is not null
  order by dist limit 30
), meta as (
  select count(*) n,
    (percentile_cont(.5) within group(order by step2_ck) filter(where step2_ck is not null))::numeric s2,
    (percentile_cont(.5) within group(order by usce_months) filter(where usce_months is not null))::numeric usce,
    (percentile_cont(.5) within group(order by us_lors) filter(where us_lors is not null))::numeric lors
  from ranked
), rr as (select pr.* from program_reports pr join ranked r on r.id=pr.applicant_cycle_id)
select rr.program_name_snapshot, max(rr.state_snapshot),
       count(*) filter(where applied and source='user'), count(*) filter(where interview), count(*) filter(where matched),
       meta.n, meta.s2, meta.usce, meta.lors
from rr cross join meta
where meta.n>=5
group by rr.program_name_snapshot, meta.n, meta.s2, meta.usce, meta.lors
order by 4 desc, 3 desc;
$$;

revoke all on function public.program_stats(integer,text), public.similar_programs(integer,text,integer,numeric,integer,integer,boolean) from public;
grant execute on function public.community_overview(integer), public.program_stats(integer,text), public.similar_programs(integer,text,integer,numeric,integer,integer,boolean) to anon, authenticated;

notify pgrst, 'reload schema';
