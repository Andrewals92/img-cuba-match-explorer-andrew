-- Cuba Match Explorer v3.3 — repair migration
-- Safe to run more than once. Run AFTER schema.sql, 002 and 003.
--
-- Why: the original schema.sql failed while creating program_stats() and
-- recent_interview_activity() ("column interviews/week_start does not exist"
-- — SQL functions cannot ORDER BY an output alias). Because the Supabase SQL
-- editor aborts on the first error, every RPC defined after that point
-- (dashboard, Program Explorer, Interview Tracker, Match Map, Applicant
-- Explorer, admin verification, delete_my_data) may be missing in production.
-- This migration (re)creates all of them with the fix applied.

-- ---------- Public aggregate RPCs ----------
drop function if exists public.program_stats(integer,text);
create function public.program_stats(p_cycle integer default null,p_specialty text default null)
returns table(program_name text,state text,specialty text,applicants bigint,applications bigint,interviews bigint,matches bigint,interview_rate numeric,median_step2 numeric,median_usce numeric,median_lors numeric)
security definer set search_path=public language sql stable as $$
with c as (
  select * from applicant_cycles
  where consent_public and (p_cycle is null or match_cycle=p_cycle) and (p_specialty is null or specialty=p_specialty)
), j as (
  select pr.*, c.step2_ck, c.usce_months, c.us_lors
  from program_reports pr join c on c.id=pr.applicant_cycle_id
)
select program_name_snapshot,
       max(state_snapshot),
       max(j.specialty),
       count(distinct applicant_cycle_id),
       count(*) filter(where applied),
       count(*) filter(where interview),
       count(*) filter(where matched),
       round(100.0*count(*) filter(where interview)/nullif(count(*) filter(where applied),0),1),
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by step2_ck) filter(where step2_ck is not null))::numeric end,
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by usce_months))::numeric end,
       case when count(distinct applicant_cycle_id)>=5 then (percentile_cont(.5) within group(order by us_lors))::numeric end
from j
group by program_name_snapshot
having count(*) filter(where applied)>0
order by 6 desc, 5 desc;
$$;

drop function if exists public.recent_interview_activity(integer,text);
create function public.recent_interview_activity(p_cycle integer default null,p_specialty text default null)
returns table(program_name text,specialty text,week_start date,reports bigint,verified bigint)
security definer set search_path=public language sql stable as $$
select pr.program_name_snapshot,
       max(pr.specialty),
       date_trunc('week',pr.interview_date)::date,
       count(*),
       count(*) filter(where pr.verification_status='verified')
from program_reports pr
join applicant_cycles c on c.id=pr.applicant_cycle_id
where c.consent_public and pr.interview and pr.interview_date is not null
  and (p_cycle is null or pr.match_cycle=p_cycle)
  and (p_specialty is null or pr.specialty=p_specialty)
group by pr.program_name_snapshot, date_trunc('week',pr.interview_date)
having count(*)>=3
order by 3 desc, 4 desc
limit 100;
$$;

create or replace function public.community_overview(p_cycle integer default null) returns jsonb
security definer set search_path=public language sql stable as $$
with c as (select * from applicant_cycles where consent_public and (p_cycle is null or match_cycle=p_cycle)),
r as (select pr.* from program_reports pr join c on c.id=pr.applicant_cycle_id),
bins as (select jsonb_build_array(
  jsonb_build_object('label','≤220','count',count(*) filter(where step2_ck<=220)),
  jsonb_build_object('label','221–230','count',count(*) filter(where step2_ck between 221 and 230)),
  jsonb_build_object('label','231–240','count',count(*) filter(where step2_ck between 231 and 240)),
  jsonb_build_object('label','241–250','count',count(*) filter(where step2_ck between 241 and 250)),
  jsonb_build_object('label','251+','count',count(*) filter(where step2_ck>=251))) j from c)
select jsonb_build_object(
  'applicants',(select count(*) from c),
  'applications',(select count(*) from r where applied),
  'programs',(select count(distinct coalesce(program_id::text,program_name_snapshot)) from r where applied),
  'interviews',(select count(*) from r where interview),
  'matches',(select count(*) from r where matched),
  'step_bins',(select j from bins));
$$;

drop function if exists public.match_state_stats(integer);
create function public.match_state_stats(p_cycle integer default null) returns table(state text,matches bigint)
security definer set search_path=public language sql stable as $$
select pr.state_snapshot, count(*)
from program_reports pr join applicant_cycles c on c.id=pr.applicant_cycle_id
where c.consent_public and pr.matched and (p_cycle is null or pr.match_cycle=p_cycle) and pr.state_snapshot is not null
group by pr.state_snapshot
order by 2 desc;
$$;

