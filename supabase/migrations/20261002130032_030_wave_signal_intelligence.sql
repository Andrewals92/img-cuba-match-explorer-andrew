-- v4.3: only consented public contribution reports, never private tracker events.
create or replace view cme_private.canonical_program_observations_v43 as
select distinct on (coalesce(r.program_id,l.id),coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text),c.match_cycle)
 coalesce(r.program_id,l.id) program_id,
 coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text) person,
 c.match_cycle,r.applied,r.interview,r.signal,r.interview_date invitation_date,r.updated_at
from public.program_reports r join public.applicant_cycles c on c.id=r.applicant_cycle_id
left join cme_private.program_labels l on r.program_id is null and l.name=r.program_name_snapshot
 and l.specialty=coalesce(r.specialty,'') and l.state=coalesce(r.state_snapshot,'')
where c.consent_public and r.source='user' and r.verification_status<>'rejected' and r.match_cycle=c.match_cycle
order by coalesce(r.program_id,l.id),coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text),c.match_cycle,r.updated_at desc,r.id desc;
revoke all on cme_private.canonical_program_observations_v43 from public,anon,authenticated;

create or replace function public.program_season_intelligence_v43(p_ids uuid[],p_cycle integer default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;
begin
 if coalesce(cardinality(p_ids),0)<1 or cardinality(p_ids)>50 then raise exception 'Select 1 to 50 programs' using errcode='22023';end if;
 if p_cycle is not null and (p_cycle<2020 or p_cycle>2100) then raise exception 'Invalid cycle' using errcode='22023';end if;
 with raw as materialized (select * from cme_private.canonical_program_observations_v43
  where program_id=any(p_ids) and (p_cycle is null or match_cycle=p_cycle)),
 weeks as (select program_id,match_cycle,date_trunc('week',invitation_date::timestamp)::date period,count(distinct person) n
  from raw where interview and invitation_date is not null and invitation_date<=current_date
  and invitation_date>=make_date(match_cycle-1,7,1) and invitation_date<make_date(match_cycle,7,1)
  group by 1,2,3 having count(distinct person)>=3),
 months as (select program_id,match_cycle,date_trunc('month',invitation_date::timestamp)::date period,count(distinct person) n
  from raw where interview and invitation_date is not null and invitation_date<=current_date
  and invitation_date>=make_date(match_cycle-1,7,1) and invitation_date<make_date(match_cycle,7,1)
  group by 1,2,3 having count(distinct person)>=3),
 buckets as (select w.*,'week'::text resolution from weeks w union all
  select m.*,'month' from months m where not exists(select 1 from weeks w where w.program_id=m.program_id and w.match_cycle=m.match_cycle)),
 timelines as (select program_id,jsonb_agg(jsonb_build_object('cycle',match_cycle,'period',period,'resolution',resolution,'reports',n) order by match_cycle,period) timeline,
  min(period) first_period,max(period) latest_period,count(*) periods,array_agg(distinct match_cycle order by match_cycle) cycles
  from buckets group by program_id),
 groups as (select program_id,signal,count(distinct person) n,count(distinct person) filter(where interview) yes,
  count(distinct person) filter(where not interview) no from raw
  where p_cycle is not null and applied and signal in ('Gold','Silver','None','Signal') group by 1,2),
 safe_signals as (select program_id,jsonb_agg(jsonb_build_object('signal',signal,
  'applications',case when n>=5 and (yes=0 or yes>=3) and (no=0 or no>=3) then n end,
  'interviews',case when n>=5 and (yes=0 or yes>=3) and (no=0 or no>=3) then yes end,
  'rate',case when n>=5 and (yes=0 or yes>=3) and (no=0 or no>=3) then round(100.0*yes/n,1) end,
  'state',case when n>=5 and (yes=0 or yes>=3) and (no=0 or no>=3) then 'available' else 'insufficient' end) order by signal) signals
  from groups group by program_id)
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'specialty',d.specialty,'state',d.state,
  'cycle',p_cycle,'context',case when p_cycle is null then 'Historical aggregate · cycles kept separate' when public.match_cycle_completed(p_cycle) then 'Historical completed cycle' else 'Current / incomplete cycle' end,
  'timeline',coalesce(t.timeline,'[]'::jsonb),'first_period',t.first_period,'latest_period',t.latest_period,
  'qualifying_periods',coalesce(t.periods,0),'cycles',coalesce(to_jsonb(t.cycles),'[]'::jsonb),
  'activity',case when t.latest_period>=current_date-13 then 'Active now' when t.latest_period>=current_date-41 then 'Recent activity' when t.latest_period is not null then 'Earlier activity' else 'Insufficient data' end,
  'signals',coalesce(s.signals,'[]'::jsonb),'signal_state',case when p_cycle is null then 'Select a specific cycle' else 'Cycle-specific observations' end
 ) order by array_position(p_ids,d.id)),'[]'::jsonb) into answer
 from cme_private.program_directory d left join timelines t on t.program_id=d.id left join safe_signals s on s.program_id=d.id where d.id=any(p_ids);
 return answer;
end $$;
revoke all on function public.program_season_intelligence_v43(uuid[],integer) from public;
grant execute on function public.program_season_intelligence_v43(uuid[],integer) to anon,authenticated;

create or replace function public.specialty_wave_overview_v43(p_specialty text default null,p_cycle integer default null,p_state text default null,p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];answer jsonb;
begin
 select array_agg(id order by name,id) into ids from (select d.id,d.name from cme_private.program_directory d
  where d.active and (p_specialty is null or lower(d.specialty)=lower(left(p_specialty,100)))
  and (p_state is null or upper(d.state)=upper(left(p_state,2)))
  and (coalesce(p_query,'')='' or d.name ilike '%'||left(p_query,160)||'%')
  order by d.name,d.id limit 30 offset greatest(0,least(coalesce(p_offset,0),50000))) x;
 if ids is null then return jsonb_build_object('programs','[]'::jsonb);end if;
 answer:=public.program_season_intelligence_v43(ids,p_cycle);
 return jsonb_build_object('programs',answer,'has_more',cardinality(ids)=30);
end $$;
revoke all on function public.specialty_wave_overview_v43(text,integer,text,text,integer) from public;
grant execute on function public.specialty_wave_overview_v43(text,integer,text,text,integer) to anon,authenticated;
comment on function public.program_season_intelligence_v43(uuid[],integer) is 'Latest consented user report per person/program/cycle. Invitation dates only. Wave >=3 distinct people; signals >=5 plus zero-or->=3 outcome complements. No signals pooled across cycles. No private tracker access.';
