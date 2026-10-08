-- Official public catalogues are independent sources. Never infer ERAS status from accreditation.
create table public.catalog_sources(
 source text primary key check(source in ('acgme','aamc')),season integer not null default 0,
 source_url text not null,last_attempt_at timestamptz,last_success_at timestamptz,last_error text
);
create table public.catalog_sync_state(
 source text not null references public.catalog_sources(source),season integer not null,specialty_id text not null,
 name text not null,source_url text not null,active boolean not null default true,baseline_complete boolean not null default false,
 last_attempt_at timestamptz,last_success_at timestamptz,last_error text,program_count integer not null default 0,
 primary key(source,season,specialty_id)
);
create table public.catalog_programs(
 source text not null,season integer not null,specialty_id text not null,acgme_program_id text not null,
 name text not null,specialty text not null,city text,state text,status text not null,source_url text not null,external_id text,
 tracks jsonb not null default '[]',present boolean not null default true,revision integer not null default 0,first_seen_at timestamptz not null default now(),last_seen_at timestamptz not null default now(),
 primary key(source,season,specialty_id,acgme_program_id),
 foreign key(source,season,specialty_id) references public.catalog_sync_state(source,season,specialty_id)
);
create index catalog_program_identity on public.catalog_programs(acgme_program_id,source,season);
create index catalog_sync_due on public.catalog_sync_state(source,season,last_attempt_at);
alter table public.catalog_sources enable row level security;
alter table public.catalog_sync_state enable row level security;
alter table public.catalog_programs enable row level security;
revoke all on public.catalog_sources,public.catalog_sync_state,public.catalog_programs from public,anon,authenticated;
grant all on public.catalog_sources,public.catalog_sync_state,public.catalog_programs to service_role;
insert into public.catalog_sources(source,season,source_url) values
 ('acgme',0,'https://apps.acgme.org/ads/Public/Programs/Search'),
 ('aamc',0,'https://systems.aamc.org/eras/erasstats/par/index.cfm');
-- A separate, server-only dispatch token; never put credentials in cron text or in the browser.
create table cme_private.catalog_runtime(singleton boolean primary key default true check(singleton),dispatch_token text not null,lease_until timestamptz,lease_id uuid);
insert into cme_private.catalog_runtime(dispatch_token) values(encode(extensions.gen_random_bytes(48),'hex'));
alter table cme_private.catalog_runtime enable row level security;
revoke all on cme_private.catalog_runtime from public,anon,authenticated;
create function public.catalog_claim(p_token text) returns uuid language plpgsql security definer set search_path='' as $$
declare lease uuid:=gen_random_uuid();begin
 update cme_private.catalog_runtime set lease_until=now()+interval '4 minutes',lease_id=lease
 where singleton and dispatch_token=p_token and coalesce(lease_until,'-infinity')<now();
 if found then return lease;end if;return null;end $$;
create function public.catalog_release(p_lease uuid) returns void language sql security definer set search_path='' as $$
 update cme_private.catalog_runtime set lease_until=null,lease_id=null where lease_id=p_lease;
$$;
revoke all on function public.catalog_claim(text),public.catalog_release(uuid) from public,anon,authenticated;
grant execute on function public.catalog_claim(text),public.catalog_release(uuid) to service_role;
alter table public.acgme_specialties add column if not exists last_attempt_at timestamptz;
-- Repair historical misleading success timestamps only where the recorded attempt failed.
update public.acgme_specialties set last_attempt_at=last_synced_at,last_synced_at=null where last_error is not null;
alter table public.program_change_events add column source text;
alter table public.program_change_events add column source_season integer;
alter table public.program_change_events add column participation_status text;
update public.program_change_events set source='acgme' where event_key like 'acgme-%';

