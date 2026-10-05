-- Run as maintenance owner; every fixture and mutation rolls back.
begin;
do $$
declare a uuid; b uuid; j jsonb; n int;
begin
 select id into a from public.programs where acgme_program_id='1401100957';
 select id into b from public.programs where acgme_program_id='1401112101';
 if (select count(*) from cme_private.presence_people)<>30 then raise exception 'Expected initial 30 people'; end if;
 j:=public.presence_directory_v53('{"specialty":"Internal Medicine","state":"FL","time":"current","school":"la-habana"}',0,40);
 if not exists(select 1 from jsonb_array_elements(j->'programs') x where x->>'id'=a::text) then raise exception 'Combination lost Larkin';end if;
 -- Two different people in the same program must not satisfy a single-person conjunction.
 j:=public.presence_directory_v53('{"query":"Mount Sinai","role":"faculty","school":"universidad-habana"}',0,40);
 if (j->>'total')::int<>0 then raise exception 'Role/school cross-person false positive';end if;
 j:=public.presence_profiles_v53(array[a]);
 if jsonb_array_length(j->0->'people')<>22 then raise exception 'Expected all 22 documented residents';end if;
 -- School evidence suffices. There is deliberately no nationality/ethnicity column.
 if exists(select 1 from information_schema.columns where table_schema='cme_private' and table_name='presence_people' and column_name ~ '(ethnic|national|origin)') then raise exception 'Sensitive person classification';end if;
 insert into cme_private.presence_affiliations(id,person_id,program_id,role,period_key,temporal_status,source,verified_at,published)
 select 'test-historical',person_id,a,'alumnus','test','historical',source,current_date,true from cme_private.presence_affiliations where program_id=a limit 1;
 j:=public.presence_profiles_v53(array[a]);
 if (j->0->'presence'->>'total_count')::int<>22 or (j->0->'presence'->>'historical_count')::int<>1 then raise exception 'Duplicate total / historical count';end if;
 update cme_private.presence_people set confidence='unverified' where id='yanisley-menendez';
 j:=public.presence_profiles_v53(array[a]);
 if exists(select 1 from jsonb_array_elements(j->0->'people') x where x->>'person_id'='yanisley-menendez') then raise exception 'Unverified person leaked';end if;
 update cme_private.presence_affiliations set verified_at=current_date-400 where person_id='elvis-henriquez';
 if not exists(select 1 from cme_private.presence_evidence where person_id='elvis-henriquez' and effective_status='last_seen_unknown') then raise exception 'Stale roster remains current';end if;
 select presence into j from cme_private.presence_programs where presence->>'review_status'='pending' limit 1;
 if j->>'total_count' is not null or j->>'status'<>'unknown' then raise exception 'Unknown rendered as zero';end if;
 begin perform public.presence_directory_v53('{"nationality":"Cuban"}',0,40);raise exception 'Unknown filter accepted';exception when sqlstate '22023' then null;end;
 begin perform public.presence_directory_v53('{}',0,100);raise exception 'Unbounded pagination';exception when sqlstate '22023' then null;end;
 begin perform public.presence_directory_v53('{"minimum":-1}',0,40);raise exception 'Invalid count accepted';exception when sqlstate '22023' then null;end;
 if has_table_privilege('anon','cme_private.presence_people','select') or has_table_privilege('authenticated','cme_private.presence_affiliations','select') then raise exception 'Raw tables exposed';end if;
 if not has_function_privilege('anon','public.presence_profiles_v53(uuid[])','execute') then raise exception 'Wrapper unavailable';end if;
 if exists(select 1 from cme_private.presence_revision_log where record_key='test-historical') is not true then raise exception 'History audit missing';end if;
end $$;
rollback;
