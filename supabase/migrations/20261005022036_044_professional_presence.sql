-- Professional education evidence only. No person-level ethnicity or nationality.
create table cme_private.presence_schools (
 id text primary key, name text not null, country text not null default 'CU' check(country='CU'),
 aliases text[] not null default '{}'
);
create table cme_private.presence_people (
 id text primary key, full_name text not null, school_id text not null references cme_private.presence_schools,
 education_status text not null check(education_status in ('attended','graduated','medical_education')),
 education_source jsonb not null check(jsonb_typeof(education_source)='object' and education_source->>'url' like 'https://%'),
 linkedin_url text check(linkedin_url ~ '^https://([a-z]+\.)?linkedin\.com/in/[^/?#]+/?$'),
 linkedin_checked_at date, linkedin_note text,
 confidence text not null check(confidence in ('high','moderate','unverified')),
 verified_at date not null, updated_at timestamptz not null default now()
);
create table cme_private.presence_affiliations (
 id text primary key, person_id text not null references cme_private.presence_people,
 program_id uuid not null references public.programs(id),
 role text not null check(role in ('resident','chief','fellow','faculty','leadership','alumnus')),
 period_key text not null, temporal_status text not null check(temporal_status in ('current','historical','last_seen_unknown')),
 pgy integer check(pgy between 1 and 12), class_year integer check(class_year between 1900 and 2100),
 start_year integer, end_year integer, source jsonb not null check(source->>'url' like 'https://%'),
 verified_at date not null, published boolean not null default false,
 unique(person_id,program_id,role,period_key), check(end_year is null or start_year is null or end_year>=start_year)
);
create index presence_aff_program_idx on cme_private.presence_affiliations(program_id) where published;
create table cme_private.presence_reviews (
 program_id uuid primary key references public.programs(id),
 review_status text not null check(review_status in ('partial','reviewed','needs_review')),
 verified_at date not null, next_review_at date not null,
 completeness text not null check(completeness in ('high','medium','limited')),
 source_url text not null check(source_url like 'https://%'), notes text not null,
 verified_state text check(verified_state ~ '^[A-Z]{2}$'), verified_city text
);
create table cme_private.presence_aggregates (
 id text primary key, program_id uuid not null references public.programs(id),
 percentage numeric check(percentage between 0 and 100), period_label text not null, scope text not null,
 source jsonb not null check(source->>'url' like 'https://%'), verified_at date not null,
 published boolean not null default false
);
create table cme_private.presence_revision_log (
 id bigint generated always as identity primary key, table_name text not null, record_key text not null,
 old_record jsonb, new_record jsonb, changed_at timestamptz not null default now()
);
create function cme_private.presence_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into cme_private.presence_revision_log(table_name,record_key,old_record,new_record)
 values(tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(new)->>'program_id',to_jsonb(old)->>'id',to_jsonb(old)->>'program_id'),
 case when tg_op<>'INSERT' then to_jsonb(old) end,case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
end $$;
revoke all on function cme_private.presence_audit() from public,anon,authenticated;
create trigger presence_people_audit after insert or update or delete on cme_private.presence_people for each row execute function cme_private.presence_audit();
create trigger presence_aff_audit after insert or update or delete on cme_private.presence_affiliations for each row execute function cme_private.presence_audit();
create trigger presence_aggregate_audit after insert or update or delete on cme_private.presence_aggregates for each row execute function cme_private.presence_audit();
create trigger presence_review_audit after insert or update or delete on cme_private.presence_reviews for each row execute function cme_private.presence_audit();
alter table cme_private.presence_schools enable row level security;
alter table cme_private.presence_people enable row level security;
alter table cme_private.presence_affiliations enable row level security;
alter table cme_private.presence_reviews enable row level security;
alter table cme_private.presence_aggregates enable row level security;
alter table cme_private.presence_revision_log enable row level security;
revoke all on cme_private.presence_schools,cme_private.presence_people,cme_private.presence_affiliations,cme_private.presence_reviews,cme_private.presence_aggregates,cme_private.presence_revision_log from public,anon,authenticated;

