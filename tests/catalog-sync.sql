begin;
do $$
declare rows jsonb;after_rows jsonb;n integer;
begin
 insert into public.catalog_sync_state(source,season,specialty_id,name,source_url) values('aamc',2099,'TEST','Catalogue regression test','https://systems.aamc.org/eras/erasstats/par/display.cfm?SPEC_CD=TEST');
 select jsonb_agg(jsonb_build_object('acgme_program_id','TEST000'||i,'name','Regression test '||i,'specialty','Catalogue regression test','status','Participating','source_url','https://systems.aamc.org/eras/erasstats/par/display.cfm?SPEC_CD=TEST','tracks',jsonb_build_array(jsonb_build_object('name','Track','status','Participating')))) into rows from generate_series(1,4)i;
 perform public.catalog_apply_snapshot('aamc',2099,'TEST',rows);
 if exists(select 1 from public.program_change_events where source='aamc' and source_season=2099) then raise exception 'Baseline emitted false new-program events';end if;
 begin
  perform public.catalog_apply_snapshot('aamc',2099,'TEST',jsonb_build_array(rows->0));
  raise exception 'Truncated snapshot was accepted';
 exception when others then
  if sqlerrm not like 'Catalogue shrank%' then raise;end if;
 end;
 if (select count(*) from public.catalog_programs where source='aamc' and season=2099 and present)<>4 then raise exception 'Failed snapshot changed data';end if;
 after_rows:=jsonb_set(rows,'{0,status}','"Not Participating"');
 perform public.catalog_apply_snapshot('aamc',2099,'TEST',after_rows);
 perform public.catalog_apply_snapshot('aamc',2099,'TEST',after_rows);
 select count(*) into n from public.program_change_events where source='aamc' and source_season=2099;
 if n<>1 then raise exception 'Status event not idempotent: %',n;end if;
 perform public.catalog_apply_snapshot('aamc',2099,'TEST',after_rows-3);
 if not exists(select 1 from public.catalog_programs where source='aamc' and season=2099 and acgme_program_id='TEST0004' and not present and status='Participating') then raise exception 'Missing listing wrongly became not participating';end if;
 if has_function_privilege('anon','public.catalog_apply_snapshot(text,integer,text,jsonb)','execute') or has_function_privilege('authenticated','public.catalog_claim(text)','execute') or has_table_privilege('anon','public.catalog_programs','select') then raise exception 'Public catalogue writer or raw access exposed';end if;
end $$;
rollback;
