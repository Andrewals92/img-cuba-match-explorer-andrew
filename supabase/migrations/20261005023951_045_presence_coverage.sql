-- Research coverage refers to the official catalog, not unlinked community labels.
create or replace function cme_private.presence_overview(p_filters jsonb) returns jsonb
language sql stable security definer set search_path='' as $$
 with m as materialized(select * from cme_private.presence_filter(p_filters)), e as materialized(select e.* from cme_private.presence_evidence e join m on m.id=e.program_id)
 select jsonb_build_object(
 'coverage',jsonb_build_object('catalog',(select count(*) from cme_private.presence_programs where active and identity_kind='official'),'community_labels',(select count(*) from cme_private.presence_programs where active and identity_kind='community_label'),'reviewed',(select count(*) from cme_private.presence_reviews),'complete_reviews',(select count(*) from cme_private.presence_reviews where review_status='reviewed')),
 'totals',jsonb_build_object('programs',(select count(*) from m where documented_count>0),'current',(select count(*) from m where (presence->>'current_count')::int>0),'historical',(select count(*) from m where (presence->>'historical_count')::int>0),'people',(select count(distinct person_id) from e),'latino',(select count(*) from m where presence->>'latino_status'='aggregate_evidence')),
 'states',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select coalesce(state,'Sin estado verificado') label,count(*) count from m where documented_count>0 group by state)x),'[]'),
 'specialties',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select specialty label,count(*) count from m where documented_count>0 group by specialty)x),'[]'),
 'schools',coalesce((select jsonb_agg(x order by x.count desc,x.label) from (select school_id id,school_name label,count(distinct person_id) count from e group by school_id,school_name)x),'[]'),
 'top_programs',coalesce((select jsonb_agg(x) from (select id,name,documented_count count from m where documented_count>0 order by documented_count desc,name,id limit 10)x),'[]'),
 'school_options',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'aliases',aliases) order by name) from cme_private.presence_schools)
 );
$$;

notify pgrst, 'reload schema';