create view cme_private.presence_evidence as
select a.*,p.full_name,p.school_id,s.name school_name,p.education_status,p.education_source,p.linkedin_url,p.linkedin_checked_at,p.linkedin_note,p.confidence,p.verified_at person_verified_at,
 case when a.temporal_status='current' and (a.verified_at<current_date-365 or (a.class_year is not null and (a.class_year<extract(year from current_date) or (a.class_year=extract(year from current_date) and extract(month from current_date)>7)))) then 'last_seen_unknown' else a.temporal_status end effective_status
from cme_private.presence_affiliations a join cme_private.presence_people p on p.id=a.person_id
join cme_private.presence_schools s on s.id=p.school_id
where a.published and p.confidence in ('high','moderate');

create view cme_private.presence_programs as
with counts as (
 select program_id,count(distinct person_id)::int total_count,
 count(distinct person_id) filter(where effective_status='current')::int current_count,
 count(distinct person_id) filter(where effective_status='historical')::int historical_count,
 count(distinct person_id) filter(where effective_status='last_seen_unknown')::int unknown_count,
 max(verified_at) evidence_verified_at from cme_private.presence_evidence group by program_id
), locations as (
 select distinct on (program_id) program_id,city,state from cme_private.program_source_catalog_v43
 where program_id is not null order by program_id,source_date desc nulls last,source_key
), aggregates as (
 select program_id,count(*) n from cme_private.presence_aggregates where published group by program_id
)
select d.id,d.name,d.specialty,coalesce(r.verified_city,d.city,l.city) city,
 coalesce(r.verified_state,d.state,l.state) state,d.acgme_program_id,d.institution,d.identity_kind,d.active,d.directory_updated_at,
 coalesce(c.total_count,0) documented_count,
 jsonb_build_object('status',case when c.total_count>0 then 'documented' when r.review_status='reviewed' then 'no_public_evidence' else 'unknown' end,
 'total_count',case when c.total_count>0 or r.review_status='reviewed' then coalesce(c.total_count,0) end,
 'current_count',case when c.total_count>0 or r.review_status='reviewed' then coalesce(c.current_count,0) end,
 'historical_count',case when c.total_count>0 or r.review_status='reviewed' then coalesce(c.historical_count,0) end,
 'unknown_count',case when c.total_count>0 or r.review_status='reviewed' then coalesce(c.unknown_count,0) end,
 'latino_status',case when g.n>0 then 'aggregate_evidence' else 'unknown' end,
 'review_status',coalesce(r.review_status,'pending'),'completeness',coalesce(r.completeness,'limited'),
 'verified_at',greatest(c.evidence_verified_at,r.verified_at),'next_review_at',r.next_review_at) presence
from cme_private.program_directory d left join counts c on c.program_id=d.id
left join cme_private.presence_reviews r on r.program_id=d.id left join locations l on l.program_id=d.id
left join aggregates g on g.program_id=d.id;
revoke all on cme_private.presence_evidence,cme_private.presence_programs from public,anon,authenticated;

