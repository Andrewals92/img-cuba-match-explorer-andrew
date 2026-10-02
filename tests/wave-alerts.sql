begin;
do $$declare p uuid;u uuid;c uuid;owner uuid;i integer;n integer;begin
 insert into public.programs(name,specialty,state,active,source) values('V43 wave alert QA','V43 Alert QA','FL',true,'test:v43') returning id into p;
 for i in 1..3 loop
  u:=gen_random_uuid();insert into auth.users(id,email) values(u,'wave-'||u||'@example.invalid');
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(u,'QA-'||u,extract(year from current_date)::int+1,'V43 Alert QA',true) returning id into c;
  insert into public.program_reports(user_id,applicant_cycle_id,program_id,match_cycle,program_name_snapshot,specialty,interview,signal,interview_date)
  values(u,c,p,extract(year from current_date)::int+1,'V43 wave alert QA','V43 Alert QA',true,'Gold',current_date);
  if i=1 then owner:=u;end if;
 end loop;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 insert into public.user_program_watchlist(user_id,program_id) values(owner,p);
 insert into public.notification_preferences(user_id,in_app,email,push,watchlist,wave_activity) values(owner,true,false,false,true,false) on conflict(user_id) do update set in_app=true,email=false,push=false,watchlist=true,wave_activity=false;
 perform cme_private.generate_wave_notifications_v43();
 select count(*) into n from public.notifications where user_id=owner and event_key like 'v43-wave:%';assert n=0,'alert without opt-in';
 update public.notification_preferences set wave_activity=true where user_id=owner;
 perform cme_private.generate_wave_notifications_v43();perform cme_private.generate_wave_notifications_v43();
 select count(*) into n from public.notifications where user_id=owner and event_key like 'v43-wave:%';assert n=1,'weekly alert dedupe failed';
 assert not exists(select 1 from public.notification_outbox where user_id=owner),'email/push without opt-in';
 update public.user_program_watchlist set alerts_muted=true where user_id=owner;
 perform cme_private.generate_wave_notifications_v43();
 select count(*) into n from public.notifications where user_id=owner and event_key like 'v43-wave:%';assert n=1,'muted program notified';
end $$;
rollback;
select 'PASS explicit opt-in, sufficient period, per-cycle-week dedupe, muted watchlist and no unintended channels; rolled back' result;
