-- Only a fully checked, fresh catalogue can substantiate absence. Absence is not non-participation.
create or replace function cme_private.catalog_directory() returns table(acgme_program_id text,program_id uuid,name text,specialty text,city text,state text,acgme_status text,acgme_checked_at timestamptz,acgme_url text,eras_status text,eras_checked_at timestamptz,eras_url text,eras_season integer,eras_tracks jsonb)
language sql stable security definer set search_path='' as $$
 with coverage as(
 select c.source,c.season,c.source_url,c.last_error is null and c.last_success_at>now()-interval '24 hours' and count(s.*)>0 and bool_and(s.baseline_complete and s.last_success_at>now()-interval '24 hours' and s.last_error is null) as complete,min(s.last_success_at) checked_at
 from public.catalog_sources c left join public.catalog_sync_state s on s.source=c.source and s.season=c.season and s.active group by c.source
 ),
 a as(select distinct on(c.acgme_program_id) c.*,s.last_success_at snapshot_checked_at from public.catalog_programs c join public.catalog_sync_state s using(source,season,specialty_id) where c.source='acgme' and c.season=0 and s.active order by c.acgme_program_id,c.present desc,c.last_seen_at desc),
 e as(select distinct on(c.acgme_program_id) c.*,s.last_success_at snapshot_checked_at from public.catalog_programs c join public.catalog_sync_state s using(source,season,specialty_id) join public.catalog_sources origin on origin.source=c.source and origin.season=c.season where c.source='aamc' and s.active order by c.acgme_program_id,c.present desc,c.last_seen_at desc)
 select coalesce(a.acgme_program_id,e.acgme_program_id),p.id,coalesce(a.name,e.name),coalesce(a.specialty,e.specialty),coalesce(a.city,e.city),coalesce(e.state,p.state,a.state),
 case when a.acgme_program_id is null then case when ca.complete then 'Not listed in current catalogue' else 'Not verified' end when not a.present then 'Not listed in latest catalogue' else a.status end,
 case when a.acgme_program_id is null then case when ca.complete then ca.checked_at end when not a.present then a.snapshot_checked_at else a.last_seen_at end,coalesce(a.source_url,ca.source_url),
 case when e.acgme_program_id is null then case when ce.complete then 'Not listed in current catalogue' else 'Not verified' end when not e.present then 'Not listed in latest catalogue' else e.status end,
 case when e.acgme_program_id is null then case when ce.complete then ce.checked_at end when not e.present then e.snapshot_checked_at else e.last_seen_at end,coalesce(e.source_url,ce.source_url),ce.season,case when e.present then coalesce(e.tracks,'[]'::jsonb) else '[]'::jsonb end
 from a full join e using(acgme_program_id) left join public.programs p on p.acgme_program_id=coalesce(a.acgme_program_id,e.acgme_program_id)
 cross join (select * from coverage where source='acgme')ca cross join (select * from coverage where source='aamc')ce;
$$;
