-- Authorization, small cells, incomplete cycles and limits. All fixtures roll back.
begin;
do $$
declare p uuid;u uuid;c uuid;owner_id uuid;owner_cycle uuid;peer uuid;r jsonb;ans uuid;i integer;before_hash text; rec record;
begin
 select md5(string_agg((to_jsonb(x))::text,'' order by id)) into before_hash from public.program_reports x where source='import:CubaMatch_2026';
 perform set_config('v50.before_hash',before_hash,true);
 insert into public.programs(name,specialty,state,active,source) values('V50 QA Program','V50 QA','FL',true,'test:v50') returning id into p;
 for i in 0..6 loop
  u:=gen_random_uuid();insert into auth.users(id,email) values(u,'v50-'||u||'@example.invalid');
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,step2_ck,yog,usce_months,us_lors,visa_required,consent_public,programs_applied,interview_invites)
  values(u,'V50-'||u,2026,'V50 QA',245,2020,6,3,false,true,100,8) returning id into c;
  if i=0 then owner_id:=u;owner_cycle:=c;end if;if i=1 then peer:=u;end if;
  insert into public.program_reports(user_id,applicant_cycle_id,program_id,match_cycle,program_name_snapshot,specialty,applied,interview,matched,signal)
  values(u,c,p,2026,'V50 QA Program','V50 QA',true,i between 1 and 3,i between 1 and 3,'Gold');
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 perform set_config('v50.owner',owner_id::text,true);perform set_config('v50.peer',peer::text,true);
 perform set_config('v50.cycle',owner_cycle::text,true);perform set_config('v50.program',p::text,true);
 r:=public.match_intelligence_v50(owner_cycle,'{"state":"FL","include_sparse":false}');
 assert (r#>>'{cohort,cohort_size}')::integer=6,'own profile counted';
 assert r#>'{cohort,members}'='[]'::jsonb,'raw profiles leaked';
 assert (r#>>'{cohort,matched}')::integer=3,'completed Match aggregate incorrect';
 assert (r#>>'{cohort,no_match_reported}')::integer=3;
 assert r#>>'{cohort,no_match}' is null,'unreported outcomes treated as confirmed no match';
 assert (r#>>'{cohort,match_rate}')::numeric=50;
 assert jsonb_array_length(r->'programs')=1,'discovery did not use stable program identity';
 assert r#>>'{programs,0,id}'=p::text;
 assert r#>>'{profile,id}'=owner_cycle::text;
 r:=public.similar_cohort(p_specialty=>'V50 QA',p_step2=>290,p_step2_range=>5);
 assert (r->>'protected')::boolean and r->>'cohort_size' is null,'small count or silent widening';
 assert r->'programs'='[]'::jsonb;
 -- A minority of one matched contributor must not be reconstructible from totals.
 for rec in select user_id from public.program_reports where specialty='V50 QA' and matched and user_id<>peer loop
  perform set_config('request.jwt.claim.sub',rec.user_id::text,true);
  update public.program_reports set matched=false where specialty='V50 QA' and user_id=rec.user_id;
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 r:=public.similar_cohort(p_specialty=>'V50 QA');
 assert r->>'matched' is null and r->>'no_match_reported' is null and r->>'match_rate' is null,'small complement exposed';
 -- Future cycles contribute activity but never no-match outcomes.
 for rec in select user_id,anon_id from public.applicant_cycles where specialty='V50 QA' and match_cycle=2026 loop
  perform set_config('request.jwt.claim.sub',rec.user_id::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(rec.user_id,rec.anon_id,2028,'V50 QA',true);
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 r:=public.similar_cohort(p_cycle=>2028,p_specialty=>'V50 QA');
 assert (r->>'in_progress')::integer=6 and (r->>'completed')::integer=0;
 assert r->>'matched' is null and r->>'match_rate' is null and r->>'no_match' is null;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 r:=public.ai_begin_request_v50('research');assert (r->>'allowed')::boolean;ans:=(r->>'answer_id')::uuid;
 perform set_config('v50.answer',ans::text,true);
 assert public.ai_finish_request_v50(ans,'success',null,100,3,300,100,array['catalog'],array[p]);
 assert not public.ai_finish_request_v50(ans,'success'), 'telemetry mutable after completion';
 assert public.ai_feedback_v50(ans,'helpful');
 perform public.ai_begin_request_v50('cohort');perform public.ai_begin_request_v50('dashboard');
 r:=public.ai_begin_request_v50('assistant');assert not (r->>'allowed')::boolean and r->>'reason'='minute_limit';
end $$;
set local role authenticated;
do $$declare r jsonb;denied boolean:=false;begin
 assert not has_schema_privilege('authenticated','cme_private','USAGE');
 assert not public.is_admin();
 begin perform public.admin_ai_operations_v50();exception when insufficient_privilege then denied:=true;end;assert denied,'normal user sees operations';
 perform set_config('request.jwt.claim.sub',current_setting('v50.peer'),true);
 denied:=false;begin perform public.match_intelligence_v50(current_setting('v50.cycle')::uuid);exception when insufficient_privilege then denied:=true;end;assert denied,'cross-user profile context accepted';
 assert not public.ai_feedback_v50(current_setting('v50.answer')::uuid,'incorrect'),'cross-user feedback accepted';
 assert not public.ai_finish_request_v50(current_setting('v50.answer')::uuid,'success'),'cross-user telemetry changed';
 assert not exists(select 1 from public.applicant_cycles where source like 'import:%'),'raw imports readable';
 assert not exists(select 1 from public.interview_events where user_id<>auth.uid()),'cross-user tracker readable';
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$declare r jsonb;begin
 assert not has_function_privilege('anon','public.match_intelligence_v50(uuid,jsonb)','EXECUTE');
 assert not has_function_privilege('anon','public.ai_begin_request_v50(text)','EXECUTE');
 assert not has_function_privilege('anon','public.ai_feedback_v50(uuid,text)','EXECUTE');
 assert not has_function_privilege('anon','public.admin_ai_operations_v50()','EXECUTE');
 r:=public.similar_cohort(p_specialty=>'V50 QA');assert r->'members'='[]'::jsonb;
 assert not (r::text ~ 'V50-[0-9a-f]'),'historical identity exposed';
end $$;
reset role;
do $$declare h text;begin
 assert (select count(*)=36 from public.applicant_cycles where source='import:CubaMatch_2026');
 assert (select count(*)=338 from public.program_reports where source='import:CubaMatch_2026' and interview);
 assert (select count(*)=14 from public.program_reports where source='import:CubaMatch_2026' and matched);
 select md5(string_agg((to_jsonb(x))::text,'' order by id)) into h from public.program_reports x where source='import:CubaMatch_2026';
 assert h=current_setting('v50.before_hash'),'historical report bytes changed';
 assert not exists(select 1 from public.program_reports r where source='import:CubaMatch_2026' group by to_jsonb(r)-'id'-'created_at'-'updated_at' having count(*)>1);
end $$;
rollback;
select 'PASS v5: own profile exclusion, aggregate-only cohorts, complementary suppression, no silent widening, incomplete cycles, stable discovery, owner-only feedback, atomic rate limit, anon/admin denial, immutable 36/338/14 and duplicate guard' result;
