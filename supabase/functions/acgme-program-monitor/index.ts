import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import {ACGME_URL,AAMC_URL,parseAcgmeSpecialties,parseAcgmePrograms,parseAamcIndex,parseAamcPrograms,selectTargets} from './catalog-parser.mjs';
const PROJECT_URL=Deno.env.get('SUPABASE_URL')!;
const SECRET_KEY=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const UA='CubaMatchExplorer/2.0 (+https://cubamatchexplorer.org)';
async function db(path:string,init:RequestInit={}){
 const r=await fetch(PROJECT_URL+'/rest/v1/'+path,{...init,signal:AbortSignal.timeout(45000),headers:{apikey:SECRET_KEY,'Content-Type':'application/json',...(init.headers||{})}});
 const text=await r.text();if(!r.ok)throw Error(`Database ${r.status}: ${text.slice(0,400)}`);return text?JSON.parse(text):null;
}
async function upsert(table:string,rows:any[],conflict:string){for(let i=0;i<rows.length;i+=100)await db(table+'?on_conflict='+conflict,{method:'POST',headers:{Prefer:'resolution=merge-duplicates'},body:JSON.stringify(rows.slice(i,i+100))});}
async function html(url:string,init:RequestInit={}){
 const r=await fetch(url,{...init,signal:AbortSignal.timeout(20000),headers:{'User-Agent':UA,Accept:'text/html,application/xhtml+xml',...(init.headers||{})}});
 if(!r.ok)throw Error(`Official source returned HTTP ${r.status}`);const bytes=await r.arrayBuffer();if(bytes.byteLength>12000000)throw Error('Official response exceeds limit');
 const preview=new TextDecoder().decode(bytes.slice(0,12000));const charset=(r.headers.get('content-type')||'').match(/charset=([\w-]+)/i)?.[1]||preview.match(/charset=([\w-]+)/i)?.[1]||'utf-8';
 const text=new TextDecoder(charset).decode(bytes);return {text,headers:r.headers};
}
async function discover(source:string){
 const now=new Date().toISOString();await db('catalog_sources?source=eq.'+source,{method:'PATCH',body:JSON.stringify({last_attempt_at:now})});
 const page=await html(source==='acgme'?ACGME_URL:AAMC_URL);
 if(source==='aamc'){const parsed=parseAamcIndex(page.text);return {...parsed,session:null};}
 const token=page.text.match(/name=["']__RequestVerificationToken["'][^>]*value=["']([^"']+)/i)?.[1];
 if(!token)throw Error('ACGME verification token missing');
 const cookies=page.headers.getSetCookie().map(x=>x.split(';')[0]).join('; ');
 return {season:0,specialties:parseAcgmeSpecialties(page.text).map((s:any)=>({...s,source_url:ACGME_URL})),session:{token,cookies}};
}
async function fetchPrograms(source:string,s:any,session:any){
 if(source==='aamc')return parseAamcPrograms((await html(s.source_url)).text,s,s.season);
 const params=new URLSearchParams({__RequestVerificationToken:session.token,accreditationTypeId:'2',specialtyId:s.specialty_id,specialtyCategoryTypeId:'',stateId:'',numCode:'',city:'','g-recaptcha-response':''});
 const page=await html(ACGME_URL,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',Cookie:session.cookies,Referer:ACGME_URL},body:params.toString()});
 return parseAcgmePrograms(page.text,s.name);
}
Deno.serve(async(req:Request)=>{
 if(req.method==='GET'&&new URL(req.url).pathname.endsWith('/health'))return Response.json({ok:true,service:'ACGME + AAMC ERAS catalogue monitor',version:9});
 if(req.method!=='POST'||!req.headers.get('x-monitor-token'))return Response.json({error:'Unauthorized'},{status:401});
 let lease:string|null=null,runId:string|null=null;
 try{
  lease=await db('rpc/catalog_claim',{method:'POST',body:JSON.stringify({p_token:req.headers.get('x-monitor-token')})});
  if(!lease)return Response.json({error:'Unauthorized or monitor already running'},{status:409});
  const body=await req.json().catch(()=>({}));const limit=Math.min(12,Math.max(1,Number(body.limit)||4));
  const sources=body.source&&['acgme','aamc'].includes(body.source)?[body.source]:['acgme','aamc'];
  const runs=await db('acgme_sync_runs',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({status:'running',details:{mode:'dual_catalog',sources}})});runId=runs[0].id;
  const started=Date.now(),results:any[]=[],errors:any[]=[];
  for(const source of sources){
   try{
    const discovered=await discover(source),season=discovered.season;
    await db('catalog_sources?source=eq.'+source,{method:'PATCH',body:JSON.stringify({season,last_success_at:new Date().toISOString(),last_error:null})});
    await upsert('catalog_sync_state',discovered.specialties.map((s:any)=>({...s,source,season,active:true})),'source,season,specialty_id');
    if(source==='acgme')await upsert('acgme_specialties',discovered.specialties.map((s:any)=>({acgme_specialty_id:s.specialty_id,name:s.name,active:true})),'acgme_specialty_id');
    const states=await db(`catalog_sync_state?source=eq.${source}&season=eq.${season}&active=eq.true&limit=1000`);
    const ids=new Set(discovered.specialties.map((s:any)=>s.specialty_id));
    for(const stale of states.filter((s:any)=>!ids.has(s.specialty_id)))await db(`catalog_sync_state?source=eq.${source}&season=eq.${season}&specialty_id=eq.${encodeURIComponent(stale.specialty_id)}`,{method:'PATCH',body:JSON.stringify({active:false})});
    const eligible=states.filter((s:any)=>ids.has(s.specialty_id));
    const selected=body.specialty_id?eligible.filter((s:any)=>s.specialty_id===String(body.specialty_id)):selectTargets(eligible,limit);
    if(body.specialty_id&&!selected.length)throw Error('Unknown specialty in current catalogue');
    for(const s of selected){
     if(Date.now()-started>135000)break;
     const key=`source=eq.${source}&season=eq.${season}&specialty_id=eq.${encodeURIComponent(s.specialty_id)}`;
     await db('catalog_sync_state?'+key,{method:'PATCH',body:JSON.stringify({last_attempt_at:new Date().toISOString()})});
     try{
      const rows=await fetchPrograms(source,s,discovered.session);
      const result=await db('rpc/catalog_apply_snapshot',{method:'POST',body:JSON.stringify({p_source:source,p_season:season,p_specialty_id:s.specialty_id,p_rows:rows})});
      results.push({source,specialty:s.name,...result});
     }catch(e){const error=String((e as Error).message).slice(0,500);errors.push({source,specialty:s.name,error});
      await db('catalog_sync_state?'+key,{method:'PATCH',body:JSON.stringify({last_error:error})});
      if(source==='acgme')await db('acgme_specialties?acgme_specialty_id=eq.'+s.specialty_id,{method:'PATCH',body:JSON.stringify({last_attempt_at:new Date().toISOString(),last_error:error})});
     }
    }
   }catch(e){const error=String((e as Error).message).slice(0,500);errors.push({source,error});await db('catalog_sources?source=eq.'+source,{method:'PATCH',body:JSON.stringify({last_error:error})});}
  }
  const status=errors.length?(results.length?'partial':'failed'):'completed';
  const programs_seen=results.reduce((n,x)=>n+x.programs,0),new_programs=results.reduce((n,x)=>n+x.new_programs,0);
  await db('acgme_sync_runs?id=eq.'+runId,{method:'PATCH',body:JSON.stringify({status,completed_at:new Date().toISOString(),programs_seen,new_programs,error_message:errors.length?`${errors.length} catalogue checks failed`:null,details:{mode:'dual_catalog',results,errors}})});
  return Response.json({ok:status==='completed',status,programs_seen,new_programs,results,errors},{status:status==='failed'?502:200});
 }catch(e){if(runId)await db('acgme_sync_runs?id=eq.'+runId,{method:'PATCH',body:JSON.stringify({status:'failed',completed_at:new Date().toISOString(),error_message:String((e as Error).message).slice(0,500)})}).catch(()=>{});return Response.json({ok:false,error:'Catalogue synchronization failed'},{status:500});}
 finally{if(lease)await db('rpc/catalog_release',{method:'POST',body:JSON.stringify({p_lease:lease})}).catch(()=>{});}
});
