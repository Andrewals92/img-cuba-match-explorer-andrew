create or replace function public.notification_unread_count() returns integer language sql stable security invoker set search_path='' as $$ select count(*)::integer from public.notifications where user_id=(select auth.uid()) and read_at is null $$;
revoke all on function public.notification_unread_count() from public,anon;
grant execute on function public.notification_unread_count() to authenticated;
-- Avoid the same saved identity being recomputed in multiple batches.
-- Apply a limit to subscriptions per account at database level, not only UI.
create or replace function cme_private.validate_radar_filter() returns trigger language plpgsql set search_path='' as $$
begin
 if new.enabled and cardinality(new.specialties)=0 then raise exception 'Choose a specialty';end if;
 if exists(select 1 from unnest(new.states)s where s !~ '^[A-Z]{2}$') then raise exception 'Use two-letter state codes';end if;
 return new;end $$;
revoke all on function cme_private.validate_radar_filter() from public,anon,authenticated;
create trigger validate_radar_filter before insert or update on public.radar_subscriptions for each row execute function cme_private.validate_radar_filter();

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
 update cme_private.notification_runtime set last_generation=now();
 -- Documented retention. Queue deletion cascades only for expired retained metadata.
 delete from public.notifications where created_at<now()-interval '180 days';
 delete from public.notification_deliveries where created_at<now()-interval '30 days';
end $$;
revoke all on function cme_private.generate_notification_events() from public,anon,authenticated;
