-- Cuba Match Explorer — Program Intelligence
-- Add after the base schema.sql
create schema if not exists private;

create table if not exists public.acgme_specialties (
  acgme_specialty_id text primary key,
  name text not null,
  active boolean not null default true,
  baseline_complete boolean not null default false,
  last_synced_at timestamptz,
  last_program_count integer,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.program_external_sources (
  id uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs(id) on delete set null,
  acgme_program_id text not null,
  source text not null check (source in ('acgme','freida','residency_explorer')),
  external_id text,
  source_url text not null,
  data_scope text,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source, acgme_program_id)
);

create table if not exists public.accreditation_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  acgme_program_id text not null,
  program_name text not null,
  specialty text not null,
  city text,
  state text,
  accreditation_status text,
  effective_date date,
  source_url text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.program_watch_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  specialty text not null,
  state text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists program_watch_unique_idx
  on public.program_watch_subscriptions(user_id, lower(specialty), coalesce(upper(state),''));

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  accreditation_event_id uuid references public.accreditation_events(id) on delete cascade,
  notification_type text not null default 'new_acgme_program',
  title text not null,
  body text not null,
  source_url text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id, accreditation_event_id)
);

create or replace function public.set_program_intelligence_updated_at()
returns trigger language plpgsql set search_path='public' as $$
begin new.updated_at=now(); return new; end; $$;

drop trigger if exists set_program_watch_subscriptions_updated_at on public.program_watch_subscriptions;
create trigger set_program_watch_subscriptions_updated_at before update on public.program_watch_subscriptions
for each row execute function public.set_program_intelligence_updated_at();

create or replace function private.notify_watchers_of_new_program()
returns trigger language plpgsql security definer set search_path='public','private' as $$
begin
  insert into public.notifications(user_id, accreditation_event_id, title, body, source_url)
  select s.user_id, new.id,
         'Nuevo programa ACGME: ' || new.specialty,
         new.program_name || coalesce(' — ' || new.city, '') || coalesce(', ' || new.state, ''),
         new.source_url
  from public.program_watch_subscriptions s
  where s.enabled=true
    and lower(s.specialty)=lower(new.specialty)
    and (s.state is null or s.state='' or upper(s.state)=upper(coalesce(new.state,'')))
  on conflict do nothing;
  return new;
end; $$;

drop trigger if exists notify_watchers_new_acgme_program on public.accreditation_events;
create trigger notify_watchers_new_acgme_program after insert on public.accreditation_events
for each row execute function private.notify_watchers_of_new_program();

create or replace function public.new_accredited_programs(
  p_specialty text default null,
  p_state text default null,
  p_since timestamptz default now()-interval '30 days'
) returns table(
  acgme_program_id text, program_name text, specialty text, city text, state text,
  accreditation_status text, effective_date date, first_seen_at timestamptz, source_url text
) language sql stable set search_path='public' as $$
  select e.acgme_program_id,e.program_name,e.specialty,e.city,e.state,
         e.accreditation_status,e.effective_date,e.first_seen_at,e.source_url
  from public.accreditation_events e
  where (p_specialty is null or lower(e.specialty)=lower(p_specialty))
    and (p_state is null or upper(e.state)=upper(p_state))
    and e.first_seen_at>=p_since
  order by e.first_seen_at desc;
$$;

grant execute on function public.new_accredited_programs(text,text,timestamptz) to anon, authenticated;

alter table public.acgme_specialties enable row level security;
alter table public.program_external_sources enable row level security;
alter table public.accreditation_events enable row level security;
alter table public.program_watch_subscriptions enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "acgme specialties are publicly readable" on public.acgme_specialties;
create policy "acgme specialties are publicly readable" on public.acgme_specialties for select to anon,authenticated using(true);
drop policy if exists "external sources are publicly readable" on public.program_external_sources;
create policy "external sources are publicly readable" on public.program_external_sources for select to anon,authenticated using(true);
drop policy if exists "accreditation events are publicly readable" on public.accreditation_events;
create policy "accreditation events are publicly readable" on public.accreditation_events for select to anon,authenticated using(true);

drop policy if exists "users read own watch subscriptions" on public.program_watch_subscriptions;
create policy "users read own watch subscriptions" on public.program_watch_subscriptions for select to authenticated using(auth.uid()=user_id);
drop policy if exists "users create own watch subscriptions" on public.program_watch_subscriptions;
create policy "users create own watch subscriptions" on public.program_watch_subscriptions for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "users update own watch subscriptions" on public.program_watch_subscriptions;
create policy "users update own watch subscriptions" on public.program_watch_subscriptions for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "users delete own watch subscriptions" on public.program_watch_subscriptions;
create policy "users delete own watch subscriptions" on public.program_watch_subscriptions for delete to authenticated using(auth.uid()=user_id);

drop policy if exists "users read own notifications" on public.notifications;
create policy "users read own notifications" on public.notifications for select to authenticated using(auth.uid()=user_id);
drop policy if exists "users mark own notifications" on public.notifications;
create policy "users mark own notifications" on public.notifications for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "users delete own notifications" on public.notifications;
create policy "users delete own notifications" on public.notifications for delete to authenticated using(auth.uid()=user_id);
