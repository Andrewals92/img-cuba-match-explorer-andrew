-- Entire fixture transaction rolls back: no lasting users, reports or notifications.
begin;
do $$
declare p uuid;u uuid;c uuid;result jsonb;i integer;first_c uuid;first_u uuid;n integer;
begin
 insert into public.programs(name,specialty,state,active,source) values('V43 QA','V43 QA Specialty','FL',true,'test:v43') returning id into p;
 perform set_config('v43.program',p::text,true);
 for i in 1..5 loop
  u:=gen_random_uuid();insert into auth.users(id,email) values(u,'v43-'||u||'@example.invalid');
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(u,'QA-'||u,2026,'V43 QA Specialty',true) returning id into c;
  if i=1 then first_c:=c;first_u:=u;end if;
  insert into public.program_reports(user_id,applicant_cycle_id,program_id,match_cycle,program_name_snapshot,specialty,applied,interview,signal,interview_date)
   values(u,c,p,2026,'V43 QA','V43 QA Specialty',true,true,'Gold','2025-10-01');
  result:=public.program_season_intelligence_v43(array[p],2026)->0;
  if i=2 then assert result->'timeline'='[]'::jsonb,'two reports disclosed';end if;
  if i=3 then assert (result#>>'{timeline,0,reports}')::int=3,'three qualifying reports missing';end if;
  if i=4 then assert result#>>'{signals,0,rate}' is null,'four signal reports disclosed';end if;
 end loop;
 result:=public.program_season_intelligence_v43(array[p],2026)->0;
 assert (result#>>'{signals,0,applications}')::int=5,'wrong signal denominator';
 assert (result#>>'{signals,0,rate}')::numeric=100,'wrong observed rate';
 assert result->>'context'='Historical completed cycle';
 perform set_config('request.jwt.claim.sub',first_u::text,true);
 insert into public.program_reports(user_id,applicant_cycle_id,program_id,match_cycle,program_name_snapshot,specialty,applied,interview,signal,interview_date)
  values(first_u,first_c,p,2026,'V43 duplicate','V43 QA Specialty',true,true,'Gold','2025-10-01');
 result:=public.program_season_intelligence_v43(array[p],2026)->0;
 assert (result#>>'{signals,0,applications}')::int=5,'duplicate inflated denominator';
 assert (result#>>'{timeline,0,reports}')::int=5,'duplicate inflated wave';
 -- One negative outcome would be derivable from a rate; complementary suppression required.
 update public.program_reports set interview=false,interview_date=null where user_id=first_u and program_id=p;
 result:=public.program_season_intelligence_v43(array[p],2026)->0;
 assert result#>>'{signals,0,rate}' is null,'small complement disclosed';
 result:=public.program_season_intelligence_v43(array[p],null)->0;
 assert result->'signals'='[]'::jsonb,'cycles pooled for signals';
 result:=public.program_season_intelligence_v43(array[p],2027)->0;
 assert result->>'context'='Current / incomplete cycle';assert result->'timeline'='[]'::jsonb;
 perform set_config('request.jwt.claim.sub','',true);
end $$;
set local role anon;
do $$declare p uuid:=current_setting('v43.program')::uuid;r jsonb;begin
 r:=public.specialty_wave_overview_v43('V43 QA Specialty',2026,'FL','V43 QA',0);
 assert jsonb_array_length(r->'programs')=1;
 assert r#>>'{programs,0,signals,0,rate}' is null,'cross-filter bypassed suppression';
 assert not has_table_privilege('anon','public.interview_events','SELECT');
 assert not has_schema_privilege('anon','cme_private','USAGE');
 assert not has_function_privilege('anon','public.intelligence_health_v43()','EXECUTE');
end $$;
reset role;
rollback;
select 'PASS wave 2/3, signal 4/5, complement, canonical dedup, cycles, cross-filter and private ACL' result;
