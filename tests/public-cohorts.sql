-- Public DTO, small samples, explicit outcomes and totals. No persistent fixtures.
begin;
do $$
declare c uuid; p uuid; u uuid; i integer; r jsonb; m jsonb; n integer;
begin
 insert into public.programs(name,specialty,state,active,source) values('Cohort QA','Public cohort QA','FL',true,'test:cohort') returning id into p;
 for i in 1..5 loop
  u:=gen_random_uuid(); insert into auth.users(id,email) values(u,'cohort-'||u||'@example.invalid');
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,step2_ck,yog,consent_public,programs_applied,interview_invites,match_outcome,notes,immigration_status)
   values(u,'PRIVATE-ID-'||u,2026,'Public cohort QA',230+i*10,2020,i<>5,case when i=1 then 0 else 100 end,case when i=1 then 0 else 8 end,case when i=2 then 'no_match' end,'PRIVATE NOTE SENTINEL','PRIVATE IMMIGRATION SENTINEL') returning id into c;
  insert into public.program_reports(user_id,applicant_cycle_id,program_id,program_name_snapshot,match_cycle,specialty,applied,interview,signal,matched)
   values(u,c,p,'Cohort QA',2026,'Public cohort QA',true,i<>2,case when i=1 then 'Gold' when i=2 then 'Silver' else 'None' end,i=1);
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 r:=public.similar_cohort(p_specialty=>'Public cohort QA');
 assert jsonb_array_length(r->'members')=4,'private or public inclusion incorrect';
 assert (r->>'protected')::boolean=false;
 assert not (r::text ~ 'PRIVATE|user_id|immigration_status|verification_note|private_notes|meeting_url'), 'private fields leaked';
 assert (r->>'matched')::int=1 and (r->>'no_match')::int=1 and (r->>'outcome_not_reported')::int=2,'outcome distinction lost';
 r:=public.similar_cohort(p_specialty=>'Public cohort QA',p_step2=>240,p_step2_range=>5);
 assert (r->>'cohort_size')::int=1 and jsonb_array_length(r->'members')=1 and not (r->>'widened')::boolean;
 m:=r->'members'->0;
 assert (m->>'programs_applied')::int=0 and (m->>'interviews')::int=0,'declared zero lost';
 assert (m->>'detailed_interviews')::int=1 and (m->>'totals_conflict')::boolean,'detail discrepancy hidden';
 assert m#>>'{programs,0,signal}'='Gold' and (m#>>'{signals,Gold}')::int=1,'signal program link lost';
 assert m#>>'{programs,0,id}'=p::text,'program identity missing';
 r:=public.similar_cohort(p_specialty=>'Public cohort QA',p_step2=>245,p_step2_range=>5);
 assert jsonb_array_length(r->'members')=2,'two people suppressed';
 r:=public.similar_cohort(p_specialty=>'Public cohort QA',p_step2=>300,p_step2_range=>5);
 assert (r->>'cohort_size')::int=0 and jsonb_array_length(r->'members')=0,'empty cohort silently widened';
end $$;
set local role anon;
do $$ declare r jsonb;begin
 r:=public.similar_cohort(p_specialty=>'Public cohort QA',p_step2=>240,p_step2_range=>5);
 assert jsonb_array_length(r->'members')=1,'anonymous read missing';
 assert not has_table_privilege('anon','public.applicant_cycles','SELECT'),'raw profile grant changed';
 assert not has_table_privilege('anon','public.program_reports','SELECT'),'raw report grant changed';
end $$;
rollback;
select 'PASS: public 1/2/4-person cohorts, no widening, consent withdrawal, private-field omission, declared zero, explicit No Match, missing outcome, linked signals and raw-table RLS' result;
