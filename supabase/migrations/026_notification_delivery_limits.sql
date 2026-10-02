create or replace function cme_private.limit_push_devices() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,42));
 if TG_OP='UPDATE' and new.user_id<>old.user_id then raise exception 'Owner cannot change';end if;
 if not exists(select 1 from public.push_subscriptions where id=new.id) and(select count(*) from public.push_subscriptions where user_id=new.user_id)>=10 then raise exception 'Maximum 10 devices; remove an old device first';end if;
 return new;end $$;
revoke all on function cme_private.limit_push_devices() from public,anon,authenticated;
create trigger limit_push_devices before insert or update on public.push_subscriptions for each row execute function cme_private.limit_push_devices();

create or replace function public.notification_claim_jobs(p_limit integer default 20) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if not pg_catalog.pg_try_advisory_xact_lock(420026) then return '[]'::jsonb;end if;
 update public.notification_outbox o set status='cancelled',last_error_code='expired' from public.notifications n where n.id=o.notification_id and n.expires_at<now() and o.status in ('queued','blocked');
 -- Suppress opted-out work at send-time as well as enqueue-time.
 update public.notification_outbox o set status='cancelled',last_error_code='muted' from public.notification_preferences f,public.notifications n where f.user_id=o.user_id and n.id=o.notification_id and o.status in ('queued','blocked') and (not(case when o.channel='email' then f.email else f.push end) or (n.notification_type='new_program' and not f.radar) or(n.notification_type in ('program_update','watchlist_activity') and (not f.watchlist or exists(select 1 from public.user_program_watchlist w where w.user_id=o.user_id and w.program_id=n.program_id and w.alerts_muted))) or(n.notification_type='interview_reminder' and not f.interview_reminders));
 update public.notification_outbox o set not_before=cme_private.delivery_time(f,now()) from public.notification_preferences f where f.user_id=o.user_id and o.status in ('queued','blocked') and o.not_before<=now();
 with jobs as(select o.id from public.notification_outbox o join cme_private.notification_runtime r on true where ((o.status in ('queued','blocked') and o.not_before<=now()) or(o.status='processing' and o.lease_until<now())) and (case when o.channel='email' then r.email_ready else r.push_ready end) and o.attempt_count<5 and (select count(*) from public.notification_outbox d where d.user_id=o.user_id and d.channel=o.channel and d.status in ('sent','processing') and d.updated_at>now()-interval '1 hour')<10 order by o.created_at for update of o skip locked limit least(greatest(p_limit,1),5)),claimed as(update public.notification_outbox o set status='processing',lease_until=now()+interval '5 minutes',lease_token=gen_random_uuid(),attempt_count=attempt_count+1,updated_at=now() from jobs where o.id=jobs.id returning o.*)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('notification',jsonb_build_object('title',n.title,'body',n.body,'action_path',n.action_path,'type',n.notification_type,'expires_at',n.expires_at),'email',u.email)),'[]') into result from claimed c join public.notifications n on n.id=c.notification_id join auth.users u on u.id=c.user_id;
 return result;end $$;
revoke all on function public.notification_claim_jobs(integer) from public,anon,authenticated;
grant execute on function public.notification_claim_jobs(integer) to service_role;
