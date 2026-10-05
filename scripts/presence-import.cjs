'use strict';
// Produce reviewable SQL. This command never connects to or mutates a database.
const fs=require('node:fs');
const keys={schools:'id name aliases',people:'id full_name school_id education_status education_source linkedin_url linkedin_checked_at linkedin_note confidence verified_at',affiliations:'id person_id acgme_program_id role temporal_status period_key pgy class_year start_year end_year source verified_at published',reviews:'acgme_program_id review_status verified_at next_review_at completeness source_url notes verified_state verified_city',aggregates:'id acgme_program_id percentage period_label scope source verified_at published'};
const sourceKeys='name url type verified_at note'.split(' ');
function only(obj,allowed){if(!obj||typeof obj!=='object'||Array.isArray(obj)||Object.keys(obj).some(k=>!allowed.includes(k)))throw Error('Unsupported fields: professional evidence only');}
function https(value){const u=new URL(value);if(u.protocol!=='https:'||u.username||u.password)throw Error('HTTPS source required');}
function validate(d){
 only(d,['version','verified_at','scope',...Object.keys(keys)]);
 for(const [table,fields] of Object.entries(keys)){
  if(!Array.isArray(d[table]))throw Error('Missing collection '+table);
  const ids=new Set();
  for(const row of d[table]){
   only(row,fields.split(' '));const id=row.id||row.acgme_program_id;if(!id||ids.has(id))throw Error('Duplicate identity in '+table);ids.add(id);
   if(row.verified_at&&!/^\d{4}-\d{2}-\d{2}$/.test(row.verified_at))throw Error('Verification date required');
   if(row.acgme_program_id&&!/^\d{10}$/.test(row.acgme_program_id))throw Error('Official program identifier required');
   for(const key of ['source','education_source'])if(row[key]){only(row[key],sourceKeys);https(row[key].url);if(!row[key].name||!row[key].note||!row[key].verified_at)throw Error('Incomplete evidence');}
   if(row.source_url)https(row.source_url);
   if(row.linkedin_url&&(!/^https:\/\/(?:[a-z]+\.)?linkedin\.com\/in\/[^/?#]+\/?$/.test(row.linkedin_url)||!row.linkedin_note||!row.linkedin_checked_at))throw Error('LinkedIn identity check required');
  }
 }
 const schools=new Set(d.schools.map(x=>x.id)),people=new Set(d.people.map(x=>x.id));
 for(const p of d.people)if(!schools.has(p.school_id)||!p.education_source||!p.verified_at)throw Error('Education evidence required');
 for(const a of d.affiliations)if(!people.has(a.person_id)||!a.source||!a.verified_at)throw Error('Affiliation evidence required');
 return d;
}
function sql(d){
 validate(d);const literal=JSON.stringify(d);if(literal.includes('$presence_import$'))throw Error('Invalid delimiter');
 return `begin;
create temporary table presence_import_payload(data jsonb) on commit drop;
insert into presence_import_payload values($presence_import$${literal}$presence_import$::jsonb);
do $$ declare code text; n integer; begin
 for code in select distinct x->>'acgme_program_id' from presence_import_payload t cross join lateral jsonb_array_elements((t.data->'affiliations')||(t.data->'reviews')||(t.data->'aggregates')) x loop
 select count(*) into n from public.programs where acgme_program_id=code;
 if n<>1 then raise exception 'Program identity requires manual resolution: %',code; end if;
 end loop; end $$;
insert into cme_private.presence_schools(id,name,aliases)
select x.id,x.name,x.aliases from presence_import_payload t cross join lateral jsonb_to_recordset(t.data->'schools') x(id text,name text,aliases text[])
on conflict(id) do update set name=excluded.name,aliases=excluded.aliases;
insert into cme_private.presence_people(id,full_name,school_id,education_status,education_source,linkedin_url,linkedin_checked_at,linkedin_note,confidence,verified_at)
select x.* from presence_import_payload t cross join lateral jsonb_to_recordset(t.data->'people') x(id text,full_name text,school_id text,education_status text,education_source jsonb,linkedin_url text,linkedin_checked_at date,linkedin_note text,confidence text,verified_at date)
on conflict(id) do update set full_name=excluded.full_name,school_id=excluded.school_id,education_status=excluded.education_status,education_source=excluded.education_source,
linkedin_url=excluded.linkedin_url,linkedin_checked_at=excluded.linkedin_checked_at,linkedin_note=excluded.linkedin_note,confidence=excluded.confidence,verified_at=excluded.verified_at,updated_at=now()
where excluded.verified_at>=presence_people.verified_at and array_position(array['unverified','moderate','high'],excluded.confidence)>=array_position(array['unverified','moderate','high'],presence_people.confidence);
insert into cme_private.presence_affiliations(id,person_id,program_id,role,temporal_status,period_key,pgy,class_year,start_year,end_year,source,verified_at,published)
select x.id,x.person_id,p.id,x.role,x.temporal_status,x.period_key,x.pgy,x.class_year,x.start_year,x.end_year,x.source,x.verified_at,x.published
from presence_import_payload t cross join lateral jsonb_to_recordset(t.data->'affiliations') x(id text,person_id text,acgme_program_id text,role text,temporal_status text,period_key text,pgy int,class_year int,start_year int,end_year int,source jsonb,verified_at date,published bool)
join public.programs p on p.acgme_program_id=x.acgme_program_id
on conflict(id) do update set temporal_status=excluded.temporal_status,pgy=excluded.pgy,class_year=excluded.class_year,start_year=excluded.start_year,end_year=excluded.end_year,source=excluded.source,verified_at=excluded.verified_at,published=excluded.published
where excluded.verified_at>=presence_affiliations.verified_at;
insert into cme_private.presence_reviews(program_id,review_status,verified_at,next_review_at,completeness,source_url,notes,verified_state,verified_city)
select p.id,x.review_status,x.verified_at,x.next_review_at,x.completeness,x.source_url,x.notes,x.verified_state,x.verified_city
from presence_import_payload t cross join lateral jsonb_to_recordset(t.data->'reviews') x(acgme_program_id text,review_status text,verified_at date,next_review_at date,completeness text,source_url text,notes text,verified_state text,verified_city text)
join public.programs p on p.acgme_program_id=x.acgme_program_id
on conflict(program_id) do update set review_status=excluded.review_status,verified_at=excluded.verified_at,next_review_at=excluded.next_review_at,completeness=excluded.completeness,source_url=excluded.source_url,notes=excluded.notes,verified_state=excluded.verified_state,verified_city=excluded.verified_city
where excluded.verified_at>=presence_reviews.verified_at;
insert into cme_private.presence_aggregates(id,program_id,percentage,period_label,scope,source,verified_at,published)
select x.id,p.id,x.percentage,x.period_label,x.scope,x.source,x.verified_at,x.published
from presence_import_payload t cross join lateral jsonb_to_recordset(t.data->'aggregates') x(id text,acgme_program_id text,percentage numeric,period_label text,scope text,source jsonb,verified_at date,published bool)
join public.programs p on p.acgme_program_id=x.acgme_program_id
on conflict(id) do update set percentage=excluded.percentage,period_label=excluded.period_label,scope=excluded.scope,source=excluded.source,verified_at=excluded.verified_at,published=excluded.published
where excluded.verified_at>=presence_aggregates.verified_at;
commit;`;
}
module.exports={validate,sql};
if(require.main===module){try{process.stdout.write(sql(JSON.parse(fs.readFileSync(process.argv[2],'utf8')))+'\n');}catch(e){console.error(e.message);process.exitCode=1;}}
