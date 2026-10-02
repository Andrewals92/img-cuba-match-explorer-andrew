-- v4.1: private productivity records. No changes to historical/community reports.
create unique index if not exists applicant_cycles_id_owner_v41 on public.applicant_cycles(id,user_id);
create table if not exists public.interview_events (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 applicant_cycle_id uuid not null, program_id uuid, program_name_snapshot text not null check(length(trim(program_name_snapshot)) between 1 and 300),
 specialty text, report_id uuid references public.program_reports(id) on delete set null,
 event_type text not null default 'interview' check(event_type in ('interview','social','second_look','other')),
 status text not null default 'invited' check(status in ('invited','scheduled','completed','cancelled','declined')),
 invitation_received_date date, start_at timestamptz, end_at timestamptz,
 timezone text not null default 'America/New_York', format text not null default 'Virtual' check(format in ('Virtual','In-person','Hybrid')),
 location text check(length(location)<=2000), meeting_url text check(meeting_url is null or (length(meeting_url)<=2000 and meeting_url ~ '^https?://')),
 thank_you_sent boolean not null default false, thank_you_sent_at date,
 ranked boolean not null default false, rank_position integer check(rank_position between 1 and 1000),
 private_notes text check(length(private_notes)<=20000), private_impression jsonb not null default '{}'::jsonb check(jsonb_typeof(private_impression)='object' and octet_length(private_impression::text)<=20000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(applicant_cycle_id,user_id) references public.applicant_cycles(id,user_id) on delete cascade,
 check(end_at is null or (start_at is not null and end_at>start_at)),
 check(status<>'scheduled' or start_at is not null),
 check(rank_position is null or ranked), check(thank_you_sent_at is null or thank_you_sent)
);
create table if not exists public.user_program_watchlist (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 program_id uuid not null, interest_level text not null default 'interested' check(interest_level in ('high','interested','researching')),
 private_notes text check(length(private_notes)<=10000), created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(user_id,program_id)
);
create index if not exists interview_events_owner_cycle_time on public.interview_events(user_id,applicant_cycle_id,start_at);
create index if not exists interview_events_cycle on public.interview_events(applicant_cycle_id);
create index if not exists interview_events_report on public.interview_events(report_id) where report_id is not null;
create index if not exists interview_events_program on public.interview_events(program_id) where program_id is not null;
create index if not exists watchlist_program on public.user_program_watchlist(program_id);
create unique index if not exists interview_events_no_duplicates on public.interview_events(user_id,applicant_cycle_id,coalesce(program_id,'00000000-0000-0000-0000-000000000000'::uuid),(case when program_id is null then lower(trim(program_name_snapshot)) else '' end),event_type,coalesce(start_at,'-infinity'::timestamptz));
-- Narrow validator needs private directory metadata only; returns no data to caller.
create or replace function cme_private.validate_productivity_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and new.user_id<>old.user_id then raise exception 'Owner cannot change'; end if;
 if new.program_id is not null and not exists(select 1 from cme_private.program_directory p where p.id=new.program_id) then raise exception 'Unknown program identity'; end if;
 if TG_TABLE_NAME='interview_events' then
  if not exists(select 1 from pg_catalog.pg_timezone_names t where t.name=new.timezone) then raise exception 'Use an IANA timezone'; end if;
  if new.report_id is not null and not exists(select 1 from public.program_reports r where r.id=new.report_id and r.user_id=new.user_id and r.applicant_cycle_id=new.applicant_cycle_id) then raise exception 'Report must belong to this cycle and owner'; end if;
 end if;
 new.updated_at:=now();return new;
end $$;
revoke all on function cme_private.validate_productivity_record() from public,anon,authenticated;
drop trigger if exists validate_interview_workspace on public.interview_events;
create trigger validate_interview_workspace before insert or update on public.interview_events for each row execute function cme_private.validate_productivity_record();
drop trigger if exists validate_watchlist_workspace on public.user_program_watchlist;
create trigger validate_watchlist_workspace before insert or update on public.user_program_watchlist for each row execute function cme_private.validate_productivity_record();
alter table public.interview_events enable row level security;
alter table public.user_program_watchlist enable row level security;
revoke all on public.interview_events,public.user_program_watchlist from public,anon,authenticated;
grant select,insert,update,delete on public.interview_events,public.user_program_watchlist to authenticated;
drop policy if exists interview_owner on public.interview_events;
create policy interview_owner on public.interview_events for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
drop policy if exists watchlist_owner on public.user_program_watchlist;
create policy watchlist_owner on public.user_program_watchlist for all to authenticated using((select auth.uid())=user_id) with check((select auth.uid())=user_id);
