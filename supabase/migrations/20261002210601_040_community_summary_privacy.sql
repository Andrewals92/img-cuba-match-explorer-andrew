-- Protect small histogram cells and community totals without changing input rows.
create or replace function public.community_overview(p_cycle integer default null)
returns jsonb language sql stable security definer set search_path='' as $$
with c as materialized (
 select c.*,coalesce(c.user_id::text,nullif(c.anon_id,''),c.id::text) person
 from public.applicant_cycles c where c.consent_public and (p_cycle is null or c.match_cycle=p_cycle)
), r as materialized (
 select pr.* from public.program_reports pr join c on c.id=pr.applicant_cycle_id and c.match_cycle=pr.match_cycle
 where pr.verification_status<>'rejected'
), per as (
 select c.id,c.person,
 greatest(coalesce(c.programs_applied,0),(select count(*) from r where r.applicant_cycle_id=c.id and r.applied)) apps,
 greatest(coalesce(c.interview_invites,0),(select count(*) from r where r.applicant_cycle_id=c.id and r.interview)) ints,
 public.match_cycle_completed(c.match_cycle) completed,
 exists(select 1 from r where r.applicant_cycle_id=c.id and r.matched) matched
 from c
), totals as (
 select count(*) n,count(distinct person) people,sum(apps) apps,sum(ints) ints,
 count(distinct person) filter(where apps>0) application_people,count(distinct person) filter(where ints>0) interview_people,
 count(*) filter(where completed and matched) matches,
 count(distinct person) filter(where completed and matched) matched_people,
 count(distinct person) filter(where completed and not matched) unmatched_people,
 count(distinct person) filter(where not completed) in_progress_people,
 count(distinct person) filter(where completed) completed_people from per
), bins as (
 select label,min(ord) ord,count(*) n,count(distinct person) people from c
 cross join lateral(values
 ('≤220',1,c.step2_ck<=220),('221–230',2,c.step2_ck between 221 and 230),
 ('231–240',3,c.step2_ck between 231 and 240),('241–250',4,c.step2_ck between 241 and 250),('251+',5,c.step2_ck>=251)
 )v(label,ord,ok) where ok group by label
), broad_bins as (
 select label,min(ord) ord,count(*) n,count(distinct person) people from c
 cross join lateral(values('≤240',1,c.step2_ck<=240),('241–250',2,c.step2_ck between 241 and 250),('251+',3,c.step2_ck>=251))v(label,ord,ok)
 where ok group by label
), safe_bins as (
 select * from bins where not exists(select 1 from bins where people<5)
 union all
 select * from broad_bins where exists(select 1 from bins where people<5) and not exists(select 1 from broad_bins where people<5)
)
select jsonb_build_object(
 'applicants',case when t.people>=5 then t.n end,
 'applications',case when t.people>=5 and (t.application_people=0 or t.application_people>=5) and (t.people-t.application_people=0 or t.people-t.application_people>=5) then coalesce(t.apps,0) end,
 'programs',case when t.people>=5 then (select count(distinct coalesce(program_id::text,program_name_snapshot)) from r) end,
 'interviews',case when t.people>=5 and (t.interview_people=0 or t.interview_people>=5) and (t.people-t.interview_people=0 or t.people-t.interview_people>=5) then coalesce(t.ints,0) end,
 'matches',case when t.people>=5 and t.completed_people>=5 and (t.matched_people=0 or t.matched_people>=3) and (t.unmatched_people=0 or t.unmatched_people>=3) and (t.in_progress_people=0 or t.in_progress_people>=5) then t.matches end,
 'step_bins',case when t.people>=5 and (select count(distinct person) from c where step2_ck is null) not between 1 and 4
 then coalesce((select jsonb_agg(jsonb_build_object('label',label,'count',n) order by ord) from safe_bins),'[]'::jsonb) else '[]'::jsonb end,
 'privacy_minimum',5,'step_bins_scope','Consenting cycle profiles; adjacent ranges may be combined to protect small cells.',
 'match_scope','Completed cycles only; an absent report is not a confirmed No Match.'
) from totals t;
$$;
revoke all on function public.community_overview(integer) from public;
grant execute on function public.community_overview(integer) to anon,authenticated;
notify pgrst,'reload schema';
