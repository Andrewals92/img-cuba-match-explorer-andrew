begin;
do $$declare u uuid;c uuid;r jsonb;i integer;begin
 assert not exists(select 1 from public.applicant_cycles where match_cycle=2040),'Reserved fixture cycle is already in use';
 for i in 1..12 loop
  u:=gen_random_uuid();insert into auth.users(id,email) values(u,'v50-summary-'||u||'@example.invalid');
  perform set_config('request.jwt.claim.sub',u::text,true);
  insert into public.applicant_cycles(user_id,anon_id,match_cycle,specialty,step2_ck,consent_public,programs_applied,interview_invites)
  values(u,'V50-summary-'||u,2040,'V50 Summary QA',case when i=1 then 219 when i<=3 then 225 when i<=6 then 235 else 246 end,true,10,2) returning id into c;
  if i=4 then
   r:=public.community_overview(2040);
   assert r->>'applicants' is null and r->>'applications' is null and r->>'interviews' is null and r->>'matches' is null,'Small totals exposed';
   assert r->'step_bins'='[]'::jsonb,'Small histogram exposed';
  end if;
 end loop;
 r:=public.community_overview(2040);
 assert (r->>'applicants')::integer=12;
 assert r->>'matches' is null,'Future cycle interpreted as zero Matches';
 assert jsonb_array_length(r->'step_bins')=2,'Safe broad bins unavailable';
 assert not exists(select 1 from jsonb_array_elements(r->'step_bins') b where (b->>'count')::integer<5),'Small bin exposed';
 assert (select sum((b->>'count')::integer)=12 from jsonb_array_elements(r->'step_bins') b),'Histogram changed total';
 r:=public.community_overview(2026);
 assert (r->>'applicants')::integer=36 and (r->>'matches')::integer=14;
 assert not exists(select 1 from jsonb_array_elements(r->'step_bins') b where (b->>'count')::integer<5);
 assert (select count(*)=36 from public.applicant_cycles where source='import:CubaMatch_2026');
 assert (select count(*)=338 from public.program_reports where source='import:CubaMatch_2026' and interview);
 assert (select count(*)=14 from public.program_reports where source='import:CubaMatch_2026' and matched);
end $$;
rollback;
select 'PASS: small summary cells suppressed, adjacent Step 2 ranges safely grouped, incomplete-cycle outcomes unknown, 36/338/14 unchanged' result;
