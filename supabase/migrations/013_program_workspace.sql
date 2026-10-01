-- Cuba Match Explorer v4.0. Additive; never rewrites historical reports.
create schema if not exists cme_private;
revoke all on schema cme_private from public, anon, authenticated;
create table if not exists cme_private.program_labels (
 id uuid primary key default gen_random_uuid(),
 name text not null, specialty text not null, state text not null,
 unique(name,specialty,state)
);
alter table cme_private.program_labels enable row level security;
revoke all on cme_private.program_labels from public, anon, authenticated;
-- These UUIDs describe reporting labels, NOT asserted official identities.
insert into cme_private.program_labels(name,specialty,state)
select distinct r.program_name_snapshot, coalesce(r.specialty,''), coalesce(r.state_snapshot,'')
from public.program_reports r join public.applicant_cycles c on c.id=r.applicant_cycle_id
where r.program_id is null and c.consent_public and r.program_name_snapshot is not null
on conflict(name,specialty,state) do nothing;

create or replace view cme_private.program_directory as
select p.id,p.name,p.specialty,p.city,p.state,p.acgme_program_id,p.institution,
 'official'::text identity_kind,p.active,p.updated_at directory_updated_at
from public.programs p
union all
select l.id,l.name,l.specialty,null::text,l.state,null::text,null::text,
 'community_label',true,null::timestamptz from cme_private.program_labels l;
revoke all on cme_private.program_directory from public,anon,authenticated;

create or replace function public.program_directory_v4(
 p_query text default '', p_specialty text default null, p_kind text default 'all', p_offset integer default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object('programs',coalesce(jsonb_agg(to_jsonb(d) order by d.name,d.id),'[]'::jsonb),
 'has_more',count(*)>40) from (
 select * from cme_private.program_directory d where d.active
 and (p_specialty is null or d.specialty=p_specialty)
 and (p_kind='all' or d.identity_kind=p_kind)
 and (coalesce(p_query,'')='' or concat_ws(' ',d.name,d.specialty,d.city,d.state,d.acgme_program_id,d.institution)
 ilike '%'||left(p_query,160)||'%') order by d.name,d.id
 limit 41 offset greatest(0,least(coalesce(p_offset,0),50000))) d;
$$;
revoke all on function public.program_directory_v4(text,text,text,integer) from public;
grant execute on function public.program_directory_v4(text,text,text,integer) to anon,authenticated;

-- Single batched endpoint for both profile (one UUID) and compare (2-5).
-- No user identifiers, individual records, notes or unprotected small counts leave this function.
create or replace function public.program_compare_stats(p_ids uuid[],p_cycle integer default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
 if coalesce(cardinality(p_ids),0)<1 or cardinality(p_ids)>5 then
   raise exception 'Select between 1 and 5 program IDs' using errcode='22023';
 end if;
 if p_cycle is not null and (p_cycle<2020 or p_cycle>2100) then
   raise exception 'Invalid cycle' using errcode='22023';
 end if;
 with directory as materialized (
   select * from cme_private.program_directory where id=any(p_ids)
 ), raw as materialized (
   select coalesce(r.program_id,l.id) program_id,c.id cycle_id,
    coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text) person,
    c.match_cycle,c.step2_ck,c.yog,c.usce_months,c.us_lors,c.visa_required,
    r.applied and r.source='user' application,
    r.interview,r.matched,r.signal,r.interview_date,r.updated_at
   from public.program_reports r join public.applicant_cycles c on c.id=r.applicant_cycle_id
   left join cme_private.program_labels l on r.program_id is null
    and l.name=r.program_name_snapshot and l.specialty=coalesce(r.specialty,'') and l.state=coalesce(r.state_snapshot,'')
   where coalesce(r.program_id,l.id)=any(p_ids) and c.consent_public
    and r.verification_status<>'rejected' and r.match_cycle=c.match_cycle
    and (p_cycle is null or c.match_cycle=p_cycle)
 ), cohort as materialized (
   -- Duplicate detailed reports never increase the contributor count or rates.
   select program_id,cycle_id,person,match_cycle,step2_ck,yog,usce_months,us_lors,visa_required,
    bool_or(application) application,bool_or(interview) interview,bool_or(matched) matched,
    bool_or(signal='Gold') gold,bool_or(signal='Silver') silver,
    bool_or(signal='None') no_signal,bool_or(signal='Signal') other_signal
   from raw group by program_id,cycle_id,person,match_cycle,step2_ck,yog,usce_months,us_lors,visa_required
 ), aggregates as (
   select program_id,count(distinct person) n,count(*) reports,
    count(*) filter(where application) applications,
    count(distinct person) filter(where application) application_n,
    count(*) filter(where interview) interviews,
    count(distinct person) filter(where interview) interview_n,
    count(*) filter(where application and interview) app_interviews,
    count(distinct person) filter(where application and interview) app_interview_n,
    count(distinct person) filter(where application and not interview) app_no_interview_n,
    count(*) filter(where matched and public.match_cycle_completed(match_cycle)) matches,
    count(distinct person) filter(where matched and public.match_cycle_completed(match_cycle)) match_n,
    count(*) filter(where application and public.match_cycle_completed(match_cycle)) completed_apps,
    count(distinct person) filter(where application and public.match_cycle_completed(match_cycle)) completed_n,
    count(*) filter(where matched and application and public.match_cycle_completed(match_cycle)) app_matches,
    count(distinct person) filter(where matched and application and public.match_cycle_completed(match_cycle)) app_match_n,
    count(distinct person) filter(where not matched and application and public.match_cycle_completed(match_cycle)) app_no_match_n,
    count(distinct person) filter(where gold) gold_n,
    count(distinct person) filter(where silver) silver_n,
    count(distinct person) filter(where no_signal) none_n,
    count(distinct person) filter(where other_signal) other_n,
    case when count(distinct person) filter(where step2_ck is not null)>=5 then percentile_cont(.5) within group(order by step2_ck) end step2,
    case when count(distinct person) filter(where yog is not null)>=5 then percentile_cont(.5) within group(order by yog) end yog,
    case when count(distinct person) filter(where usce_months is not null)>=5 then percentile_cont(.5) within group(order by usce_months) end usce,
    case when count(distinct person) filter(where us_lors is not null)>=5 then percentile_cont(.5) within group(order by us_lors) end lors,
    count(distinct person) filter(where visa_required) visa_yes,
    count(distinct person) filter(where not visa_required) visa_no
   from cohort group by program_id
 ), month_counts as (
   select program_id,to_char(interview_date,'YYYY-MM') as activity_month,count(distinct cycle_id) invitations,
    count(distinct person) contributors from raw where interview and interview_date is not null
   group by program_id,to_char(interview_date,'YYYY-MM')
 ), timelines as (
   select program_id,jsonb_agg(jsonb_build_object('month',activity_month,'invitations',invitations) order by activity_month) timeline,
    max(activity_month) last_activity_month from month_counts where contributors>=3 group by program_id
 )
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object(
   'cycle',p_cycle,'data_state',case when a.n is null then 'no_reports' when a.n<5 then 'insufficient' else 'available' end,
   'applicant_profiles',case when a.n>=5 then a.reports end,
   'applications',case when a.application_n>=5 then a.applications end,
   'interviews',case when a.interview_n>=3 then a.interviews end,
   'interview_rate',case when a.application_n>=5 and a.app_interview_n>=3 and (a.app_no_interview_n=0 or a.app_no_interview_n>=3)
     then round(100.0*a.app_interviews/nullif(a.applications,0),1) end,
   'matches',case when a.match_n>=3 then a.matches end,
   'match_rate',case when a.completed_n>=5 and a.app_match_n>=3 and (a.app_no_match_n=0 or a.app_no_match_n>=3)
     then round(100.0*a.app_matches/nullif(a.completed_apps,0),1) end,
   'signals',case when a.n>=5 and (a.gold_n=0 or a.gold_n>=3) and (a.silver_n=0 or a.silver_n>=3)
     and (a.none_n=0 or a.none_n>=3) and (a.other_n=0 or a.other_n>=3)
     then jsonb_build_object('gold',nullif(a.gold_n,0),'silver',nullif(a.silver_n,0),'none',nullif(a.none_n,0),'other',nullif(a.other_n,0)) end,
   'characteristics',jsonb_build_object('step2',a.step2,'yog',a.yog,'usce',a.usce,'lors',a.lors,
      'visa_percent',case when a.visa_yes>=5 and a.visa_no>=5 then round(100.0*a.visa_yes/(a.visa_yes+a.visa_no),1) end),
   'timeline',coalesce(t.timeline,'[]'::jsonb),'last_activity_month',t.last_activity_month,
   'accreditation',(select jsonb_build_object('status',e.accreditation_status,'effective_date',e.effective_date,'last_seen_at',e.last_seen_at)
      from public.accreditation_events e where e.acgme_program_id=d.acgme_program_id order by e.last_seen_at desc limit 1),
   'links',coalesce((select jsonb_agg(jsonb_build_object('source',s.source,'url',s.source_url))
     from public.program_external_sources s where s.program_id=d.id or s.acgme_program_id=d.acgme_program_id),'[]'::jsonb)
 ) order by array_position(p_ids,d.id)),'[]'::jsonb) into result
 from directory d left join aggregates a on a.program_id=d.id left join timelines t on t.program_id=d.id;
 return result;
