// Parse only official public catalogue pages. A failed/partial page is never a snapshot.
export const ACGME_URL='https://apps.acgme.org/ads/Public/Programs/Search';
export const AAMC_URL='https://systems.aamc.org/eras/erasstats/par/index.cfm';
export function decode(s=''){return s.replace(/&#(x[0-9a-f]+|\d+);/gi,(_,n)=>String.fromCodePoint(n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n))).replace(/&nbsp;/gi,' ').replace(/&amp;/gi,'&').replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/&lt;/gi,'<').replace(/&gt;/gi,'>').replace(/\s+/g,' ').trim();}
export const strip=s=>decode(String(s||'').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<[^>]+>/g,' '));
const attr=(s,k)=>decode(s.match(new RegExp('\\b'+k+'=(["\'])([\\s\\S]*?)\\1','i'))?.[2]||'');
export function parseAcgmeSpecialties(html){
 const block=html.match(/<select\b[^>]*id=["']specialtyFilter["'][^>]*>([\s\S]*?)<\/select>/i)?.[1];
 if(!block)throw Error('ACGME specialty selector missing');
 const rows=[...block.matchAll(/<option\b([^>]*)>([\s\S]*?)<\/option>/gi)].map(m=>({specialty_id:attr(m[1],'value'),name:strip(m[2])})).filter(x=>/^\d+$/.test(x.specialty_id)&&x.name);
 if(rows.length<30)throw Error('Incomplete ACGME specialty catalogue');return rows;
}
export function parseAcgmePrograms(html,specialty){
 if(!/id=["']statusFilter["']/.test(html)||!/listview/.test(html))throw Error('ACGME program table missing');
 const rows=[];
 for(const m of html.matchAll(/<tr\b([^>]*)>([\s\S]*?)<\/tr>/gi)){
  const cells=[...m[2].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>strip(x[1]));
  const i=cells.findIndex(c=>/^(?:\d{10}|M\d{9})$/.test(c));if(i<0)continue;
  const flags=attr(m[1],'data-status-matches');let status='Listed; accreditation status unverified';
  try{const f=JSON.parse(flags);status=f['5']?'Withdrawn':f['3']?'Pre-Accreditation':f['4']?'Unaccredited Combined':f['1']?'Accredited':status;}catch{}
  for(const icon of m[2].matchAll(/<span\b([^>]*)>/gi)){if(!/\bhidden\b/.test(attr(icon[1],'class'))&&attr(icon[1],'data-bs-content')==='Future Accredited')status='Future Accredited';}
  const source_url='https://apps.acgme.org/ads/Public/Programs/Detail?orgCode='+cells[i];
  rows.push({acgme_program_id:cells[i],name:cells[i+2],specialty:cells[i+1]||specialty,city:cells[i+3]||null,state:null,status,source_url,external_id:attr(m[1],'data-item-key')||null});
 }
 if(!rows.length&&!/No Programs found for the input and\/or selected search criteria/i.test(html))throw Error('ACGME response has no validated rows or explicit empty result');
 if(new Set(rows.map(x=>x.acgme_program_id)).size!==rows.length||rows.some(x=>!x.name))throw Error('ACGME duplicate or malformed program identity');
 return rows;
}
export function parseAamcIndex(html){
 const season=Number(strip(html).match(/ERAS\s+(20\d{2})\s+Participating Specialties/i)?.[1]);
 if(!season)throw Error('AAMC ERAS season missing');
 const map=new Map();
 for(const m of html.matchAll(/<a\b[^>]*href=["']([^"']*display\.cfm\?[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)){
  const u=new URL(decode(m[1]),AAMC_URL),id=u.searchParams.get('SPEC_CD')||u.searchParams.get('spec_cd');
  if(u.hostname==='systems.aamc.org'&&/^[A-Z0-9,]+$/.test(id||''))map.set(id,{specialty_id:id,name:strip(m[2]),source_url:u.href});
 }
 if(map.size<30)throw Error('Incomplete AAMC specialty catalogue');return {season,specialties:[...map.values()]};
}
const states='Alabama:AL|Alaska:AK|Arizona:AZ|Arkansas:AR|California:CA|Colorado:CO|Connecticut:CT|Delaware:DE|District of Columbia:DC|Florida:FL|Georgia:GA|Hawaii:HI|Idaho:ID|Illinois:IL|Indiana:IN|Iowa:IA|Kansas:KS|Kentucky:KY|Louisiana:LA|Maine:ME|Maryland:MD|Massachusetts:MA|Michigan:MI|Minnesota:MN|Mississippi:MS|Missouri:MO|Montana:MT|Nebraska:NE|Nevada:NV|New Hampshire:NH|New Jersey:NJ|New Mexico:NM|New York:NY|North Carolina:NC|North Dakota:ND|Ohio:OH|Oklahoma:OK|Oregon:OR|Pennsylvania:PA|Puerto Rico:PR|Rhode Island:RI|South Carolina:SC|South Dakota:SD|Tennessee:TN|Texas:TX|Utah:UT|Vermont:VT|Virginia:VA|Washington:WA|West Virginia:WV|Wisconsin:WI|Wyoming:WY|Guam:GU|Virgin Islands:VI';
const stateCodes=new Map(states.split('|').map(s=>s.split(':').map((v,i)=>i?v:v.toLowerCase())));
export function parseAamcPrograms(html,specialty,season){
 const found=Number(strip(html).match(/ERAS\s+(20\d{2})\s+Participating Specialties/i)?.[1]);if(found!==season)throw Error('AAMC season mismatch');
 const totalMatch=strip(html.match(/<tfoot\b[^>]*>([\s\S]*?)<\/tfoot>/i)?.[1]||'').match(/\b(\d+) Programs\b/);
 if(!totalMatch){if(/No programs were found/i.test(strip(html)))return [];throw Error('AAMC program count footer missing');}
 const rows=[];
 for(const m of html.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)){
  const raw=[...m[1].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>x[1]),cells=raw.map(strip);
  if(cells.length!==6)continue;
  const [state,city,,,id,status]=cells;const name=strip(raw[3].replace(/<sup\b[^>]*>[\s\S]*?<\/sup>/gi,''));const is_new=/New\s+Program!/i.test(cells[3]);
  if(!/^[A-Za-z0-9-]{5,20}$/.test(id))continue;
  if(!['Participating','Not Participating','Unregistered','No Longer Accepting Applications'].includes(status))throw Error('Unknown AAMC participation status: '+status);
  rows.push({acgme_program_id:id,name,specialty:specialty.name,city,state:stateCodes.get(state.toLowerCase())||(/^[A-Z]{2}$/.test(state)?state:null),status,is_new,source_url:specialty.source_url,external_id:id});
 }
 if(rows.length!==Number(totalMatch[1]))throw Error('AAMC count mismatch: '+rows.length+'/'+totalMatch[1]);
 const grouped=new Map();
 for(const row of rows){const old=grouped.get(row.acgme_program_id);if(old){old.tracks.push({name:row.name,status:row.status,is_new:row.is_new});if(old.status!==row.status)old.status='Mixed participation';}else grouped.set(row.acgme_program_id,{...row,tracks:[{name:row.name,status:row.status,is_new:row.is_new}]});}
 return [...grouped.values()];
}
export function selectTargets(states,limit=4){
 return states.slice().sort((a,b)=>{
  const priority=s=>s.name.toLowerCase()==='internal medicine'&&Date.now()-new Date(s.last_attempt_at||0).getTime()>3600000?-1:0;
  return priority(a)-priority(b)||new Date(a.last_attempt_at||0)-new Date(b.last_attempt_at||0);
 }).slice(0,limit);
}
