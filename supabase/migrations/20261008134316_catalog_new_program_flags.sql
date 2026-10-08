-- Source labels (New Program / Osteopathic Recognized) are metadata, not participation changes.
create function cme_private.catalog_track_status(p_tracks jsonb) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('name',n,'status',s) order by n,s),'[]') from(
  select trim(regexp_replace(lower(t->>'name'),'new program!|osteopathic recognized!','','g')) n,t->>'status' s from jsonb_array_elements(coalesce(p_tracks,'[]'))t
 )x;
$$;
revoke all on function cme_private.catalog_track_status(jsonb) from public,anon,authenticated;
create or replace function public.catalog_apply_snapshot(p_source text,p_season integer,p_specialty_id text,p_rows jsonb) returns jsonb
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
    revision=catalog_programs.revision+case when catalog_programs.status is distinct from excluded.status or cme_private.catalog_track_status(catalog_programs.tracks) is distinct from cme_private.catalog_track_status(excluded.tracks) or not catalog_programs.present then 1 else 0 end;
  -- Baselines populate the catalogue without falsely announcing old programs as newly accredited.
  if s.baseline_complete and (is_new or old.status is distinct from r.status or cme_private.catalog_track_status(old.tracks) is distinct from cme_private.catalog_track_status(coalesce(r.tracks,'[]'::jsonb)) or not old.present) then
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
create or replace function public.program_catalog_watch(p_query text default '',p_specialty text default null,p_state text default null,p_status text default null,p_offset integer default 0) returns jsonb language sql stable security definer set search_path='' as $$
 with filtered as(select * from cme_private.catalog_directory() d where
  (coalesce(p_query,'')='' or strpos(lower(d.name||' '||d.acgme_program_id),lower(left(p_query,200)))>0)
  and (nullif(trim(p_specialty),'') is null or lower(d.specialty)=lower(trim(p_specialty)))
  and (nullif(trim(p_state),'') is null or upper(d.state)=upper(trim(p_state)))
  and (nullif(p_status,'') is null or (p_status='__new__' and exists(select 1 from jsonb_array_elements(d.eras_tracks)t where t->>'is_new'='true')) or d.eras_status=p_status or exists(select 1 from jsonb_array_elements(d.eras_tracks)t where t->>'status'=p_status))),
 page as(select * from filtered order by name,acgme_program_id offset greatest(coalesce(p_offset,0),0) limit 30)
 select jsonb_build_object('programs',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from filtered),'has_more',(select count(*) from filtered)>greatest(coalesce(p_offset,0),0)+30);
$$;