create function cme_private.presence_filter(p_filters jsonb) returns setof cme_private.presence_programs
language plpgsql stable security definer set search_path='' as $$
declare f jsonb:=coalesce(p_filters,'{}'); k text; minimum integer:=0; yr integer; img numeric; rate numeric;
begin
 if jsonb_typeof(f)<>'object' or octet_length(f::text)>4000 then raise sqlstate '22023' using message='Filtros inválidos'; end if;
 for k in select jsonb_object_keys(f) loop
  if k<>all(array['query','specialty','state','city','kind','time','role','school','education','minimum','evidence','latino','year','img_min','signal','signal_min']) or jsonb_typeof(f->k) not in ('string','number','null') then raise sqlstate '22023' using message='Filtro no admitido'; end if;
 end loop;
 if coalesce(f->>'kind','all') not in ('all','official','community_label') or coalesce(f->>'time','all') not in ('all','current','historical','last_seen_unknown') or coalesce(f->>'role','all') not in ('all','resident','chief','fellow','faculty','leadership','alumnus') or coalesce(f->>'education','all') not in ('all','graduated','attended','medical_education') or coalesce(f->>'evidence','all') not in ('all','documented','unknown','no_public_evidence') or coalesce(f->>'latino','all') not in ('all','aggregate_evidence') or coalesce(f->>'signal','all') not in ('all','gold','silver','none') then raise sqlstate '22023' using message='Opción de filtro inválida'; end if;
 minimum:=coalesce(nullif(f->>'minimum','')::integer,0); yr:=nullif(f->>'year','')::integer;
 img:=nullif(f->>'img_min','')::numeric; rate:=nullif(f->>'signal_min','')::numeric;
 if minimum not between 0 and 1000 or yr not between 1900 and 2100 or img not between 0 and 100 or rate not between 0 and 100 then raise sqlstate '22023' using message='Valor fuera de rango'; end if;
 return query select p.* from cme_private.presence_programs p
 where p.active
 and (coalesce(f->>'query','')='' or concat_ws(' ',p.name,p.specialty,p.city,p.state,p.acgme_program_id,p.institution) ilike '%'||left(f->>'query',160)||'%')
 and (coalesce(f->>'specialty','all') in ('all','') or lower(p.specialty)=lower(f->>'specialty'))
 and (coalesce(f->>'state','')='' or upper(p.state)=upper(f->>'state'))
 and (coalesce(f->>'city','')='' or p.city ilike '%'||left(f->>'city',100)||'%')
 and (coalesce(f->>'kind','all')='all' or p.identity_kind=f->>'kind')
 and (coalesce(f->>'evidence','all')='all' or p.presence->>'status'=f->>'evidence')
 and (coalesce(f->>'latino','all')='all' or p.presence->>'latino_status'=f->>'latino')
 and p.documented_count>=minimum
 and ((coalesce(f->>'time','all')='all' and coalesce(f->>'role','all')='all' and coalesce(f->>'school','all')='all' and coalesce(f->>'education','all')='all' and yr is null)
 or exists(select 1 from cme_private.presence_evidence e where e.program_id=p.id
   and (coalesce(f->>'time','all')='all' or e.effective_status=f->>'time')
   and (coalesce(f->>'role','all')='all' or e.role=f->>'role')
   and (coalesce(f->>'school','all')='all' or e.school_id=f->>'school')
   and (coalesce(f->>'education','all')='all' or e.education_status=f->>'education')
   and (yr is null or e.class_year=yr or (e.start_year is not null and e.end_year is not null and yr between e.start_year and e.end_year))))
 and (img is null or exists(select 1 from cme_private.program_source_catalog_v43 s where s.program_id=p.id and case when s.fields->>'Interview Rate — Non-US IMG' ~ '^[0-9]+(\.[0-9]+)?$' then (s.fields->>'Interview Rate — Non-US IMG')::numeric*100>=img else false end))
 and (rate is null or exists(select 1 from cme_private.program_source_catalog_v43 s where s.program_id=p.id and case when s.fields->>(case f->>'signal' when 'gold' then 'Interview Rate — Gold Signal' when 'silver' then 'Interview Rate — Silver Signal' when 'none' then 'Interview Rate — No Signal' else 'Interview Rate (Average Likelihood)' end) ~ '^[0-9]+(\.[0-9]+)?$' then (s.fields->>(case f->>'signal' when 'gold' then 'Interview Rate — Gold Signal' when 'silver' then 'Interview Rate — Silver Signal' when 'none' then 'Interview Rate — No Signal' else 'Interview Rate (Average Likelihood)' end))::numeric*100>=rate else false end));
end $$;
revoke all on function cme_private.presence_filter(jsonb) from public,anon,authenticated;

