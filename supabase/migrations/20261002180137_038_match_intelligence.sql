-- v5.0: aggregate-only cohorts and an owner-scoped intelligence workspace.
-- No historical rows, source identifiers, Auth settings or existing RLS policies change.
create or replace function cme_private.cohort_summary_v50(
 p_cycle integer,p_specialty text,p_step2 integer,p_usce numeric,p_lors integer,p_yog integer,
 p_visa_required boolean,p_step2_range integer,p_yog_range integer,p_lors_range integer,p_usce_range numeric,
 p_completed_only boolean default false,p_state text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if (p_cycle is not null and p_cycle not between 2020 and 2100)
 or length(coalesce(p_specialty,''))>100 or (p_step2 is not null and p_step2 not between 1 and 300)
 or (p_yog is not null and p_yog not between 1900 and 2100)
 or (p_usce is not null and p_usce not between 0 and 600)
 or (p_lors is not null and p_lors not between 0 and 100)
 or p_step2_range not between 5 and 100 or p_yog_range not between 1 and 50
 or p_lors_range not between 1 and 20 or p_usce_range not between 1 and 120
 or p_step2_range is null or p_yog_range is null or p_lors_range is null or p_usce_range is null
 or (p_state is not null and p_state !~ '^[A-Z]{2}$') then
 raise exception 'Invalid cohort filters' using errcode='22023'; end if;
 with eligible as materialized (
  select c.*,coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text) person
  from public.applicant_cycles c where c.consent_public
  and (auth.uid() is null or c.user_id is null or c.user_id<>auth.uid())
  and (p_cycle is null or c.match_cycle=p_cycle)
  and (p_specialty is null or lower(c.specialty)=lower(p_specialty))
  and (not p_completed_only or public.match_cycle_completed(c.match_cycle))
 ), filtered as materialized (
  select e.* from eligible e where
  (p_step2 is null or abs(e.step2_ck-p_step2)<=p_step2_range)
  and (p_yog is null or abs(e.yog-p_yog)<=p_yog_range)
  and (p_usce is null or abs(e.usce_months-p_usce)<=p_usce_range)
  and (p_lors is null or abs(e.us_lors-p_lors)<=p_lors_range)
  and (p_visa_required is null or e.visa_required=p_visa_required)
  and (p_state is null or exists(select 1 from public.program_reports r where r.applicant_cycle_id=e.id
    and r.verification_status<>'rejected' and r.match_cycle=e.match_cycle and upper(r.state_snapshot)=p_state))
 ), reports as materialized (
  select coalesce(r.program_id,l.id) program_id,f.person,f.id cycle_id,f.match_cycle,
   bool_or(r.applied and r.source='user') applied,bool_or(r.interview) interview,bool_or(r.matched) matched
  from filtered f join public.program_reports r on r.applicant_cycle_id=f.id and r.match_cycle=f.match_cycle
  left join cme_private.program_labels l on r.program_id is null and l.name=r.program_name_snapshot
    and l.specialty=coalesce(r.specialty,'') and l.state=coalesce(r.state_snapshot,'')
  where r.verification_status<>'rejected'
  group by 1,2,3,4
 ), members as materialized (
  select f.*,public.match_cycle_completed(f.match_cycle) completed,
   exists(select 1 from reports r where r.cycle_id=f.id and r.matched) matched,
   coalesce(f.programs_applied,(select count(*)::integer from reports r where r.cycle_id=f.id and r.applied)) applications,
   coalesce(f.interview_invites,(select count(*)::integer from reports r where r.cycle_id=f.id and r.interview)) interviews
  from filtered f
 ), totals as (
  select count(*) n,count(distinct person) people,
   count(*) filter(where completed) completed,count(distinct person) filter(where completed) completed_people,
   count(*) filter(where not completed) in_progress,count(distinct person) filter(where not completed) progress_people,
   count(*) filter(where completed and matched) matched,count(distinct person) filter(where completed and matched) matched_people,
   count(*) filter(where completed and not matched) no_match_reported,count(distinct person) filter(where completed and not matched) no_match_people,
   count(distinct person) filter(where source like 'import:%') imported_people,
   count(distinct person) filter(where source='user') current_people,
   case when count(distinct person) filter(where step2_ck is not null)>=5 then percentile_cont(.5) within group(order by step2_ck) end step2,
   case when count(distinct person) filter(where yog is not null)>=5 then percentile_cont(.5) within group(order by yog) end yog,
   case when count(distinct person) filter(where usce_months is not null)>=5 then percentile_cont(.5) within group(order by usce_months) end usce,
   case when count(distinct person) filter(where us_lors is not null)>=5 then percentile_cont(.5) within group(order by us_lors) end lors,
   case when count(distinct person) filter(where visa_required)>=5 and count(distinct person) filter(where not visa_required)>=5
     then round(100.0*count(*) filter(where visa_required)/nullif(count(*) filter(where visa_required is not null),0),1) end visa_percent,
   percentile_cont(.5) within group(order by interviews) median_interviews,
   percentile_cont(.5) within group(order by applications) median_applied
  from members
 ), cycle_counts as (
  select match_cycle,count(*) n,count(distinct person) people,public.match_cycle_completed(match_cycle) completed
  from members group by match_cycle
 ), program_counts as (
  select r.program_id,count(distinct person) people,
   count(distinct person) filter(where applied) applications,
   count(distinct person) filter(where interview) interviews,
   count(distinct person) filter(where not interview) no_interview,
   count(distinct person) filter(where matched and public.match_cycle_completed(match_cycle)) matches,
   count(distinct person) filter(where not matched and public.match_cycle_completed(match_cycle)) no_match,
   count(distinct person) filter(where public.match_cycle_completed(match_cycle)) completed
  from reports r group by r.program_id
 ), safe_programs as (
  select d.id,d.name as program,d.name,d.specialty,d.state,d.city,d.acgme_program_id,d.identity_kind,p.people contributors,
   case when p.applications>=5 and (p.people-p.applications=0 or p.people-p.applications>=3) then p.applications end applied,
   case when p.interviews>=3 and (p.no_interview=0 or p.no_interview>=3) then p.interviews end interviews,
   case when p.matches>=3 and (p.no_match=0 or p.no_match>=3) and (p.people-p.completed=0 or p.people-p.completed>=3) then p.matches end matches
  from program_counts p join cme_private.program_directory d on d.id=p.program_id where p.people>=5
 ), state_counts as (
  select d.state,count(distinct r.person) matches from reports r join cme_private.program_directory d on d.id=r.program_id
  where r.matched and public.match_cycle_completed(r.match_cycle) and d.state ~ '^[A-Z]{2}$'
  group by d.state having count(distinct r.person)>=5
 ), impact as (
  select label,count(distinct person) n from eligible e cross join lateral(values
   ('Step 2 CK',p_step2 is null or abs(e.step2_ck-p_step2)<=p_step2_range),
   ('YOG',p_yog is null or abs(e.yog-p_yog)<=p_yog_range),
   ('USCE',p_usce is null or abs(e.usce_months-p_usce)<=p_usce_range),
   ('LoRs',p_lors is null or abs(e.us_lors-p_lors)<=p_lors_range),
   ('Visa',p_visa_required is null or e.visa_required=p_visa_required)) v(label,ok)
  where ok group by label
 )
 select jsonb_build_object('version','5.0','aggregate_only',true,'min_size',5,'protected',t.people<5,
  'eligible_profiles',case when (select count(distinct person) from eligible)>=5 then (select count(*) from eligible) end,
  'cohort_size',case when t.people>=5 then t.n end,'contributors',case when t.people>=5 then t.people end,
  'in_range',case when t.people>=5 then t.n end,'widened',false,'members','[]'::jsonb,
  'completed',case when t.people>=5 and (t.completed_people=0 or t.completed_people>=5) and (t.progress_people=0 or t.progress_people>=5) then t.completed end,
  'in_progress',case when t.people>=5 and (t.completed_people=0 or t.completed_people>=5) and (t.progress_people=0 or t.progress_people>=5) then t.in_progress end,
  'matched',case when t.people>=5 and t.completed_people>=5 and (t.matched_people=0 or t.matched_people>=3) and (t.no_match_people=0 or t.no_match_people>=3) and (t.progress_people=0 or t.progress_people>=5) then t.matched end,
  'no_match',null,'no_match_reported',case when t.people>=5 and t.completed_people>=5 and (t.matched_people=0 or t.matched_people>=3) and (t.no_match_people=0 or t.no_match_people>=3) and (t.progress_people=0 or t.progress_people>=5) then t.no_match_reported end,
  'match_rate',case when t.people>=5 and t.completed_people>=5 and (t.matched_people=0 or t.matched_people>=3) and (t.no_match_people=0 or t.no_match_people>=3) and (t.progress_people=0 or t.progress_people>=5) then round(100.0*t.matched/nullif(t.completed,0),1) end,
  'median_step2',case when t.people>=5 then t.step2 end,'median_yog',case when t.people>=5 then t.yog end,
  'median_usce',case when t.people>=5 then t.usce end,'median_lors',case when t.people>=5 then t.lors end,
  'visa_percent',case when t.people>=5 then t.visa_percent end,
  'median_interviews',case when t.people>=5 then t.median_interviews end,'median_applied',case when t.people>=5 then t.median_applied end,
  'by_cycle',case when t.people>=5 and not exists(select 1 from cycle_counts where people<5) then coalesce((select jsonb_object_agg(match_cycle,n) from cycle_counts),'{}'::jsonb) else '{}'::jsonb end,
  'data_types',case when t.people>=5 then jsonb_build_object('historical_import',t.imported_people>=5,'community_reports',t.current_people>=5) else '{}'::jsonb end,
  'programs',case when t.people>=5 then coalesce((select jsonb_agg(to_jsonb(s) order by s.interviews desc nulls last,s.matches desc nulls last,s.name) from safe_programs s),'[]'::jsonb) else '[]'::jsonb end,
  'states',case when t.people>=5 and (t.no_match_people=0 or t.no_match_people>=3) then coalesce((select jsonb_agg(to_jsonb(s) order by matches desc,state) from state_counts s where t.matched_people-s.matches=0 or t.matched_people-s.matches>=5),'[]'::jsonb) else '[]'::jsonb end,
  'filter_impact',coalesce((select jsonb_agg(jsonb_build_object('filter',label,'contributors',case when n>=5 then n end) order by label) from impact),'[]'::jsonb),
  'filters',jsonb_build_object('cycle',p_cycle,'specialty',p_specialty,'step2',p_step2,'yog',p_yog,'usce',p_usce,'lors',p_lors,'visa_required',p_visa_required,'completed_only',p_completed_only,'geography',p_state),
  'ranges',jsonb_build_object('step2',p_step2_range,'yog',p_yog_range,'lors',p_lors_range,'usce',p_usce_range),
  'uncertainty',case when t.people<5 then 'Insufficient data' when t.people<10 then 'Limited data' when t.people<30 then 'Moderate sample' else 'Larger sample' end,
  'outcome_definition','Completed cycles only. No Match reported is not a verified No Match outcome; in-progress cycles are excluded.',
  'missing_field_policy','A profile missing an actively filtered field is excluded. Ranges are never silently widened.',
  'updated_at',null,'queried_at',now()
 ) into result from totals t;
 return result;
