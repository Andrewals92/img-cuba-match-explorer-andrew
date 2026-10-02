-- Constrain subscriptions against server-side request forgery; unsupported services fail gracefully.
alter table public.push_subscriptions add constraint trusted_push_endpoint check(endpoint ~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com)/');
create unique index if not exists push_delivery_once on public.notification_deliveries(outbox_id,subscription_id) where status='sent' and subscription_id is not null;
grant select,insert,update,delete on public.notification_outbox,public.notification_deliveries,public.push_subscriptions,public.notifications to service_role;
create or replace function cme_private.notification_tick() returns void language plpgsql security definer set search_path='' as $$
declare tok text;begin
 perform cme_private.generate_notification_events();
 select dispatch_token into tok from cme_private.notification_runtime;
 perform net.http_post(url:='https://xqjjiveuvnioachgxqez.supabase.co/functions/v1/notification-dispatcher',headers:=jsonb_build_object('Content-Type','application/json','x-dispatch-token',tok),body:='{}'::jsonb,timeout_milliseconds:=5000);
end $$;
revoke all on function cme_private.notification_tick() from public,anon,authenticated;
select cron.schedule('cme-notifications-v42','*/5 * * * *','select cme_private.notification_tick()');
-- Extend the pre-existing user erasure operation; no admin bypass for private delivery data.
create or replace function public.delete_my_data() returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=(select auth.uid());begin
 if uid is null then raise exception 'Authentication required';end if;
 delete from public.notifications where user_id=uid;
 delete from public.push_subscriptions where user_id=uid;
 delete from public.radar_subscriptions where user_id=uid;
 delete from public.notification_preferences where user_id=uid;
 delete from public.user_program_watchlist where user_id=uid;
 delete from public.interview_events where user_id=uid;
 delete from public.applicant_cycles where user_id=uid;
 delete from public.program_watch_subscriptions where user_id=uid;
 update public.profiles set display_name=null where id=uid;
end $$;
revoke all on function public.delete_my_data() from public,anon;
grant execute on function public.delete_my_data() to authenticated;
