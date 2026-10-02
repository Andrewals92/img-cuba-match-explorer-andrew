-- Read-only acceptance checks; no historical import or applicant records modified.
begin;
do $$
declare page jsonb; item jsonb; resource jsonb; seen uuid[]:='{}'; n integer;
begin
 assert not has_table_privilege('anon','cme_private.program_source_catalog_v43','SELECT');
 assert not has_table_privilege('authenticated','cme_private.program_source_catalog_v43','UPDATE');
 assert (select count(*)=821 from cme_private.program_source_catalog_v43);
 assert (select count(*)=702 from cme_private.program_source_catalog_v43 where source='Residency Explorer');
 assert (select count(*)=119 from cme_private.program_source_catalog_v43 where source='Match A Resident');
 assert not exists(select 1 from cme_private.program_source_catalog_v43 where program_id is null or website_url is null);
 assert (select count(distinct program_id)=702 from cme_private.program_source_catalog_v43);
 assert not exists(select 1 from cme_private.program_source_catalog_v43 c join public.programs p on p.id=c.program_id where c.acgme_program_id is distinct from p.acgme_program_id);
 assert not exists(select 1 from cme_private.program_source_catalog_v43 c cross join lateral jsonb_object_keys(c.fields) k where k ~* 'My Interview|compatibilidad|orden MAR|YOUR CONNECTIONS|similar profile');
 for n in 0..23 loop
  page:=public.program_source_directory_v43('',n*30);
  for item in select * from jsonb_array_elements(page->'programs') loop
   assert not (item->>'program_id')::uuid=any(seen),'Duplicate card';
   seen:=array_append(seen,(item->>'program_id')::uuid);
   assert item->>'acgme_program_id' is not null;
   assert item->>'state' ~ '^[A-Z]{2}$','Missing state in program card';
   for resource in select * from jsonb_array_elements(item->'resources') loop
    assert not resource ? 'source' and not resource ? 'source_key' and not resource ? 'program_url','Provider provenance in public response';
    assert resource->>'website_url' ~ '^https?://';
   end loop;
  end loop;
  if n=23 then assert (page->>'has_more')::boolean=false;end if;
 end loop;
 assert cardinality(seen)=702,'Pagination lost a program';
 assert (select count(*)=36 from public.applicant_cycles where source='import:CubaMatch_2026');
 assert (select count(*)=338 from public.program_reports where source='import:CubaMatch_2026' and interview);
 assert (select count(*)=14 from public.program_reports where source='import:CubaMatch_2026' and matched);
 assert not exists(select 1 from public.program_reports r where source='import:CubaMatch_2026' group by to_jsonb(r)-'id'-'created_at'-'updated_at' having count(*)>1);
end $$;
set local role anon;
do $$declare result jsonb;begin
 assert not has_schema_privilege('anon','cme_private','USAGE');
 result:=public.program_source_directory_v43('1400500016',0);
 assert jsonb_array_length(result->'programs')=1;
 assert jsonb_array_length(result#>'{programs,0,resources}')>=1;
 begin perform public.program_resources_v43(array[]::uuid[]);raise exception 'Accepted empty selection';exception when raise_exception then assert sqlerrm='Select 1 to 50 programs';end;
end $$;
reset role;
set local role authenticated;
do $$begin
 assert not has_schema_privilege('authenticated','cme_private','USAGE');
 assert jsonb_array_length(public.program_source_directory_v43('McLaren',0)->'programs')>=6;
end $$;
rollback;
select 'PASS 19 resolved; 821 records / 702 unique programs and websites; pagination; no provider fields or personal predictions; private ACL; 36/338/14; no duplicate historical payloads' result;