create function cme_private.presence_directory(p_filters jsonb,p_offset integer,p_limit integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if p_offset is null or p_offset not between 0 and 50000 or p_limit is null or p_limit not between 1 and 40 then raise sqlstate '22023' using message='Paginación inválida'; end if;
 with matches as materialized(select * from cme_private.presence_filter(p_filters)), page as (
 select * from matches order by documented_count desc,name,id limit p_limit offset p_offset)
 select jsonb_build_object('programs',coalesce((select jsonb_agg(to_jsonb(page) order by documented_count desc,name,id) from page),'[]'),
 'total',(select count(*) from matches),'has_more',(select count(*) from matches)>p_offset+p_limit) into result;
 return result;
end $$;
create function cme_private.presence_profiles(p_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if p_ids is null or cardinality(p_ids)>50 then raise sqlstate '22023' using message='Máximo 50 programas'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'presence',p.presence,'review',(select to_jsonb(r) from cme_private.presence_reviews r where r.program_id=p.id),
 'people',coalesce((select jsonb_agg(to_jsonb(e) order by e.effective_status,e.full_name,e.id) from cme_private.presence_evidence e where e.program_id=p.id),'[]'),
 'aggregates',coalesce((select jsonb_agg(to_jsonb(a) order by a.verified_at desc,a.id) from cme_private.presence_aggregates a where a.program_id=p.id and a.published),'[]')))
 from cme_private.presence_programs p where p.id=any(p_ids)),'[]');
end $$;
create function cme_private.presence_overview(p_filters jsonb) returns jsonb
language sql stable security definer set search_path='' as $$
 with m as materialized(select * from cme_private.presence_filter(p_filters)), e as materialized(select e.* from cme_private.presence_evidence e join m on m.id=e.program_id)
 select jsonb_build_object(
 'coverage',jsonb_build_object('catalog',(select count(*) from cme_private.presence_programs where active),'reviewed',(select count(*) from cme_private.presence_reviews),'complete_reviews',(select count(*) from cme_private.presence_reviews where review_status='reviewed')),
 'totals',jsonb_build_object('programs',(select count(*) from m where documented_count>0),'current',(select count(*) from m where (presence->>'current_count')::int>0),'historical',(select count(*) from m where (presence->>'historical_count')::int>0),'people',(select count(distinct person_id) from e),'latino',(select count(*) from m where presence->>'latino_status'='aggregate_evidence')),
 'states',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select coalesce(state,'Sin estado verificado') label,count(*) count from m where documented_count>0 group by state)x),'[]'),
 'specialties',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select specialty label,count(*) count from m where documented_count>0 group by specialty)x),'[]'),
 'schools',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select school_id id,school_name label,count(distinct person_id) count from e group by school_id,school_name)x),'[]'),
 'top_programs',coalesce((select jsonb_agg(x) from (select id,name,documented_count count from m where documented_count>0 order by documented_count desc,name,id limit 10)x),'[]'),
 'school_options',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'aliases',aliases) order by name) from cme_private.presence_schools)
 );
$$;
revoke all on function cme_private.presence_directory(jsonb,integer,integer),cme_private.presence_profiles(uuid[]),cme_private.presence_overview(jsonb) from public;
grant usage on schema cme_private to anon,authenticated;
grant execute on function cme_private.presence_directory(jsonb,integer,integer),cme_private.presence_profiles(uuid[]),cme_private.presence_overview(jsonb) to anon,authenticated;
create function public.presence_directory_v53(p_filters jsonb default '{}',p_offset integer default 0,p_limit integer default 40) returns jsonb language sql stable security invoker set search_path='' as $$ select cme_private.presence_directory(p_filters,p_offset,p_limit) $$;
create function public.presence_profiles_v53(p_ids uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$ select cme_private.presence_profiles(p_ids) $$;
create function public.presence_overview_v53(p_filters jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$ select cme_private.presence_overview(p_filters) $$;
revoke all on function public.presence_directory_v53(jsonb,integer,integer),public.presence_profiles_v53(uuid[]),public.presence_overview_v53(jsonb) from public;
grant execute on function public.presence_directory_v53(jsonb,integer,integer),public.presence_profiles_v53(uuid[]),public.presence_overview_v53(jsonb) to anon,authenticated,service_role;
grant execute on function cme_private.presence_directory(jsonb,integer,integer),cme_private.presence_profiles(uuid[]),cme_private.presence_overview(jsonb) to service_role;
notify pgrst, 'reload schema';
