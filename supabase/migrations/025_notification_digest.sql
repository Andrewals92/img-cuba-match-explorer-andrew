create or replace function cme_private.generate_notification_digests() returns void language plpgsql security definer set search_path='' as $$
declare f public.notification_preferences; local_now timestamp;boundary timestamp;n integer;span interval;begin
 for f in select * from public.notification_preferences where digest<>'off' loop
 local_now=now() at time zone f.timezone;
 if local_now::time<'09:00' or(f.digest='weekly' and extract(isodow from local_now)<>1) then continue;end if;
 span=case when f.digest='weekly' then interval '7 days' else interval '1 day' end;
 boundary=date_trunc('day',local_now)+interval '9 hours';
 select count(*) into n from public.notifications where user_id=f.user_id and notification_type in ('new_program','program_update','watchlist_activity') and created_at>=(boundary-span) at time zone f.timezone and created_at<boundary at time zone f.timezone;
 if n>0 then perform cme_private.enqueue_notification(f.user_id,'digest','digest:'||f.digest||':'||boundary::date,'Tu resumen de alertas',n||' alertas de programas disponibles en tu centro privado. Recibes este resumen por la frecuencia que elegiste.','#/notification-center');end if;
 end loop;
end $$;
revoke all on function cme_private.generate_notification_digests() from public,anon,authenticated;

create or replace function cme_private.enqueue_notification(p_user uuid,p_type text,p_key text,p_title text,p_body text,p_path text,p_program uuid default null,p_cycle uuid default null,p_expiry timestamptz default null) returns uuid language plpgsql security definer set search_path='' as $$
declare pref public.notification_preferences; nid uuid;ch text;at_time timestamptz;
begin
 select * into pref from public.notification_preferences where user_id=p_user;
 if not found then pref.in_app=true;pref.email=false;pref.push=false;pref.timezone='America/New_York';pref.digest='off';end if;
 if not pref.in_app and not pref.email and not pref.push then return null;end if;
 if (select count(*) from public.notifications where user_id=p_user and created_at>now()-interval '1 day')>=50 or (select count(*) from public.notifications where created_at>now()-interval '1 day')>=5000 then return null;end if;
 insert into public.notifications(user_id,notification_type,event_key,title,body,action_path,program_id,applicant_cycle_id,expires_at,read_at)
 values(p_user,p_type,p_key,left(p_title,200),left(p_body,500),p_path,p_program,p_cycle,p_expiry,case when not pref.in_app then now() end)
 on conflict(user_id,event_key,notification_type) do nothing returning id into nid;
 if nid is null then return null;end if;
 at_time=cme_private.delivery_time(pref,now());
 -- Non-urgent changes are held for the configured digest window.
 if pref.digest<>'off' and p_type in ('new_program','program_update','watchlist_activity') then
  at_time=greatest(at_time,((date_trunc(case when pref.digest='weekly' then 'week' else 'day' end,now() at time zone pref.timezone)+case when pref.digest='weekly' then interval '1 week' else interval '1 day' end)+interval '9 hours') at time zone pref.timezone);
 end if;
 foreach ch in array array['email','push'] loop
 if ((ch='email' and pref.email) or (ch='push' and pref.push)) and (pref.digest='off' or p_type not in ('new_program','program_update','watchlist_activity')) then
 insert into public.notification_outbox(notification_id,user_id,channel,not_before,dedupe_key) values(nid,p_user,ch,at_time,nid::text||':'||ch) on conflict do nothing;
 end if;end loop;return nid;
end $$;
revoke all on function cme_private.enqueue_notification(uuid,text,text,text,text,text,uuid,uuid,timestamptz) from public,anon,authenticated;

