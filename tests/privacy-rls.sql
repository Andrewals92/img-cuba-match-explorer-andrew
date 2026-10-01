-- Transactional production regression: all synthetic rows are rolled back.
begin;
do $$
declare p uuid; u uuid; c uuid; result jsonb; i integer; uid1 uuid; uid2 uuid;
begin
 insert into public.programs(name,specialty,state,active,source) values ('V4 transactional QA','V4 QA Specialty','FL',true,'test:v4') returning id into p;
 perform set_config('cme.test_program',p::text,true);
 for i in 1..6 loop
   u:=gen_random_uuid();
   insert into auth.users(id,email) values(u,'cme-v4-'||u::text||'@example.invalid');
   if i=1 then uid1:=u; end if; if i=2 then uid2:=u; end if;
   perform set_config('request.jwt.claim.sub',u::text,true);
   insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,step2_ck,yog,usce_months,us_lors,consent_public,programs_applied,interview_invites)
     values(u,'QA-'||u::text,2026,'V4 QA Specialty',240+i,2020,6,3,true,100,8) returning id into c;
   insert into public.program_reports(user_id,applicant_cycle_id,program_id,match_cycle,program_name_snapshot,specialty,applied,interview,matched,signal,interview_date)
     values(u,c,p,2026,'QA','V4 QA Specialty',true,i<=3,i<=3,case when i<=3 then 'Gold' else 'Silver' end,case when i<=3 then date '2025-10-01' end);
   if i=2 then
     result:=public.program_compare_stats(array[p],2026)->0;
     assert result->>'applicant_profiles' is null,'small cohort exposed';
     assert result->>'interviews' is null,'small interview count exposed';
     assert result->>'matches' is null,'small match count exposed';
     assert result#>>'{characteristics,step2}' is null,'small characteristics exposed';
     assert result->'timeline'='[]'::jsonb,'small month exposed';
   end if;
 end loop;
 result:=public.program_compare_stats(array[p],2026)->0;
 assert (result->>'applicant_profiles')::int=6;
 assert (result->>'applications')::int=6;
 assert (result->>'interviews')::int=3;
 assert (result->>'interview_rate')::numeric=50;
 assert (result->>'matches')::int=3;
 assert (result->>'match_rate')::numeric=50;
 assert (result#>>'{timeline,0,invitations}')::int=3;
 assert (result#>>'{characteristics,step2}')::numeric=243.5;
 -- A private contributor cannot influence public aggregates.
 perform set_config('request.jwt.claim.sub',uid2::text,true);
 update public.applicant_cycles set consent_public=false where user_id=uid2;
 result:=public.program_compare_stats(array[p],2026)->0;
 assert result->>'interviews' is null;
 assert result->>'matches' is null;
 assert result->>'interview_rate' is null;
 assert result->'timeline'='[]'::jsonb;
 -- An incomplete cycle never reports matches/rate as zero or No Match.
 result:=public.program_compare_stats(array[p],2028)->0;
 assert result->>'matches' is null and result->>'match_rate' is null;
 perform set_config('request.jwt.claim.sub',uid1::text,true);
 perform set_config('cme.test_user',uid1::text,true);
end $$;
set local role authenticated;
do $$
declare denied boolean:=false; n integer;
begin
 assert not public.is_admin();
 assert (public.similar_cohort(p_cycle=>2026,p_specialty=>'V4 QA Specialty')->>'cohort_size')::int=4,'own profile or private peer included in cohort';
 select count(*) into n from public.applicant_cycles;
 assert n=1,'normal user sees other profiles';
 select count(*) into n from public.program_reports;
 assert n=1,'normal user sees other reports';
 update public.applicant_cycles set programs_applied=101 where user_id=auth.uid();
 assert (select programs_applied from public.applicant_cycles where user_id=auth.uid())=101,'own update failed';
 begin update public.profiles set role='admin' where id=auth.uid(); exception when others then denied:=true; end;
 assert denied,'self promotion permitted';
 denied:=false;
 begin perform public.admin_set_user_role(auth.uid(),'admin'); exception when others then denied:=true; end;
 assert denied,'admin-only RPC permitted';
 denied:=false;
 begin perform public.program_workspace_health_v4(); exception when others then denied:=true; end;
 assert denied,'health RPC permitted';
 assert jsonb_array_length(public.program_compare_stats(array[current_setting('cme.test_program')::uuid],2026))=1;
end $$;
set local role anon;
do $$
declare denied boolean:=false; n integer;
begin
 begin select count(*) into n from public.applicant_cycles; assert n=0,'anon profiles leaked'; exception when insufficient_privilege then denied:=true; end;
 begin select count(*) into n from public.program_reports; assert n=0,'anon reports leaked'; exception when insufficient_privilege then denied:=true; end;
 assert jsonb_array_length(public.program_compare_stats(array[current_setting('cme.test_program')::uuid],2026))=1;
 assert not has_schema_privilege('anon','cme_private','USAGE');
end $$;
rollback;
select 'PASS: small-cell privacy, six-person aggregates, rates, consent, incomplete cycles, own data/update, RLS, role escalation, admin RPC denial, public aggregates; fixtures rolled back' result;
