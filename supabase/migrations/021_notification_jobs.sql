-- Program UUID is supplied by the actual updated row, never by its display name.
create or replace function cme_private.meaningful_program_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if lower(trim(new.specialty)) is distinct from lower(trim(old.specialty)) or new.active is distinct from old.active or (new.state is not null and old.state is not null and upper(new.state)<>upper(old.state)) then
 insert into public.program_change_events(event_key,program_id,event_type,title,specialty,city,state,acgme_program_id)
 values('program-update:'||new.id||':'||md5(to_jsonb(new)::text),new.id,'program_update',new.name,new.specialty,new.city,new.state,new.acgme_program_id) on conflict do nothing;
 end if;return new;
end $$;
revoke all on function cme_private.meaningful_program_change() from public,anon,authenticated;
create trigger meaningful_program_change after update on public.programs for each row execute function cme_private.meaningful_program_change();
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
 for ids in select array_agg(program_id) from(select distinct program_id,row_number() over(order by program_id) rn from public.user_program_watchlist where not alerts_muted)x group by (rn-1)/5 loop
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
create or replace function public.notification_worker_config(p_token text,p_public text default null,p_private text default null,p_email_ready boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare c cme_private.notification_runtime;
begin
 select * into c from cme_private.notification_runtime;
 if p_token is null or p_token<>c.dispatch_token then raise exception 'Unauthorized';end if;
 if p_public is not null and p_private is not null and c.vapid_private is null then update cme_private.notification_runtime set vapid_public=p_public,vapid_private=p_private,push_ready=true;end if;
 update cme_private.notification_runtime set email_ready=p_email_ready,last_dispatch=now();
 select * into c from cme_private.notification_runtime;
 return jsonb_build_object('vapid_public',c.vapid_public,'vapid_private',c.vapid_private);
end $$;
revoke all on function public.notification_worker_config(text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.notification_worker_config(text,text,text,boolean) to service_role;
create or replace function public.notification_claim_jobs(p_limit integer default 20) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 update public.notification_outbox o set status='cancelled',last_error_code='expired' from public.notifications n where n.id=o.notification_id and n.expires_at<now() and o.status in ('queued','blocked');
 -- Suppress opted-out work at send-time as well as enqueue-time.
 update public.notification_outbox o set status='cancelled',last_error_code='muted' from public.notification_preferences f,public.notifications n where f.user_id=o.user_id and n.id=o.notification_id and o.status in ('queued','blocked') and (not(case when o.channel='email' then f.email else f.push end) or (n.notification_type='new_program' and not f.radar) or(n.notification_type in ('program_update','watchlist_activity') and (not f.watchlist or exists(select 1 from public.user_program_watchlist w where w.user_id=o.user_id and w.program_id=n.program_id and w.alerts_muted))) or(n.notification_type='interview_reminder' and not f.interview_reminders));
 update public.notification_outbox o set not_before=cme_private.delivery_time(f,now()) from public.notification_preferences f where f.user_id=o.user_id and o.status in ('queued','blocked') and o.not_before<=now();
 with jobs as(select o.id from public.notification_outbox o join cme_private.notification_runtime r on true where ((o.status in ('queued','blocked') and o.not_before<=now()) or(o.status='processing' and o.lease_until<now())) and (case when o.channel='email' then r.email_ready else r.push_ready end) and o.attempt_count<5 and (select count(*) from public.notification_outbox d where d.user_id=o.user_id and d.channel=o.channel and d.status='sent' and d.updated_at>now()-interval '1 hour')<10 order by o.created_at for update of o skip locked limit least(greatest(p_limit,1),20)),claimed as(update public.notification_outbox o set status='processing',lease_until=now()+interval '5 minutes',lease_token=gen_random_uuid(),attempt_count=attempt_count+1,updated_at=now() from jobs where o.id=jobs.id returning o.*)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('notification',jsonb_build_object('title',n.title,'body',n.body,'action_path',n.action_path,'type',n.notification_type),'email',u.email)),'[]') into result from claimed c join public.notifications n on n.id=c.notification_id join auth.users u on u.id=c.user_id;
 return result;end $$;
revoke all on function public.notification_claim_jobs(integer) from public,anon,authenticated;
grant execute on function public.notification_claim_jobs(integer) to service_role;
create or replace function public.notification_finish_job(p_id uuid,p_lease uuid,p_status text,p_code text default null,p_provider text default null) returns void language plpgsql security definer set search_path='' as $$
declare job public.notification_outbox;begin
 select * into job from public.notification_outbox where id=p_id and lease_token=p_lease and status='processing' for update;
 if not found then return;end if;
 insert into public.notification_deliveries(outbox_id,attempt,status,error_code,provider_message_id) values(p_id,job.attempt_count,p_status,left(p_code,80),left(p_provider,200));
 update public.notification_outbox set status=case when p_status in ('sent','cancelled') then p_status when p_status='permanent' or attempt_count>=5 then 'failed' else 'queued' end,
 last_error_code=left(p_code,80),provider_message_id=left(p_provider,200),not_before=now()+interval '1 minute'*power(2,attempt_count),lease_until=null,lease_token=null,updated_at=now() where id=p_id;
end $$;
revoke all on function public.notification_finish_job(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.notification_finish_job(uuid,uuid,text,text,text) to service_role;
create or replace function public.notification_operations() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin required';end if;
 return jsonb_build_object('queued',(select count(*) from public.notification_outbox where status in ('queued','blocked')),'sent',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select channel,count(*) from public.notification_outbox where status='sent' group by channel)x),'failures',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select channel,status,last_error_code,count(*) from public.notification_outbox where status='failed' group by 1,2,3)x),'disabled_push',(select count(*) from public.push_subscriptions where not enabled),'last_generation',(select last_generation from cme_private.notification_runtime),'last_dispatch',(select last_dispatch from cme_private.notification_runtime));
end $$;
revoke all on function public.notification_operations() from public,anon;
grant execute on function public.notification_operations() to authenticated;