create or replace function cme_private.generate_notification_events() returns void language plpgsql security definer set search_path='' as $$
declare e record;u record;i record;stats jsonb;ids uuid[];p jsonb;
begin
 -- Transaction-scoped single generator; duplicate cron runs safely no-op.
 if not pg_catalog.pg_try_advisory_xact_lock(420021) then return;end if;
 for e in select * from public.program_change_events where detected_at>now()-interval '24 hours' order by detected_at limit 200 loop
 for u in
 select s.user_id from public.radar_subscriptions s left join public.notification_preferences f on f.user_id=s.user_id
 where e.event_type='new_program' and s.enabled and coalesce(f.radar,true) and cardinality(s.specialties)>0
 and exists(select 1 from unnest(s.specialties) v where lower(v)=lower(e.specialty))
 and (cardinality(s.states)=0 or exists(select 1 from unnest(s.states)v where upper(v)=upper(e.state)))
 union
 select w.user_id from public.user_program_watchlist w left join public.notification_preferences f on f.user_id=w.user_id
 where w.program_id=e.program_id and not w.alerts_muted and coalesce(f.watchlist,true)
 loop
 perform cme_private.enqueue_notification(u.user_id,e.event_type,e.event_key,case when e.event_type='new_program' then 'Programa detectado: ' else 'Programa actualizado: ' end||e.title,
 coalesce(e.specialty,'')||' · '||coalesce(e.city,'')||' '||coalesce(e.state,'')||'. Recibes esta alerta por tus filtros Radar o un programa guardado.',case when e.program_id is null then '#/radar' else '#/program/'||e.program_id end,e.program_id);
 end loop;end loop;
 -- Current-month threshold crossing only, not individual/report increment alerts.
 for ids in select array_agg(program_id) from(select program_id,row_number() over(order by program_id) rn from(select distinct program_id from public.user_program_watchlist where not alerts_muted)y)x group by (rn-1)/5 loop
 stats=public.program_compare_stats(ids,null);
 for p in select value from jsonb_array_elements(stats) loop
 if exists(select 1 from jsonb_array_elements(p->'timeline') t where t->>'month'=to_char(now(),'YYYY-MM')) then
 for u in select w.user_id from public.user_program_watchlist w left join public.notification_preferences f on f.user_id=w.user_id where w.program_id=(p->>'id')::uuid and not w.alerts_muted and coalesce(f.watchlist,true) loop
 perform cme_private.enqueue_notification(u.user_id,'watchlist_activity','activity:'||(p->>'id')||':'||to_char(now(),'YYYY-MM'),'Actividad comunitaria disponible',coalesce(p->>'name','Programa guardado')||'. Hay actividad agregada que cumple el umbral de privacidad.', '#/program/'||(p->>'id'),(p->>'id')::uuid);
 end loop;end if;end loop;end loop;
 for i in select v.id,v.user_id,v.applicant_cycle_id,v.start_at,v.status,v.end_at,v.updated_at,f.* from public.interview_events v join public.notification_preferences f on f.user_id=v.user_id where (f.interview_reminders or f.followup) and v.status in ('scheduled','completed') loop
 if i.status='scheduled' and i.interview_reminders then
 if i.reminder_24h and i.start_at>now() and i.start_at<=now()+interval '24 hours' then
 perform cme_private.enqueue_notification(i.user_id,'interview_reminder','interview:'||i.id||':24h:'||i.start_at,'Próximo evento de entrevista','Tienes un evento de entrevista en las próximas 24 horas. Abre tu Tracker para los detalles.','#/interviews',null,i.applicant_cycle_id,i.start_at);
 end if;
 if i.reminder_2h and i.start_at>now() and i.start_at<=now()+interval '2 hours' then
 perform cme_private.enqueue_notification(i.user_id,'interview_reminder','interview:'||i.id||':2h:'||i.start_at,'Tu evento se acerca','Tienes un evento de entrevista en las próximas 2 horas. Abre tu Tracker para los detalles.','#/interviews',null,i.applicant_cycle_id,i.start_at);
 end if;
 elsif i.status='completed' and i.followup and i.updated_at>now()-interval '7 days' then
 perform cme_private.enqueue_notification(i.user_id,'interview_followup','followup:'||i.id,'Revisa tu seguimiento','Puedes revisar tus notas y thank-you pendientes en tu Tracker privado.','#/interviews',null,i.applicant_cycle_id);
 end if;end loop;
 perform cme_private.generate_notification_digests();
 update cme_private.notification_runtime set last_generation=now() where singleton=true;
 -- Documented retention. Queue deletion cascades only for expired retained metadata.
 delete from public.notifications where created_at<now()-interval '180 days';
 delete from public.notification_deliveries where created_at<now()-interval '30 days';
end $$;
revoke all on function cme_private.generate_notification_events() from public,anon,authenticated;
