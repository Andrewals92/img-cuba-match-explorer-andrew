-- v4.2: extend existing notification identity; no historical applicant changes.
alter table public.notifications add column if not exists event_key text;
alter table public.notifications add column if not exists program_id uuid;
alter table public.notifications add column if not exists applicant_cycle_id uuid;
alter table public.notifications add column if not exists action_path text not null default '#/radar';
alter table public.notifications add column if not exists expires_at timestamptz;
update public.notifications set event_key='legacy:'||id where event_key is null;
alter table public.notifications alter column event_key set not null;
create unique index if not exists notification_event_once on public.notifications(user_id,event_key,notification_type);
create index if not exists notification_owner_read_time on public.notifications(user_id,read_at,created_at desc);
-- Read-state only, including for admins. No direct creation/deletion or content edits.
drop policy if exists admin_manage_notifications on public.notifications;
drop policy if exists "users delete own notifications" on public.notifications;
revoke all on public.notifications from public,anon,authenticated;
grant select,update(read_at) on public.notifications to authenticated;
create table if not exists public.notification_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 in_app boolean not null default true,email boolean not null default false,push boolean not null default false,
 radar boolean not null default true,watchlist boolean not null default true,interview_reminders boolean not null default false,
 reminder_24h boolean not null default true,reminder_2h boolean not null default false,followup boolean not null default false,
 digest text not null default 'off' check(digest in ('off','daily','weekly')),
 timezone text not null default 'America/New_York',quiet_start time,quiet_end time,
 updated_at timestamptz not null default now(),check((quiet_start is null)=(quiet_end is null))
);
create table if not exists public.radar_subscriptions(
 user_id uuid primary key references auth.users(id) on delete cascade,
 specialties text[] not null default '{}',states text[] not null default '{}',enabled boolean not null default false,
 check(cardinality(specialties)<=30 and cardinality(states)<=60)
);
create table if not exists public.push_subscriptions(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null check(length(endpoint)<=2000 and endpoint ~ '^https://'),
 p256dh text not null check(length(p256dh) between 40 and 200),auth text not null check(length(auth) between 16 and 100),
 enabled boolean not null default true,created_at timestamptz not null default now(),unique(user_id,endpoint)
);
alter table public.user_program_watchlist add column if not exists alerts_muted boolean not null default false;
create table if not exists public.program_change_events(
 id uuid primary key default gen_random_uuid(),event_key text not null unique,program_id uuid references public.programs(id) on delete cascade,
 event_type text not null check(event_type in ('new_program','program_update')),title text not null,
 specialty text,city text,state text,acgme_program_id text,accreditation_status text,effective_date date,
 source_url text,detected_at timestamptz not null default now()
);
create index if not exists change_events_detected on public.program_change_events(detected_at desc);
create index if not exists change_events_program on public.program_change_events(program_id);
create table if not exists public.notification_outbox(
 id uuid primary key default gen_random_uuid(),notification_id uuid not null references public.notifications(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,channel text not null check(channel in ('email','push')),
 status text not null default 'queued' check(status in ('queued','processing','sent','failed','cancelled','blocked')),
 not_before timestamptz not null default now(),attempt_count integer not null default 0,
 lease_until timestamptz,lease_token uuid,last_error_code text,provider_message_id text,
 dedupe_key text not null unique,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists outbox_ready on public.notification_outbox(status,not_before);
create index if not exists outbox_notification on public.notification_outbox(notification_id);
create index if not exists outbox_owner on public.notification_outbox(user_id,created_at);
create table if not exists public.notification_deliveries(
 id uuid primary key default gen_random_uuid(),outbox_id uuid not null references public.notification_outbox(id) on delete cascade,
 subscription_id uuid references public.push_subscriptions(id) on delete set null,attempt integer not null,
 status text not null,error_code text,provider_message_id text,created_at timestamptz not null default now()
);
create index if not exists delivery_outbox on public.notification_deliveries(outbox_id);
create index if not exists delivery_subscription on public.notification_deliveries(subscription_id);
create table if not exists cme_private.notification_runtime(
 singleton boolean primary key default true check(singleton),dispatch_token text not null default encode(extensions.gen_random_bytes(32),'hex'),
 vapid_public text,vapid_private text,email_ready boolean not null default false,push_ready boolean not null default false,
 last_generation timestamptz,last_dispatch timestamptz
);
insert into cme_private.notification_runtime(singleton) values(true) on conflict do nothing;
alter table cme_private.notification_runtime enable row level security;
revoke all on cme_private.notification_runtime from public,anon,authenticated;
-- Generic private owner policies, no administrator bypass.
do $$ declare t text;begin
 foreach t in array array['notification_preferences','radar_subscriptions','push_subscriptions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 execute format('create policy owner_v42 on public.%I for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id)',t);
 end loop;
 foreach t in array array['program_change_events','notification_outbox','notification_deliveries'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;
create or replace function cme_private.validate_notification_preferences() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) or (new.timezone<>'UTC' and new.timezone !~ '^[A-Za-z_]+/[A-Za-z0-9_+/-]+$') then raise exception 'Use an IANA timezone';end if;
 new.updated_at=now();return new;
end $$;
revoke all on function cme_private.validate_notification_preferences() from public,anon,authenticated;
create trigger validate_notification_preferences before insert or update on public.notification_preferences for each row execute function cme_private.validate_notification_preferences();
create or replace function public.notification_channel_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('email_ready',email_ready,'push_ready',push_ready,'vapid_public',vapid_public) from cme_private.notification_runtime;
$$;
revoke all on function public.notification_channel_status() from public,anon;
grant execute on function public.notification_channel_status() to authenticated;
create or replace function public.program_radar(p_specialty text default null,p_state text default null,p_since timestamptz default now()-interval '90 days',p_until timestamptz default now()) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from public.program_change_events where detected_at>=p_since and detected_at<=p_until and (p_specialty is null or lower(specialty)=lower(p_specialty)) and (p_state is null or upper(state)=upper(p_state)) order by detected_at desc limit 100)x;
$$;
revoke all on function public.program_radar(text,text,timestamptz,timestamptz) from public;
grant execute on function public.program_radar(text,text,timestamptz,timestamptz) to anon,authenticated;
create or replace function cme_private.delivery_time(p public.notification_preferences,p_at timestamptz) returns timestamptz language plpgsql stable set search_path='' as $$
declare l timestamp:=p_at at time zone p.timezone;t time:=l::time;d date:=l::date;
begin
 if p.quiet_start is null or p.quiet_start=p.quiet_end then return p_at;end if;
 if p.quiet_start<p.quiet_end then
  if t>=p.quiet_start and t<p.quiet_end then return (d+p.quiet_end) at time zone p.timezone;end if;
 else
  if t>=p.quiet_start then return ((d+1)+p.quiet_end) at time zone p.timezone;
  elsif t<p.quiet_end then return (d+p.quiet_end) at time zone p.timezone;end if;
 end if;return p_at;
end $$;
revoke all on function cme_private.delivery_time(public.notification_preferences,timestamptz) from public,anon,authenticated;
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
 if (ch='email' and pref.email) or (ch='push' and pref.push) then
 insert into public.notification_outbox(notification_id,user_id,channel,not_before,dedupe_key) values(nid,p_user,ch,at_time,nid::text||':'||ch) on conflict do nothing;
 end if;end loop;return nid;
end $$;
revoke all on function cme_private.enqueue_notification(uuid,text,text,text,text,text,uuid,uuid,timestamptz) from public,anon,authenticated;
-- ACGME first-seen events already have canonical deterministic keys and baseline suppression.
drop trigger if exists notify_watchers_new_acgme_program on public.accreditation_events;
create or replace function cme_private.radar_event_from_acgme() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid;
begin
 select id into pid from public.programs where acgme_program_id=new.acgme_program_id;
 insert into public.program_change_events(event_key,program_id,event_type,title,specialty,city,state,acgme_program_id,accreditation_status,effective_date,source_url,detected_at)
 values(new.event_key,pid,'new_program',new.program_name,new.specialty,new.city,new.state,new.acgme_program_id,new.accreditation_status,new.effective_date,new.source_url,new.first_seen_at) on conflict do nothing;return new;
end $$;
revoke all on function cme_private.radar_event_from_acgme() from public,anon,authenticated;
create trigger radar_event_from_acgme after insert on public.accreditation_events for each row execute function cme_private.radar_event_from_acgme();
-- Safe migration of existing explicit Radar filters, without turning on email/push.
insert into public.radar_subscriptions(user_id,specialties,states,enabled)
select user_id,array_agg(distinct specialty),case when bool_or(state is null or state='') then '{}'::text[] else array_agg(distinct state) end,true from public.program_watch_subscriptions where enabled group by user_id on conflict do nothing;
