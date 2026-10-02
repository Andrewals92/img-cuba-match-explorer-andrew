alter table public.notification_preferences add column if not exists wave_activity boolean not null default false;
create or replace function cme_private.generate_wave_notifications_v43() returns void language plpgsql security definer set search_path='' as $$
declare item record;
begin
 if not pg_catalog.pg_try_advisory_xact_lock(430032) then return;end if;
 for item in
 with periods as(select program_id,match_cycle,date_trunc('week',invitation_date::timestamp)::date period
  from cme_private.canonical_program_observations_v43 where interview and invitation_date between current_date-13 and current_date
  and invitation_date>=make_date(match_cycle-1,7,1) and invitation_date<make_date(match_cycle,7,1)
  group by 1,2,3 having count(distinct person)>=3)
 select w.user_id,b.program_id,b.match_cycle,b.period from periods b
 join public.user_program_watchlist w on w.program_id=b.program_id and not w.alerts_muted
 join public.notification_preferences f on f.user_id=w.user_id and f.watchlist and f.wave_activity
 loop
 perform cme_private.enqueue_notification(item.user_id,'watchlist_activity',
  'v43-wave:'||item.program_id||':'||item.match_cycle||':'||item.period,
  'Nueva observación de entrevistas','Un programa guardado tiene un período de actividad comunitaria que cumple el umbral de privacidad.',
  '#/program/'||item.program_id||'?cycle='||item.match_cycle,item.program_id);
 end loop;
end $$;
revoke all on function cme_private.generate_wave_notifications_v43() from public,anon,authenticated;
create or replace function cme_private.notification_tick() returns void language plpgsql security definer set search_path='' as $$
declare tok text;begin
 perform cme_private.generate_notification_events();
 perform cme_private.generate_wave_notifications_v43();
 select dispatch_token into tok from cme_private.notification_runtime;
 perform net.http_post(url:='https://xqjjiveuvnioachgxqez.supabase.co/functions/v1/notification-dispatcher',headers:=jsonb_build_object('Content-Type','application/json','x-dispatch-token',tok),body:='{}'::jsonb,timeout_milliseconds:=5000);
end $$;
revoke all on function cme_private.notification_tick() from public,anon,authenticated;
-- Preserve current concurrency/lease/delivery logic and add send-time opt-out protection.
do $patch$
declare body text;
begin
 body:=pg_get_functiondef('public.notification_claim_jobs(integer)'::regprocedure);
 if position('v43-wave:' in body)=0 then
  if position(E'begin\n' in body)=0 then raise exception 'Unexpected claim function body';end if;
  body:=replace(body,E'begin\n',E'begin\n update public.notification_outbox o set status=\'cancelled\',last_error_code=\'wave_opt_out\' from public.notifications n,public.notification_preferences f where n.id=o.notification_id and f.user_id=o.user_id and n.event_key like \'v43-wave:%\' and not f.wave_activity and o.status in (\'queued\',\'blocked\');\n');
  execute body;
 end if;
end $patch$;
create or replace function public.intelligence_health_v43() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 return jsonb_build_object('version','4.3','qualifying_program_weeks',(select count(*) from(select program_id,match_cycle,date_trunc('week',invitation_date::timestamp) from cme_private.canonical_program_observations_v43 where interview and invitation_date is not null group by 1,2,3 having count(distinct person)>=3)x),
  'program_source_records',(select count(*) from cme_private.program_source_catalog_v43),
  'linked_source_records',(select count(*) from cme_private.program_source_catalog_v43 where program_id is not null));
end $$;
revoke all on function public.intelligence_health_v43() from public,anon;
grant execute on function public.intelligence_health_v43() to authenticated;