create function public.catalog_apply_snapshot(p_source text,p_season integer,p_specialty_id text,p_rows jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.catalog_sync_state;r record;old public.catalog_programs;pid uuid;changed integer:=0;new_count integer:=0;is_new boolean;has_old boolean;event_kind text;
begin
 select * into s from public.catalog_sync_state where source=p_source and season=p_season and specialty_id=p_specialty_id for update;
 if not found then raise exception 'Unknown source/specialty';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>3000 then raise exception 'Invalid snapshot';end if;
 if s.program_count>0 and jsonb_array_length(p_rows)<s.program_count*0.7 then raise exception 'Catalogue shrank by more than 30 percent; preserve previous snapshot for review';end if;
 if (select count(distinct x->>'acgme_program_id') from jsonb_array_elements(p_rows)x)<>jsonb_array_length(p_rows) then raise exception 'Duplicate IDs';end if;
 for r in select * from jsonb_to_recordset(p_rows) as x(acgme_program_id text,name text,specialty text,city text,state text,status text,source_url text,external_id text,tracks jsonb) loop
  if r.name is null or r.status is null or r.acgme_program_id !~ '^[A-Za-z0-9-]{5,20}$' then raise exception 'Malformed program';end if;
  if p_source='acgme' and (r.acgme_program_id !~ '^[0-9]{10}$' or r.source_url not like 'https://apps.acgme.org/ads/Public/Programs/%') then raise exception 'Invalid ACGME provenance';end if;
  if p_source='aamc' and (r.source_url not like 'https://systems.aamc.org/eras/erasstats/par/display.cfm?%' or r.status not in ('Participating','Not Participating','Unregistered','No Longer Accepting Applications','Mixed participation')) then raise exception 'Invalid AAMC provenance';end if;
  select * into old from public.catalog_programs where source=p_source and season=p_season and specialty_id=p_specialty_id and acgme_program_id=r.acgme_program_id;
  has_old:=found;is_new:=not has_old;pid:=null;
  -- Only ACGME assigns accreditation. AAMC can add a public listing with unverified accreditation.
  if r.acgme_program_id ~ '^[0-9]{10}$' then
   insert into public.programs(acgme_program_id,name,specialty,city,state,source,active)
    values(r.acgme_program_id,r.name,r.specialty,r.city,r.state,case when p_source='acgme' then 'ACGME Public' else 'AAMC ERAS' end,
     case when p_source='acgme' then r.status in ('Accredited','Future Accredited') else false end)
    on conflict(acgme_program_id) do nothing;
   select id into pid from public.programs where acgme_program_id=r.acgme_program_id;
   if p_source='acgme' then
    update public.programs set name=r.name,city=coalesce(r.city,city),active=r.status in ('Accredited','Future Accredited') where id=pid and
     (name is distinct from r.name or city is distinct from coalesce(r.city,city) or active is distinct from (r.status in ('Accredited','Future Accredited')));
    insert into public.program_external_sources(program_id,acgme_program_id,source,source_url,external_id,data_scope,last_verified_at)
     values(pid,r.acgme_program_id,'acgme',r.source_url,r.external_id,'ACGME public catalogue; listing status checked',now())
     on conflict(source,acgme_program_id) do update set source_url=excluded.source_url,external_id=excluded.external_id,last_verified_at=now(),data_scope=excluded.data_scope;
   elsif r.state is not null then
    update public.programs set state=r.state where id=pid and state is null;
   end if;
  end if;
  insert into public.catalog_programs(source,season,specialty_id,acgme_program_id,name,specialty,city,state,status,source_url,external_id,tracks)
   values(p_source,p_season,p_specialty_id,r.acgme_program_id,r.name,r.specialty,r.city,r.state,r.status,r.source_url,r.external_id,coalesce(r.tracks,'[]'::jsonb))
   on conflict(source,season,specialty_id,acgme_program_id) do update set name=excluded.name,specialty=excluded.specialty,city=excluded.city,state=excluded.state,status=excluded.status,source_url=excluded.source_url,external_id=excluded.external_id,tracks=excluded.tracks,present=true,last_seen_at=now(),
    revision=catalog_programs.revision+case when catalog_programs.status is distinct from excluded.status or catalog_programs.tracks is distinct from excluded.tracks or not catalog_programs.present then 1 else 0 end;
  -- Baselines populate the catalogue without falsely announcing old programs as newly accredited.
  if s.baseline_complete and (is_new or old.status is distinct from r.status or old.tracks is distinct from coalesce(r.tracks,'[]'::jsonb) or not old.present) then
   event_kind:=case when is_new then 'new_program' else 'program_update' end;
   insert into public.program_change_events(event_key,program_id,event_type,title,specialty,city,state,acgme_program_id,accreditation_status,source_url,source,source_season,participation_status)
    values('catalog:'||p_source||':'||p_season||':'||p_specialty_id||':'||r.acgme_program_id||':'||case when is_new then 0 else old.revision+1 end,
     pid,event_kind,r.name,r.specialty,r.city,coalesce(r.state,(select state from public.programs where id=pid)),r.acgme_program_id,
     case when p_source='acgme' then r.status end,r.source_url,p_source,p_season,case when p_source='aamc' then r.status end) on conflict do nothing;
   changed:=changed+1;if is_new then new_count:=new_count+1;end if;
  end if;
 end loop;
 -- Absence from a fully validated snapshot is NOT a withdrawal or ERAS non-participation.
 for old in select * from public.catalog_programs c where source=p_source and season=p_season and specialty_id=p_specialty_id and present and not exists(select 1 from jsonb_array_elements(p_rows)x where x->>'acgme_program_id'=c.acgme_program_id) loop
  update public.catalog_programs set present=false,revision=revision+1 where source=p_source and season=p_season and specialty_id=p_specialty_id and acgme_program_id=old.acgme_program_id;
  if s.baseline_complete then
   insert into public.program_change_events(event_key,program_id,event_type,title,specialty,city,state,acgme_program_id,source_url,source,source_season,participation_status,accreditation_status)
    values('catalog:'||p_source||':'||p_season||':'||p_specialty_id||':'||old.acgme_program_id||':'||(old.revision+1),(select id from public.programs where acgme_program_id=old.acgme_program_id),'program_update',old.name,old.specialty,old.city,old.state,old.acgme_program_id,old.source_url,p_source,p_season,case when p_source='aamc' then 'Not listed in latest catalogue' end,case when p_source='acgme' then 'Not listed in latest catalogue' end) on conflict do nothing;
  end if;
 end loop;
 update public.catalog_sync_state set baseline_complete=true,last_attempt_at=now(),last_success_at=now(),last_error=null,program_count=jsonb_array_length(p_rows) where source=p_source and season=p_season and specialty_id=p_specialty_id;
 if p_source='acgme' then update public.acgme_specialties set baseline_complete=true,last_attempt_at=now(),last_synced_at=now(),last_program_count=jsonb_array_length(p_rows),last_error=null where acgme_specialty_id=p_specialty_id;end if;
 return jsonb_build_object('programs',jsonb_array_length(p_rows),'new_programs',new_count,'changes',changed);
end $$;
revoke all on function public.catalog_apply_snapshot(text,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.catalog_apply_snapshot(text,integer,text,jsonb) to service_role;

create function public.program_catalog_health() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('checked_at',now(),'schedule_minutes',10,'freshness_hours',24,'sources',coalesce((select jsonb_agg(to_jsonb(x)) from(
  select c.source,c.season,c.source_url,c.last_success_at as discovery_success_at,c.last_error as discovery_error,
   count(s.*) filter(where s.active) as specialties_total,
   count(s.*) filter(where s.active and s.baseline_complete) as specialties_synced,
   count(s.*) filter(where s.active and s.last_success_at>now()-interval '24 hours' and s.last_error is null) as specialties_fresh,
   count(s.*) filter(where s.active and s.last_error is not null) as specialties_failed,
   min(s.last_success_at) filter(where s.active) as oldest_success_at,max(s.last_success_at) as latest_success_at,
   coalesce(sum(s.program_count) filter(where s.active),0) as programs,
   (select coalesce(jsonb_agg(jsonb_build_object('specialty',e.name,'error',e.last_error)),'[]') from (select name,last_error from public.catalog_sync_state where source=c.source and season=c.season and active and last_error is not null order by last_attempt_at desc limit 5)e) as errors
  from public.catalog_sources c left join public.catalog_sync_state s on s.source=c.source and s.season=c.season group by c.source
 )x),'[]'));
$$;
revoke all on function public.program_catalog_health() from public;
grant execute on function public.program_catalog_health() to anon,authenticated,service_role;

create function cme_private.catalog_directory() returns table(acgme_program_id text,program_id uuid,name text,specialty text,city text,state text,acgme_status text,acgme_checked_at timestamptz,acgme_url text,eras_status text,eras_checked_at timestamptz,eras_url text,eras_season integer,eras_tracks jsonb)
language sql stable security definer set search_path='' as $$
 with a as(select distinct on(c.acgme_program_id) c.* from public.catalog_programs c where c.source='acgme' and c.season=0 order by c.acgme_program_id,c.present desc,c.last_seen_at desc),
 e as(select distinct on(c.acgme_program_id) c.* from public.catalog_programs c join public.catalog_sources s on s.source=c.source and s.season=c.season where c.source='aamc' order by c.acgme_program_id,c.present desc,c.last_seen_at desc)
 select coalesce(a.acgme_program_id,e.acgme_program_id),p.id,coalesce(a.name,e.name),coalesce(a.specialty,e.specialty),coalesce(a.city,e.city),coalesce(e.state,p.state,a.state),
 case when a.acgme_program_id is null then 'Not verified' when not a.present then 'Not listed in latest catalogue' else a.status end,a.last_seen_at,a.source_url,
 case when e.acgme_program_id is null then 'Not verified' when not e.present then 'Not listed in latest catalogue' else e.status end,e.last_seen_at,e.source_url,(select season from public.catalog_sources where source='aamc'),coalesce(e.tracks,'[]'::jsonb)
 from a full join e using(acgme_program_id) left join public.programs p on p.acgme_program_id=coalesce(a.acgme_program_id,e.acgme_program_id);
$$;
revoke all on function cme_private.catalog_directory() from public,anon,authenticated;
create function public.program_catalog_watch(p_query text default '',p_specialty text default null,p_state text default null,p_status text default null,p_offset integer default 0) returns jsonb language sql stable security definer set search_path='' as $$
 with filtered as(select * from cme_private.catalog_directory() d where
  (coalesce(p_query,'')='' or strpos(lower(d.name||' '||d.acgme_program_id),lower(left(p_query,200)))>0)
  and (nullif(trim(p_specialty),'') is null or lower(d.specialty)=lower(trim(p_specialty)))
  and (nullif(trim(p_state),'') is null or upper(d.state)=upper(trim(p_state)))
  and (nullif(p_status,'') is null or d.eras_status=p_status or exists(select 1 from jsonb_array_elements(d.eras_tracks)t where t->>'status'=p_status))),
 page as(select * from filtered order by name,acgme_program_id offset greatest(coalesce(p_offset,0),0) limit 30)
 select jsonb_build_object('programs',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from filtered),'has_more',(select count(*) from filtered)>greatest(coalesce(p_offset,0),0)+30);
$$;
revoke all on function public.program_catalog_watch(text,text,text,text,integer) from public;
grant execute on function public.program_catalog_watch(text,text,text,text,integer) to anon,authenticated,service_role;
create or replace function public.program_radar(p_specialty text default null,p_state text default null,p_since timestamptz default now()-interval '90 days',p_until timestamptz default now()) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x)||coalesce((select to_jsonb(d) from cme_private.catalog_directory()d where d.acgme_program_id=x.acgme_program_id),'{}')),'[]') from
 (select * from public.program_change_events where detected_at>=p_since and detected_at<=p_until and (nullif(trim(p_specialty),'') is null or lower(specialty)=lower(trim(p_specialty))) and (nullif(trim(p_state),'') is null or upper(state)=upper(trim(p_state))) order by detected_at desc limit 100)x;
$$;
create function cme_private.catalog_tick(p_source text default null,p_limit integer default 4) returns bigint language sql security definer set search_path='' as $$
 select net.http_post(url:='https://xqjjiveuvnioachgxqez.supabase.co/functions/v1/acgme-program-monitor',headers:=jsonb_build_object('Content-Type','application/json','x-monitor-token',(select dispatch_token from cme_private.catalog_runtime)),body:=jsonb_build_object('source',p_source,'limit',least(greatest(p_limit,1),12)),timeout_milliseconds:=180000);
$$;
revoke all on function cme_private.catalog_tick(text,integer) from public,anon,authenticated;
select cron.alter_job(job_id:=jobid,command:='select cme_private.catalog_tick();') from cron.job where jobname='cuba-match-acgme-monitor';