drop function if exists public.match_program_stats(integer);
create function public.match_program_stats(p_cycle integer default null) returns table(program_name text,state text,matches bigint)
security definer set search_path=public language sql stable as $$
select pr.program_name_snapshot, max(pr.state_snapshot), count(*)
from program_reports pr join applicant_cycles c on c.id=pr.applicant_cycle_id
where c.consent_public and pr.matched and (p_cycle is null or pr.match_cycle=p_cycle)
group by pr.program_name_snapshot
having count(*)>=3
order by 3 desc;
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
  order by dist limit 30
), meta as (
  select count(*) n,
    (percentile_cont(.5) within group(order by step2_ck) filter(where step2_ck is not null))::numeric s2,
    (percentile_cont(.5) within group(order by usce_months))::numeric usce,
    (percentile_cont(.5) within group(order by us_lors))::numeric lors
  from ranked
), rr as (select pr.* from program_reports pr join ranked r on r.id=pr.applicant_cycle_id)
select rr.program_name_snapshot, max(rr.state_snapshot),
       count(*) filter(where applied), count(*) filter(where interview), count(*) filter(where matched),
       meta.n, meta.s2, meta.usce, meta.lors
from rr cross join meta
where meta.n>=5
group by rr.program_name_snapshot, meta.n, meta.s2, meta.usce, meta.lors
order by 4 desc, 3 desc;
$$;

-- ---------- Admin / moderation RPCs ----------
create or replace function public.admin_pending_verifications()
returns table(id uuid,anon_id text,program_name text,match_cycle integer,interview boolean,matched boolean,verification_note text,created_at timestamptz)
security definer set search_path=public language plpgsql stable as $$
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  return query select pr.id,c.anon_id,pr.program_name_snapshot,pr.match_cycle,pr.interview,pr.matched,pr.verification_note,pr.created_at
  from program_reports pr join applicant_cycles c on c.id=pr.applicant_cycle_id
  where pr.verification_status='pending' order by pr.created_at;
end$$;

create or replace function public.admin_set_verification(p_report_id uuid,p_status text,p_note text default null) returns void
security definer set search_path=public language plpgsql as $$
declare old_status text;
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  if p_status not in ('verified','rejected') then raise exception 'Invalid status'; end if;
  select verification_status into old_status from program_reports where id=p_report_id for update;
  if old_status is null then raise exception 'Report not found'; end if;
  update program_reports set verification_status=p_status, verification_note=coalesce(p_note,verification_note),
    verified_at=case when p_status='verified' then now() else null end, verified_by=auth.uid()
  where id=p_report_id;
  insert into moderation_audit(moderator_user_id,report_id,previous_status,new_status,note)
  values(auth.uid(),p_report_id,old_status,p_status,p_note);
end$$;

-- Security definer so the admin sees true totals (watch subscriptions are owner-only under RLS).
create or replace function public.admin_site_summary() returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_admin() then return null; end if;
  return jsonb_build_object(
    'users',(select count(*) from public.profiles),
    'admins',(select count(*) from public.profiles where role='admin'),
    'cycles',(select count(*) from public.applicant_cycles),
    'reports',(select count(*) from public.program_reports),
    'programs',(select count(*) from public.programs),
    'watch_subscriptions',(select count(*) from public.program_watch_subscriptions),
    'pending_verifications',(select count(*) from public.program_reports where verification_status='pending'));
end$$;

create or replace function public.admin_set_user_role(p_user_id uuid, p_role text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  if p_role not in ('user','moderator','admin') then raise exception 'Invalid role'; end if;
  if p_user_id = auth.uid() and p_role <> 'admin' then
    raise exception 'Current administrator cannot remove own admin role';
  end if;
  update public.profiles set role=p_role, updated_at=now() where id=p_user_id;
end$$;

-- Removes everything the user created (profiles by cycle, reports via cascade, alerts, notifications).
create or replace function public.delete_my_data() returns void
security definer set search_path=public language plpgsql as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from applicant_cycles where user_id=auth.uid();
  delete from program_watch_subscriptions where user_id=auth.uid();
  delete from notifications where user_id=auth.uid();
  update profiles set display_name=null where id=auth.uid();
end$$;

-- ---------- Grants ----------
revoke all on function public.community_overview(integer),public.program_stats(integer,text),public.recent_interview_activity(integer,text),public.match_state_stats(integer),public.match_program_stats(integer),public.similar_programs(integer,text,integer,numeric,integer,integer,boolean) from public;
grant execute on function public.community_overview(integer),public.program_stats(integer,text),public.recent_interview_activity(integer,text),public.match_state_stats(integer),public.match_program_stats(integer),public.similar_programs(integer,text,integer,numeric,integer,integer,boolean) to anon,authenticated;
revoke all on function public.admin_pending_verifications(),public.admin_set_verification(uuid,text,text),public.delete_my_data(),public.admin_site_summary(),public.admin_set_user_role(uuid,text) from public, anon;
grant execute on function public.admin_pending_verifications(),public.admin_set_verification(uuid,text,text),public.delete_my_data(),public.admin_site_summary(),public.admin_set_user_role(uuid,text) to authenticated;
grant execute on function public.new_accredited_programs(text,text,timestamptz) to anon, authenticated;

-- Tell PostgREST to reload its schema cache so the new functions are callable immediately.
notify pgrst, 'reload schema';
