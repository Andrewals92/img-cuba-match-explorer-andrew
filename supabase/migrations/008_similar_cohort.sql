-- Cuba Match Explorer v3.6 — Applicant Explorer: comparable cohort detail
-- Safe to run more than once. Run AFTER 006_imported_data_support.sql.
--
-- similar_cohort() answers, for the profile typed in Applicant Explorer:
--   * how many applicants fall inside the chosen range (in_range)
--   * the comparable cohort, one anonymous row per applicant: scores, programs
--     applied (count), interviews received (count + which programs) and
--     whether / where they matched
--   * the programs where that cohort interviewed / matched
-- Privacy: only consent_public profiles; no ids, anon ids, notes or
-- immigration text are returned; details only when the cohort has >= 5 people.

-- Internal helper: candidate pool with distance and range flag.
create or replace function public._similar_cohort_pool(
  p_cycle integer, p_specialty text, p_step2 integer, p_usce numeric, p_lors integer,
  p_yog integer, p_visa_required boolean, p_step2_range integer, p_yog_range integer,
  p_lors_range integer, p_usce_range numeric
) returns table(id uuid, dist numeric, in_range boolean)
language sql stable security definer set search_path = public as $$
  select c.id,
         coalesce(abs(c.step2_ck - p_step2), 0) / 5.0
           + coalesce(abs(c.usce_months - p_usce), 0) / 2.0
           + coalesce(abs(c.us_lors - p_lors), 0) * 1.5
           + coalesce(abs(c.yog - p_yog), 0) / 3.0
           + case when p_visa_required is not null and c.visa_required <> p_visa_required then 4 else 0 end,
         (p_step2 is null or abs(c.step2_ck - p_step2) <= p_step2_range)
           and (p_yog is null or c.yog is null or abs(c.yog - p_yog) <= p_yog_range)
           and (p_lors is null or c.us_lors is null or abs(c.us_lors - p_lors) <= p_lors_range)
           and (p_usce is null or c.usce_months is null or abs(c.usce_months - p_usce) <= p_usce_range)
           and (p_visa_required is null or c.visa_required = p_visa_required)
  from applicant_cycles c
  where c.consent_public
    and (p_cycle is null or c.match_cycle = p_cycle)
    and (p_specialty is null or lower(c.specialty) = lower(p_specialty))
    and (p_step2 is null or c.step2_ck is not null);
$$;
revoke all on function public._similar_cohort_pool(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) from public, anon, authenticated;