end $$;
revoke all on function cme_private.cohort_summary_v50(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric,boolean,text) from public,anon,authenticated;

-- Backward-compatible signature, but individual imported/profile records never leave the RPC.
create or replace function public.similar_cohort(
 p_cycle integer default null,p_specialty text default null,p_step2 integer default null,p_usce numeric default null,
 p_lors integer default null,p_yog integer default null,p_visa_required boolean default null,p_step2_range integer default 10,
 p_yog_range integer default 5,p_lors_range integer default 1,p_usce_range numeric default 3)
returns jsonb language sql stable security definer set search_path='' as $$
 select cme_private.cohort_summary_v50(p_cycle,p_specialty,p_step2,p_usce,p_lors,p_yog,p_visa_required,p_step2_range,p_yog_range,p_lors_range,p_usce_range,false,null);
$$;
revoke all on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) from public;
grant execute on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) to anon,authenticated;

-- This function accepts an owned cycle UUID, never a user ID or arbitrary profile.
create or replace function public.match_intelligence_v50(p_profile_id uuid,p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.applicant_cycles; f jsonb:=coalesce(p_filters,'{}');cohort jsonb;programs jsonb;
 cy integer;st text;query text;completed_only boolean;include_sparse boolean;active_only boolean;sig text;minimum integer;off integer;
 ids uuid[];seasons jsonb;total_ids integer;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501';end if;
 select * into c from public.applicant_cycles where id=p_profile_id and user_id=auth.uid();
 if c.id is null then raise exception 'Owned cycle profile required' using errcode='42501';end if;
 if jsonb_typeof(f)<>'object' or octet_length(f::text)>3000 or exists(select 1 from jsonb_object_keys(f) k where k not in
  ('cycle','step2_range','yog_range','usce_range','lors_range','match_visa','use_step2','use_yog','use_usce','use_lors','completed_only','state','cohort_state','include_sparse','active_only','signal','minimum_sample','query','offset')) then raise exception 'Invalid filters' using errcode='22023';end if;
 cy:=(f->>'cycle')::integer;st:=nullif(upper(f->>'state'),'');query:=coalesce(f->>'query','');sig:=nullif(f->>'signal','');
 completed_only:=coalesce((f->>'completed_only')::boolean,false);include_sparse:=coalesce((f->>'include_sparse')::boolean,true);active_only:=coalesce((f->>'active_only')::boolean,false);
 minimum:=coalesce((f->>'minimum_sample')::integer,5);off:=coalesce((f->>'offset')::integer,0);
 if (st is not null and st !~ '^[A-Z]{2}$') or length(query)>120 or minimum not between 5 and 100 or off not between 0 and 10000
 or (sig is not null and sig not in ('Gold','Silver','None','Signal')) then raise exception 'Invalid discovery filters' using errcode='22023';end if;
 cohort:=cme_private.cohort_summary_v50(cy,c.specialty,
  case when coalesce((f->>'use_step2')::boolean,true) then c.step2_ck end,
  case when coalesce((f->>'use_usce')::boolean,true) then c.usce_months end,
  case when coalesce((f->>'use_lors')::boolean,true) then c.us_lors end,
  case when coalesce((f->>'use_yog')::boolean,true) then c.yog end,
  case when coalesce((f->>'match_visa')::boolean,true) then c.visa_required end,
  coalesce((f->>'step2_range')::integer,10),coalesce((f->>'yog_range')::integer,5),coalesce((f->>'lors_range')::integer,1),coalesce((f->>'usce_range')::numeric,3),completed_only,nullif(upper(f->>'cohort_state'),''));
 with candidates as (
  select d.id,d.name,coalesce((e->>'interviews')::integer,0) activity from cme_private.program_directory d
  left join jsonb_array_elements(cohort->'programs') e on (e->>'id')::uuid=d.id
  where d.active and lower(d.specialty)=lower(c.specialty) and (st is null or d.state=st)
  and (query='' or concat_ws(' ',d.name,d.city,d.acgme_program_id) ilike '%'||query||'%')
  and (include_sparse or (e->>'contributors')::integer>=minimum)
  and (not active_only or exists(select 1 from cme_private.canonical_program_observations_v43 o where o.program_id=d.id
   and o.match_cycle=c.match_cycle and o.interview and o.invitation_date between current_date-41 and current_date group by date_trunc('week',o.invitation_date::timestamp) having count(distinct o.person)>=3))
  and (sig is null or exists(select 1 from cme_private.canonical_program_observations_v43 o where o.program_id=d.id and o.match_cycle=coalesce(cy,c.match_cycle) and o.applied and o.signal=sig
   group by o.program_id having count(distinct o.person)>=5 and (count(distinct o.person) filter(where o.interview)=0 or count(distinct o.person) filter(where o.interview)>=3)
   and (count(distinct o.person) filter(where not o.interview)=0 or count(distinct o.person) filter(where not o.interview)>=3)))
  order by activity desc,d.name,d.id limit 31 offset off
 ) select array_agg(id order by activity desc,name,id),count(*) into ids,total_ids from candidates;
 if ids is not null then
  ids:=ids[1:30];seasons:=public.program_season_intelligence_v43(ids,coalesce(cy,c.match_cycle));
  select jsonb_agg(to_jsonb(d)||jsonb_build_object('cohort_evidence',e,'season',s,
   'saved',exists(select 1 from public.user_program_watchlist w where w.program_id=d.id and w.user_id=auth.uid()),
   'reasons',to_jsonb(array_remove(array[
     'Coincide con tu especialidad',case when st is not null then 'Está en tu estado seleccionado' end,
     case when e->>'interviews' is not null then 'Entrevistas documentadas en la cohorte comparable' end,
     case when e->>'matches' is not null then 'Matches documentados en ciclos completos comparables' end,
     case when s->>'activity' in ('Active now','Recent activity') then 'Actividad comunitaria reciente visible' end,
     case when e is null then 'Datos comparables insuficientes: mostrado por tus filtros explícitos' end],null))) order by array_position(ids,d.id))
  into programs from cme_private.program_directory d
  left join jsonb_array_elements(cohort->'programs') e on (e->>'id')::uuid=d.id
  left join jsonb_array_elements(seasons) s on (s->>'id')::uuid=d.id where d.id=any(ids);
 end if;
 return jsonb_build_object('profile',jsonb_build_object('id',c.id,'cycle',c.match_cycle,'specialty',c.specialty,
  'step2',c.step2_ck,'yog',c.yog,'usce',c.usce_months,'lors',c.us_lors,'visa_required',c.visa_required),
  'cohort',cohort,'programs',coalesce(programs,'[]'::jsonb),'has_more',total_ids>30,'offset',off,
  'ordering','Observed comparable interview frequency, then name. This is not a program quality ranking.',
  'activity_cycle',coalesce(cy,c.match_cycle));
end $$;
revoke all on function public.match_intelligence_v50(uuid,jsonb) from public,anon;
grant execute on function public.match_intelligence_v50(uuid,jsonb) to authenticated;
comment on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) is 'v5 aggregate-only; no individual profiles or raw import output, no silent widening, own profiles excluded, distinct-person and complementary suppression.';
notify pgrst,'reload schema';
