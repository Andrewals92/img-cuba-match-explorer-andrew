create table if not exists cme_private.monitored_program_status(
 program_id uuid primary key references public.programs(id) on delete cascade,
 status text,effective_date date,revision integer not null default 0,checked_at timestamptz not null default now()
);
alter table cme_private.monitored_program_status enable row level security;
revoke all on cme_private.monitored_program_status from public,anon,authenticated;
create or replace function public.notification_monitor_targets() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select p.id,p.acgme_program_id,p.specialty,s.source_url from public.programs p join public.program_external_sources s on s.acgme_program_id=p.acgme_program_id and s.source='acgme' left join cme_private.monitored_program_status m on m.program_id=p.id where exists(select 1 from public.user_program_watchlist w where w.program_id=p.id and not w.alerts_muted) order by m.checked_at asc nulls first limit 10)x;
$$;
revoke all on function public.notification_monitor_targets() from public,anon,authenticated;
grant execute on function public.notification_monitor_targets() to service_role;
create or replace function public.notification_record_program_status(p_id uuid,p_status text,p_date date default null) returns void language plpgsql security definer set search_path='' as $$
declare old cme_private.monitored_program_status;p public.programs;begin
 if p_status is null or length(trim(p_status))<2 or length(p_status)>100 then return;end if;
 select * into p from public.programs where id=p_id;if not found then return;end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,428));
 select * into old from cme_private.monitored_program_status where program_id=p_id;
 if found and(lower(trim(old.status)) is distinct from lower(trim(p_status)) or(old.effective_date is not null and p_date is not null and old.effective_date<>p_date)) then
 insert into public.program_change_events(event_key,program_id,event_type,title,specialty,city,state,acgme_program_id,accreditation_status,effective_date,source_url)
 values('status:'||p_id||':'||(old.revision+1),p_id,'program_update',p.name,p.specialty,p.city,p.state,p.acgme_program_id,trim(p_status),p_date,'https://apps.acgme.org/ads/Public/Programs/Search') on conflict do nothing;
 update cme_private.monitored_program_status set revision=revision+1 where program_id=p_id;
 end if;
 insert into cme_private.monitored_program_status(program_id,status,effective_date) values(p_id,trim(p_status),p_date)
 on conflict(program_id) do update set status=excluded.status,effective_date=coalesce(excluded.effective_date,monitored_program_status.effective_date),checked_at=now();
end $$;
revoke all on function public.notification_record_program_status(uuid,text,date) from public,anon,authenticated;
grant execute on function public.notification_record_program_status(uuid,text,date) to service_role;