create or replace function public.similar_cohort(
  p_cycle integer default null,
  p_specialty text default null,
  p_step2 integer default null,
  p_usce numeric default null,
  p_lors integer default null,
  p_yog integer default null,
  p_visa_required boolean default null,
  p_step2_range integer default 10,
  p_yog_range integer default 5,
  p_lors_range integer default 1,
  p_usce_range numeric default 3
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_min constant int := 5;
  v_in_range int;
  v_widened boolean := false;
  v_ids uuid[];
  v_result jsonb;
begin
  select count(*) filter (where p.in_range) into v_in_range
  from public._similar_cohort_pool(p_cycle, p_specialty, p_step2, p_usce, p_lors, p_yog, p_visa_required,
                                   p_step2_range, p_yog_range, p_lors_range, p_usce_range) p;

  if v_in_range >= v_min then
    select array_agg(id order by dist) into v_ids
    from (select p.id, p.dist from public._similar_cohort_pool(p_cycle, p_specialty, p_step2, p_usce, p_lors, p_yog, p_visa_required, p_step2_range, p_yog_range, p_lors_range, p_usce_range) p where p.in_range order by p.dist limit 50) s;
  else
    -- Not enough people inside the range: use the 10 closest profiles.
    v_widened := true;
    select array_agg(id order by dist) into v_ids
    from (select p.id, p.dist from public._similar_cohort_pool(p_cycle, p_specialty, p_step2, p_usce, p_lors, p_yog, p_visa_required, p_step2_range, p_yog_range, p_lors_range, p_usce_range) p order by p.dist limit 10) s;
  end if;

  if coalesce(array_length(v_ids, 1), 0) < v_min then
    return jsonb_build_object(
      'in_range', v_in_range, 'cohort_size', coalesce(array_length(v_ids, 1), 0),
      'widened', v_widened, 'protected', true, 'min_size', v_min,
      'members', '[]'::jsonb, 'programs', '[]'::jsonb);
  end if;

  with m as (
    select c.*, ord
    from unnest(v_ids) with ordinality as u(id, ord)
    join applicant_cycles c on c.id = u.id
  ), r as (
    select pr.* from program_reports pr join m on m.id = pr.applicant_cycle_id
  ), members as (
    select m.ord,
      jsonb_build_object(
        'label', 'Perfil ' || m.ord,
        'specialty', m.specialty,
        'step2', m.step2_ck,
        'yog', m.yog,
        'us_lors', m.us_lors,
        'usce', m.usce_months,
        'visa_required', m.visa_required,
        'programs_applied', nullif(greatest(coalesce(m.programs_applied, 0),
            (select count(*) from r where r.applicant_cycle_id = m.id and r.applied)), 0),
        'interviews', greatest(coalesce(m.interview_invites, 0),
            (select count(*) from r where r.applicant_cycle_id = m.id and r.interview)),
        'matched', exists (select 1 from r where r.applicant_cycle_id = m.id and r.matched),
        'match_program', (select r.program_name_snapshot from r where r.applicant_cycle_id = m.id and r.matched limit 1),
        'match_state', (select r.state_snapshot from r where r.applicant_cycle_id = m.id and r.matched limit 1),
        'interview_programs', coalesce((
            select jsonb_agg(jsonb_build_object('program', r.program_name_snapshot, 'state', r.state_snapshot,
                     'specialty', r.specialty, 'signal', r.signal, 'matched', r.matched)
                   order by r.matched desc, r.program_name_snapshot)
            from r where r.applicant_cycle_id = m.id and r.interview), '[]'::jsonb),
        'applied_programs', coalesce((
            select jsonb_agg(distinct r.program_name_snapshot)
            from r where r.applicant_cycle_id = m.id and r.applied and not r.interview), '[]'::jsonb)
      ) j
    from m
  ), progs as (
    select jsonb_build_object(
      'program', program_name_snapshot, 'state', max(state_snapshot), 'specialty', specialty,
      'applied', count(distinct applicant_cycle_id) filter (where applied),
      'interviews', count(distinct applicant_cycle_id) filter (where interview),
      'matches', count(*) filter (where matched)) j,
      count(distinct applicant_cycle_id) filter (where interview) n_int,
      count(*) filter (where matched) n_match
    from r
    group by program_name_snapshot, specialty
  ), stats as (
    select count(*) n,
      (percentile_cont(.5) within group (order by step2_ck))::numeric s2,
      (percentile_cont(.5) within group (order by us_lors) filter (where us_lors is not null))::numeric lors,
      (percentile_cont(.5) within group (order by usce_months) filter (where usce_months is not null))::numeric usce
    from m
  )
  select jsonb_build_object(
    'in_range', v_in_range,
    'cohort_size', (select n from stats),
    'widened', v_widened,
    'protected', false,
    'min_size', v_min,
    'ranges', jsonb_build_object('step2', p_step2_range, 'yog', p_yog_range, 'lors', p_lors_range, 'usce', p_usce_range),
    'median_step2', (select s2 from stats),
    'median_lors', (select lors from stats),
    'median_usce', (select usce from stats),
    'median_interviews', (select (percentile_cont(.5) within group (order by (j->>'interviews')::int))::numeric from members),
    'median_applied', (select (percentile_cont(.5) within group (order by (j->>'programs_applied')::int))::numeric from members where j->>'programs_applied' is not null),
    'matched', (select count(*) from members where (j->>'matched')::boolean),
    'members', (select jsonb_agg(j order by ord) from members),
    'programs', coalesce((select jsonb_agg(j order by n_int desc, n_match desc, j->>'program') from progs), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) from public;
grant execute on function public.similar_cohort(integer,text,integer,numeric,integer,integer,boolean,integer,integer,integer,numeric) to anon, authenticated;

notify pgrst, 'reload schema';