end;
$$;
revoke all on function public.program_compare_stats(uuid[],integer) from public;
grant execute on function public.program_compare_stats(uuid[],integer) to anon,authenticated;

-- Metadata resolution only. Never infer identity from display name alone.
-- Ambiguous matches are intentionally unresolved, and lead to directory search.
create or replace function public.program_identity_index_v4()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'specialty',specialty,'state',state)),'[]'::jsonb)
 from cme_private.program_directory where identity_kind='community_label';
$$;
revoke all on function public.program_identity_index_v4() from public;
grant execute on function public.program_identity_index_v4() to anon,authenticated;

create or replace function public.program_workspace_health_v4()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501'; end if;
 return jsonb_build_object('version','4.0','official_programs',(select count(*) from public.programs),
 'community_labels',(select count(*) from cme_private.program_labels),
 'programs_with_reports',(select count(*) from (select distinct program_id,program_name_snapshot,specialty,state_snapshot from public.program_reports) x),
 'last_report_update',(select max(updated_at) from public.program_reports));
end;
$$;
revoke all on function public.program_workspace_health_v4() from public,anon;
grant execute on function public.program_workspace_health_v4() to authenticated;
comment on function public.program_compare_stats(uuid[],integer) is 'v4 privacy-safe aggregate endpoint. >=5 distinct contributors for characteristics/applications; >=3 outcomes/timeline. No raw records. Imported invitations never imply applications.';
notify pgrst,'reload schema';
