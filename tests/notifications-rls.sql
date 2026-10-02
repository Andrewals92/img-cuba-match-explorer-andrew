begin;
do $$declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();p uuid;ca uuid;n uuid;f public.notification_preferences;begin
 insert into auth.users(id,email) values(a,'v42-'||a||'@example.invalid'),(b,'v42-'||b||'@example.invalid');
 perform set_config('v42.a',a::text,true);perform set_config('v42.b',b::text,true);
 insert into public.programs(name,specialty,state,source) values('V42 fixture','Internal Medicine','FL','test:v42') returning id into p;perform set_config('v42.p',p::text,true);
 insert into public.notification_preferences(user_id,email,push,interview_reminders,timezone,quiet_start,quiet_end) values(a,true,true,true,'America/New_York','22:00','07:00') returning * into f;
 assert cme_private.delivery_time(f,'2026-10-02 03:00Z')='2026-10-02 11:00Z','Overnight quiet hours wrong';
 assert cme_private.delivery_time(f,'2026-11-01 05:30Z')='2026-11-01 12:00Z','DST quiet hours wrong';
 insert into public.radar_subscriptions(user_id,specialties,states,enabled) values(a,array['Internal Medicine'],array['FL'],true),(b,array['Pediatrics'],'{}',true);
 insert into public.accreditation_events(event_key,acgme_program_id,program_name,specialty,city,state,source_url) values('qa-v42:'||p,p::text,'V42 fixture','Internal Medicine','Miami','FL','https://apps.acgme.org/ads/Public/Programs/Search');
 -- Resolve canonical test event to stable program identity without name matching.
 update public.program_change_events set program_id=p where event_key='qa-v42:'||p;
 perform cme_private.generate_notification_events();perform cme_private.generate_notification_events();
 assert (select count(*)=1 from public.notifications where user_id=a and event_key='qa-v42:'||p),'Radar duplicate';
 assert (select count(*)=0 from public.notifications where user_id=b),'Radar wrong specialty';
 select id into n from public.notifications where user_id=a;perform set_config('v42.n',n::text,true);
 assert (select count(*)=2 from public.notification_outbox where notification_id=n),'Channel enqueue wrong';
 insert into public.push_subscriptions(user_id,endpoint,p256dh,auth) values(a,'https://fcm.googleapis.com/qa/'||a,repeat('A',88),repeat('A',24));
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,consent_public) values(a,'QA-'||a,2027,'Internal Medicine',false) returning id into ca;
 insert into public.interview_events(user_id,applicant_cycle_id,program_name_snapshot,start_at,status,timezone,meeting_url,private_notes,ranked,rank_position) values(a,ca,'PRIVATE PROGRAM',now()+interval '23 hours','scheduled','America/New_York','https://example.invalid/SECRET','PRIVATE NOTES',true,2);
 perform cme_private.generate_notification_events();
 assert exists(select 1 from public.notifications where user_id=a and notification_type='interview_reminder'),'Reminder missing';
 assert not exists(select 1 from public.notifications where user_id=a and (body like '%SECRET%' or body like '%PRIVATE NOTES%' or body like '%PRIVATE PROGRAM%')),'Private payload leak';
 -- Status baseline is not new; a changed status appears once, formatting does not.
 perform public.notification_record_program_status(p,'Initial Accreditation','2026-09-01');
 perform public.notification_record_program_status(p,'Continued Accreditation','2026-09-01');
 perform public.notification_record_program_status(p,'  Continued Accreditation  ','2026-09-01');
 assert(select count(*)=1 from public.program_change_events where event_key like 'status:'||p||':%');
 -- Digest creates one canonical summary rather than one external send per event.
 update public.notification_preferences set digest='daily',quiet_start=null,quiet_end=null,timezone=(select name from pg_catalog.pg_timezone_names where name in ('Pacific/Kiritimati','America/New_York','Europe/London','Asia/Tokyo') and extract(hour from now() at time zone name)>=10 limit 1) where user_id=a;
 update public.notifications set created_at=((date_trunc('day',now() at time zone pf.timezone)+interval '8 hours') at time zone pf.timezone) from public.notification_preferences pf where notifications.user_id=pf.user_id and pf.user_id=a;
 perform cme_private.generate_notification_digests();perform cme_private.generate_notification_digests();
 assert(select count(*)=1 from public.notifications where user_id=a and notification_type='digest');
 -- Stateful lease/retry idempotency, no actual provider transmission.
 update public.notification_outbox set status='processing',lease_token=gen_random_uuid(),attempt_count=1 where notification_id=n and channel='email';
 perform public.notification_finish_job(o.id,o.lease_token,'transient','email_http_429',null) from public.notification_outbox o where notification_id=n and channel='email';
 assert (select status='queued' and attempt_count=1 and not_before>now() from public.notification_outbox where notification_id=n and channel='email');
 update public.notification_outbox set status='processing',lease_token=gen_random_uuid(),attempt_count=5 where notification_id=n and channel='email';
 perform public.notification_finish_job(o.id,o.lease_token,'transient','email_http_503',null) from public.notification_outbox o where notification_id=n and channel='email';
 assert (select status='failed' from public.notification_outbox where notification_id=n and channel='email'),'Unbounded retries';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v42.a'),true);
do $$begin
 assert public.notification_unread_count()=(select count(*) from public.notifications where read_at is null);
 update public.notifications set read_at=now() where id=current_setting('v42.n')::uuid;
 assert public.notification_unread_count()=(select count(*) from public.notifications where read_at is null);
 begin update public.notifications set title='EDIT' where id=current_setting('v42.n')::uuid;raise exception 'content editable';exception when insufficient_privilege then null;end;
 begin insert into public.notifications(user_id,event_key,title,body) values(current_setting('v42.a')::uuid,'spoof','spoof','spoof');raise exception 'creation allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v42.b'),true);
do $$declare c integer;begin
 assert (select count(*)=0 from public.notifications where user_id=current_setting('v42.a')::uuid);
 assert (select count(*)=0 from public.notification_preferences where user_id=current_setting('v42.a')::uuid);
 assert (select count(*)=0 from public.radar_subscriptions where user_id=current_setting('v42.a')::uuid);
 assert (select count(*)=0 from public.push_subscriptions where user_id=current_setting('v42.a')::uuid);
 update public.notifications set read_at=now() where id=current_setting('v42.n')::uuid;get diagnostics c=row_count;assert c=0;
 delete from public.push_subscriptions where user_id=current_setting('v42.a')::uuid;get diagnostics c=row_count;assert c=0;
 begin perform public.notification_operations();raise exception 'admin API allowed';exception when raise_exception then assert SQLERRM='Admin required';end;
 begin perform 1 from public.notification_outbox;raise exception 'outbox exposed';exception when insufficient_privilege then null;end;
end $$;
set local role anon;
do $$begin
 begin perform 1 from public.notifications;raise exception 'anon exposed';exception when insufficient_privilege then null;end;
 begin perform 1 from public.push_subscriptions;raise exception 'anon exposed';exception when insufficient_privilege then null;end;
 assert jsonb_array_length(public.program_radar('Internal Medicine','FL',now()-interval '1 day',now()+interval '1 day'))>=1;
end $$;
reset role;
rollback;
select 'PASS: A/B/anon isolation; read-only state; Radar dedupe and filtering; private reminders; quiet hours DST; bounded retry' as result;
