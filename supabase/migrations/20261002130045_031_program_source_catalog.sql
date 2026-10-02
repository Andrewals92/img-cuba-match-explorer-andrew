-- Program-only sources supplied by owner. No applicant scores/likelihood/connections/comments.
create table if not exists cme_private.program_source_catalog_v43 (
 source_key text primary key,program_id uuid references public.programs(id) on delete set null,
 acgme_program_id text,name text not null,city text,state text,specialty text not null,
 source text not null,source_cycle integer,source_date date,program_url text,
 fields jsonb not null default '{}',imported_at timestamptz not null default now()
);
alter table cme_private.program_source_catalog_v43 enable row level security;
revoke all on cme_private.program_source_catalog_v43 from public,anon,authenticated;
create index if not exists source_catalog_program_v43 on cme_private.program_source_catalog_v43(program_id);
create or replace function public.program_resources_v43(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if coalesce(cardinality(p_ids),0)<1 or cardinality(p_ids)>50 then raise exception 'Select 1 to 50 programs';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('program_id',program_id,'name',name,'source',source,'source_cycle',source_cycle,'source_date',source_date,'program_url',program_url,'fields',fields) order by source,name),'[]') from cme_private.program_source_catalog_v43 where program_id=any(p_ids));
end $$;
revoke all on function public.program_resources_v43(uuid[]) from public;
grant execute on function public.program_resources_v43(uuid[]) to anon,authenticated;
create or replace function public.program_source_directory_v43(p_query text default '',p_offset integer default 0)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('programs',coalesce(jsonb_agg(jsonb_build_object('source_key',source_key,'program_id',program_id,'acgme_program_id',acgme_program_id,'name',name,'city',city,'state',state,'source',source,'source_cycle',source_cycle,'source_date',source_date,'program_url',program_url,'fields',fields) order by name,source),'[]'),'has_more',count(*)=30)
 from(select * from cme_private.program_source_catalog_v43 where coalesce(p_query,'')='' or concat_ws(' ',name,city,state,acgme_program_id) ilike '%'||left(p_query,160)||'%' order by name,source limit 30 offset greatest(0,least(coalesce(p_offset,0),5000)))x;
$$;
revoke all on function public.program_source_directory_v43(text,integer) from public;
grant execute on function public.program_source_directory_v43(text,integer) to anon,authenticated;
