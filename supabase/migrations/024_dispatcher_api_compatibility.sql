-- Explicit singleton predicates work with PostgREST safe-update protection.
create or replace function public.notification_worker_config(p_token text,p_public text default null,p_private text default null,p_email_ready boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare c cme_private.notification_runtime;
begin
 select * into c from cme_private.notification_runtime;
 if p_token is null or p_token<>c.dispatch_token then raise exception 'Unauthorized';end if;
 if p_public is not null and p_private is not null and c.vapid_private is null then update cme_private.notification_runtime set vapid_public=p_public,vapid_private=p_private,push_ready=true where singleton=true;end if;
 update cme_private.notification_runtime set email_ready=p_email_ready,last_dispatch=now() where singleton=true;
 select * into c from cme_private.notification_runtime;
 return jsonb_build_object('vapid_public',c.vapid_public,'vapid_private',c.vapid_private);
end $$;
revoke all on function public.notification_worker_config(text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.notification_worker_config(text,text,text,boolean) to service_role;

create index if not exists notifications_accreditation_fk on public.notifications(accreditation_event_id);
