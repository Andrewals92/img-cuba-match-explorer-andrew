begin;
do $$ declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); ca uuid; cb uuid; p uuid;
begin
 insert into auth.users(id,email) values(a,'v41-'||a||'@example.invalid'),(b,'v41-'||b||'@example.invalid');
 insert into public.programs(name,specialty,active,source) values('V41 transaction QA','Internal Medicine',true,'test:v41') returning id into p;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(a,'QA-'||a,2027,'Internal Medicine',false) returning id into ca;
 perform set_config('request.jwt.claim.sub',b::text,true);
 insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(b,'QA-'||b,2027,'Internal Medicine',false) returning id into cb;
 perform set_config('v41.a',a::text,true);perform set_config('v41.b',b::text,true);perform set_config('v41.ca',ca::text,true);perform set_config('v41.cb',cb::text,true);perform set_config('v41.p',p::text,true);
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v41.a'),true);
do $$declare eid uuid; n integer;begin
 insert into public.interview_events(user_id,applicant_cycle_id,program_id,program_name_snapshot,start_at,status,timezone,meeting_url,private_notes,ranked,rank_position)
 values(current_setting('v41.a')::uuid,current_setting('v41.ca')::uuid,current_setting('v41.p')::uuid,'Private QA','2026-10-14 14:00Z','scheduled','America/New_York','https://example.invalid/private','Secret QA',true,2) returning id into eid;
 perform set_config('v41.e',eid::text,true);
 insert into public.user_program_watchlist(user_id,program_id,private_notes) values(current_setting('v41.a')::uuid,current_setting('v41.p')::uuid,'Secret watch');
 update public.interview_events set status='completed',thank_you_sent=true,thank_you_sent_at='2026-10-15',private_impression='{"overall":"Private impression"}' where id=eid;
 assert (select thank_you_sent and ranked and private_notes='Secret QA' from public.interview_events where id=eid);
 begin
 insert into public.interview_events(user_id,applicant_cycle_id,program_id,program_name_snapshot,start_at,timezone) values(current_setting('v41.a')::uuid,current_setting('v41.ca')::uuid,current_setting('v41.p')::uuid,'QA','2026-10-14 14:00Z','America/New_York');
 raise exception 'duplicate accepted';exception when unique_violation then null;end;
 insert into public.interview_events(user_id,applicant_cycle_id,program_id,program_name_snapshot,start_at,event_type,timezone) values(current_setting('v41.a')::uuid,current_setting('v41.ca')::uuid,current_setting('v41.p')::uuid,'QA','2026-10-14 14:00Z','social','America/New_York');
 begin
 insert into public.interview_events(user_id,applicant_cycle_id,program_name_snapshot) values(current_setting('v41.a')::uuid,current_setting('v41.cb')::uuid,'Foreign cycle');raise exception 'foreign cycle accepted';exception when foreign_key_violation then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v41.b'),true);
do $$declare n integer;begin
 assert (select count(*)=0 from public.interview_events),'User B read private event';assert (select count(*)=0 from public.user_program_watchlist),'User B read watchlist';
 update public.interview_events set private_notes='B' where id=current_setting('v41.e')::uuid;get diagnostics n=row_count;assert n=0;
 delete from public.interview_events where id=current_setting('v41.e')::uuid;get diagnostics n=row_count;assert n=0;
 begin insert into public.user_program_watchlist(user_id,program_id) values(current_setting('v41.a')::uuid,current_setting('v41.p')::uuid);raise exception 'spoofed owner accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where role='admin' limit 1),true);
set local role authenticated;
do $$begin assert (select count(*)=0 from public.interview_events where user_id=current_setting('v41.a')::uuid),'Admin exposed private notes';assert (select count(*)=0 from public.user_program_watchlist where user_id=current_setting('v41.a')::uuid),'Admin exposed watchlist';end $$;
set local role anon;
do $$begin begin perform 1 from public.interview_events;raise exception 'anon read events';exception when insufficient_privilege then null;end;begin perform 1 from public.user_program_watchlist;raise exception 'anon read watchlist';exception when insufficient_privilege then null;end;end $$;
reset role;set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v41.a'),true);
do $$declare n integer;begin delete from public.interview_events where id=current_setting('v41.e')::uuid;get diagnostics n=row_count;assert n=1,'Own delete failed';delete from public.user_program_watchlist where user_id=current_setting('v41.a')::uuid;get diagnostics n=row_count;assert n=1,'Own watch delete failed';end $$;
rollback;
select 'PASS: CRUD, duplicate protection, social coexistence, foreign-cycle denial, A/B/admin/anon isolation; all fixtures rolled back' as result;
