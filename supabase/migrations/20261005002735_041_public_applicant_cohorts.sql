-- Public, pseudonymous applicant details requested by the site owner.
-- No raw-table grants or RLS changes; consent and owner-only private records remain.
alter table public.applicant_cycles add column if not exists match_outcome text
 check (match_outcome in ('matched','no_match'));

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
 ), raw_reports as materialized (
  select r.*,coalesce(r.program_id,l.id) resolved_id,
   coalesce(r.program_id::text,l.id::text,concat_ws('|',r.program_name_snapshot,r.specialty,r.state_snapshot)) program_key,
   f.person
  from filtered f join public.program_reports r on r.applicant_cycle_id=f.id and r.match_cycle=f.match_cycle
  left join cme_private.program_labels l on r.program_id is null and l.name=r.program_name_snapshot
    and l.specialty=coalesce(r.specialty,'') and l.state=coalesce(r.state_snapshot,'')
  where r.verification_status<>'rejected'
 ), reports as materialized (
  -- One current observation per applicant-cycle/program, including one signal.
  select distinct on(applicant_cycle_id,program_key) * from raw_reports
  order by applicant_cycle_id,program_key,updated_at desc nulls last,created_at desc,id
 ), members as materialized (
  select f.*,public.match_cycle_completed(f.match_cycle) completed,
   coalesce(f.programs_applied,nullif(a.apps,0)) applications,
   coalesce(f.interview_invites,nullif(a.ints,0)) interviews,
   a.apps detailed_applications,a.ints detailed_interviews,a.programs,
   a.matched_programs,a.signals,
   case when a.has_match or f.match_outcome='matched' then 'matched'
    when not public.match_cycle_completed(f.match_cycle) then 'in_progress'
    when f.match_outcome='no_match' then 'no_match' else 'not_reported' end status,
   (f.match_outcome='no_match' and a.has_match) outcome_conflict,
   coalesce(abs(f.step2_ck-p_step2)/5.0,0)+coalesce(abs(f.yog-p_yog)/3.0,0)
    +coalesce(abs(f.usce_months-p_usce)/2.0,0)+coalesce(abs(f.us_lors-p_lors)*1.5,0) distance
  from filtered f cross join lateral (
   select count(*) filter(where r.applied)::integer apps,count(*) filter(where r.interview)::integer ints,
    coalesce(bool_or(r.matched),false) has_match,
    coalesce(jsonb_agg(jsonb_build_object('id',r.resolved_id,'program',r.program_name_snapshot,
     'state',r.state_snapshot,'specialty',r.specialty,'applied',r.applied,'interview',r.interview,
     'signal',r.signal,'matched',r.matched) order by r.program_name_snapshot,r.program_key),'[]'::jsonb) programs,
    coalesce(jsonb_agg(jsonb_build_object('id',r.resolved_id,'program',r.program_name_snapshot,'state',r.state_snapshot)
     order by r.program_name_snapshot) filter(where r.matched),'[]'::jsonb) matched_programs,
    jsonb_build_object('Gold',count(*) filter(where signal='Gold'),'Silver',count(*) filter(where signal='Silver'),
     'Signal',count(*) filter(where signal='Signal'),'None',count(*) filter(where signal='None')) signals
   from reports r where r.applicant_cycle_id=f.id
  ) a
 ), public_members as (
  select distance,id, jsonb_build_object(
   'label','Aplicante '||upper(substr(md5(id::text),1,12)),
   'cycle',match_cycle,'specialty',specialty,'historical',source like 'import:%',
   'step1',step1_status,'step1_attempts',step1_attempts,'step2',step2_ck,'step3',step3,
   'yog',yog,'us_lors',us_lors,'usce',usce_months,'usce_type',usce_type,
   'ecfmg',ecfmg_status,'publications',publications,'research_projects',research_projects,
   'previous_residency',previous_residency_outside_us,'visa_required',visa_required,
   'programs_applied',applications,'interviews',interviews,
   'applications_scope',case when programs_applied is not null then 'declared' when detailed_applications>0 then 'documented_only' else 'unknown' end,
   'interviews_scope',case when interview_invites is not null then 'declared' when detailed_interviews>0 then 'documented_only' else 'unknown' end,
   'detailed_applications',detailed_applications,'detailed_interviews',detailed_interviews,
   'totals_conflict',(programs_applied<detailed_applications or interview_invites<detailed_interviews or interviews>applications),
   'status',status,'matched',case when status='matched' then true when status='no_match' then false end,
   'outcome_conflict',outcome_conflict,'match_programs',matched_programs,'signals',signals,'programs',programs
  ) j from members
 ), program_counts as (
  select r.program_key,max(r.resolved_id::text)::uuid id,max(r.program_name_snapshot) name,
   max(r.specialty) specialty,max(r.state_snapshot) state,count(distinct person) contributors,
   count(distinct person) filter(where applied) applied,count(distinct person) filter(where interview) interviews,
   count(distinct person) filter(where matched and public.match_cycle_completed(match_cycle)) matches
  from reports r group by r.program_key
 ), program_results as (
  select p.*,p.name program,d.city,d.acgme_program_id,coalesce(d.identity_kind,'community_label') identity_kind
  from program_counts p left join cme_private.program_directory d on d.id=p.id
 ), totals as (
  select count(*) n,count(distinct person) people,count(*) filter(where completed) completed,
   count(*) filter(where not completed) in_progress,count(*) filter(where completed and status='matched') matched,
   count(*) filter(where completed and status='no_match') no_match,
   count(*) filter(where completed and status='not_reported') not_reported,
   sum(applications) applications,sum(interviews) interviews,
   count(applications) application_profiles,count(interviews) interview_profiles,
   percentile_cont(.5) within group(order by step2_ck) step2,percentile_cont(.5) within group(order by yog) yog,
   percentile_cont(.5) within group(order by usce_months) usce,percentile_cont(.5) within group(order by us_lors) lors,
   percentile_cont(.5) within group(order by interviews) median_interviews,
   percentile_cont(.5) within group(order by applications) median_applied,
   round(100.0*count(*) filter(where visa_required)/nullif(count(visa_required),0),1) visa_percent,
   bool_or(source like 'import:%') imported,bool_or(source='user') community
  from members
 ), impact as (
  select label,count(distinct person) n from eligible e cross join lateral(values
   ('Step 2 CK',p_step2 is null or abs(e.step2_ck-p_step2)<=p_step2_range),
   ('YOG',p_yog is null or abs(e.yog-p_yog)<=p_yog_range),
   ('USCE',p_usce is null or abs(e.usce_months-p_usce)<=p_usce_range),
   ('LoRs',p_lors is null or abs(e.us_lors-p_lors)<=p_lors_range),
   ('Visa',p_visa_required is null or e.visa_required=p_visa_required)) v(label,ok)
  where ok group by label
 )
 select jsonb_build_object('version','5.1','aggregate_only',false,'min_size',1,'protected',false,
  'eligible_profiles',(select count(*) from eligible),'cohort_size',t.n,'contributors',t.people,
  'in_range',t.n,'widened',false,'members',coalesce((select jsonb_agg(j order by distance,id) from public_members),'[]'::jsonb),
  'completed',t.completed,'in_progress',t.in_progress,'matched',t.matched,'no_match',t.no_match,
  'no_match_reported',t.no_match+t.not_reported,'outcome_not_reported',t.not_reported,
  'match_rate',round(100.0*t.matched/nullif(t.completed,0),1),
  'total_applications',t.applications,'total_interviews',t.interviews,
  'application_profiles',t.application_profiles,'interview_profiles',t.interview_profiles,
  'median_step2',t.step2,'median_yog',t.yog,'median_usce',t.usce,'median_lors',t.lors,
  'visa_percent',t.visa_percent,'median_interviews',t.median_interviews,'median_applied',t.median_applied,
  'by_cycle',coalesce((select jsonb_object_agg(match_cycle,n) from (select match_cycle,count(*) n from members group by match_cycle) b),'{}'::jsonb),
  'data_types',jsonb_build_object('historical_import',coalesce(t.imported,false),'community_reports',coalesce(t.community,false)),
  'programs',coalesce((select jsonb_agg(to_jsonb(p)-'program_key' order by p.interviews desc,p.matches desc,p.name,p.id) from program_results p),'[]'::jsonb),
  'states',coalesce((select jsonb_agg(to_jsonb(s) order by matches desc,state) from (
   select state_snapshot state,count(distinct person) matches from reports where matched and public.match_cycle_completed(match_cycle)
   and state_snapshot ~ '^[A-Z]{2}$' group by state_snapshot) s),'[]'::jsonb),
  'filter_impact',coalesce((select jsonb_agg(jsonb_build_object('filter',label,'contributors',n) order by label) from impact),'[]'::jsonb),
  'filters',jsonb_build_object('cycle',p_cycle,'specialty',p_specialty,'step2',p_step2,'yog',p_yog,'usce',p_usce,'lors',p_lors,'visa_required',p_visa_required,'completed_only',p_completed_only,'geography',p_state),
  'ranges',jsonb_build_object('step2',p_step2_range,'yog',p_yog_range,'lors',p_lors_range,'usce',p_usce_range),
  'uncertainty',case when t.people=0 then 'Insufficient data' when t.people<10 then 'Limited data' when t.people<30 then 'Moderate sample' else 'Larger sample' end,
  'outcome_definition','Only explicit No Match outcomes are negative; missing outcomes are not reported. In-progress cycles stay separate.',
  'missing_field_policy','Profiles missing an actively filtered field are excluded. No widening or small-sample suppression.',
  'updated_at',null,'queried_at',now()
 ) into result from totals t;
 return result;
end $$;
revoke all on function cme_private.cohort_summary_v50(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric,boolean,text) from public,anon,authenticated;
comment on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric)
 is 'v5.1 public consented pseudonymous profiles and program reports; no minimum cohort threshold; no private notes, account IDs, contact information or raw imports.';
notify pgrst,'reload schema';

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
 minimum:=coalesce((f->>'minimum_sample')::integer,1);off:=coalesce((f->>'offset')::integer,0);
 if (st is not null and st !~ '^[A-Z]{2}$') or length(query)>120 or minimum not between 1 and 100 or off not between 0 and 10000
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

notify pgrst,'reload schema';
