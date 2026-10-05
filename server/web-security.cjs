'use strict';
const {createHmac}=require('node:crypto');
const {checkBotId}=require('botid/server');
const SUPABASE_URL='https://xqjjiveuvnioachgxqez.supabase.co';
const PUBLIC_KEY='sb_publishable__l6-hmw3I9zd7o_rq3dzug_EcvdFZ4N';
const RPCS=new Set(['community_overview','program_stats','recent_interview_activity','match_state_stats','match_program_stats','similar_cohort','similar_programs','program_directory_v4','program_identity_index_v4','program_compare_stats','program_resources_v43','program_season_intelligence_v43','program_source_directory_v43','specialty_wave_overview_v43','program_radar','new_accredited_programs','notification_channel_status','notification_operations','notification_unread_count','program_workspace_health_v4','intelligence_health_v43','match_intelligence_v50','ai_feedback_v50','admin_ai_operations_v50','admin_site_summary','admin_set_user_role','admin_delete_user','admin_pending_verifications','admin_set_verification','delete_my_data']);
const TABLES=new Set(['programs','profiles','applicant_cycles','program_reports','acgme_specialties','accreditation_events','program_external_sources','program_watch_subscriptions','notifications','interview_events','user_program_watchlist','notification_preferences','radar_subscriptions','push_subscriptions']);
const READ_ONLY=new Set(['programs','acgme_specialties','accreditation_events','program_external_sources']);
const AUTH_METHODS={'/auth/v1/token':['POST'],'/auth/v1/signup':['POST'],'/auth/v1/recover':['POST'],'/auth/v1/resend':['POST'],'/auth/v1/logout':['POST'],'/auth/v1/user':['GET','PUT']};
const AUTH_KEYS={token:['email','password','refresh_token','gotrue_meta_security'],signup:['email','password','data','gotrue_meta_security'],recover:['email','gotrue_meta_security'],resend:['email','type','gotrue_meta_security'],logout:[],user:['password']};
class WebError extends Error{constructor(status,message){super(message);this.status=status;}}
function origins(){return ['https://cubamatchexplorer.org','https://cubamatchexplorer.com','https://cuba-match-explorer.vercel.app',process.env.VERCEL_URL&&'https://'+process.env.VERCEL_URL,process.env.VERCEL_BRANCH_URL&&'https://'+process.env.VERCEL_BRANCH_URL].filter(Boolean);}
function validateRequest(req){
 if(req.method!=='POST')throw new WebError(405,'method_not_allowed');
 if(!origins().includes(req.headers.origin))throw new WebError(403,'origin_not_allowed');
 if(req.headers['sec-fetch-site']&&req.headers['sec-fetch-site']!=='same-origin')throw new WebError(403,'origin_not_allowed');
 if(!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type']||''))throw new WebError(415,'json_required');
 if(Number(req.headers['content-length']||0)>65536||Buffer.byteLength(JSON.stringify(req.body||{}))>65536)throw new WebError(413,'request_too_large');
 const auth=req.headers.authorization;
 if(auth&&!/^Bearer [A-Za-z0-9_.-]{1,6000}$/.test(auth))throw new WebError(401,'authentication_required');
}
function validateTarget(input){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['path','method','body','prefer'].includes(k)))throw new WebError(400,'invalid_request');
 const {path,method='GET',body=null,prefer=null}=input;
 if(typeof path!=='string'||path.length>8000||/[\\#\r\n]/.test(path)||!/^\/(rest|auth)\/v1\//.test(path))throw new WebError(400,'invalid_target');
 const url=new URL(path,SUPABASE_URL);
 if(url.origin!==SUPABASE_URL||url.pathname!==path.split('?')[0]||/%/.test(url.pathname))throw new WebError(400,'invalid_target');
 if(!['GET','POST','PATCH','PUT','DELETE'].includes(method))throw new WebError(405,'method_not_allowed');
 if(body!==null&&(typeof body!=='object'||Array.isArray(body)))throw new WebError(400,'invalid_body');
 if(['GET','DELETE'].includes(method)&&body!==null)throw new WebError(400,'invalid_body');
 if(prefer!==null&&(typeof prefer!=='string'||!/^((return=(minimal|representation)|resolution=(merge|ignore)-duplicates)(,\s*)?){1,2}$/.test(prefer)))throw new WebError(400,'invalid_prefer');
 let bucket='data';
 if(url.pathname.startsWith('/auth/v1/')){
  if(!AUTH_METHODS[url.pathname]?.includes(method))throw new WebError(403,'route_not_allowed');
  const action=url.pathname.split('/').pop();
  if(body&&Object.keys(body).some(k=>!AUTH_KEYS[action].includes(k)))throw new WebError(400,'invalid_body');
  for(const [key,value] of url.searchParams){
   if(key==='redirect_to'){if(!['https://cubamatchexplorer.org/','https://cubamatchexplorer.com/','https://cuba-match-explorer.vercel.app/'].includes(value))throw new WebError(400,'invalid_redirect');}
   else if(key==='grant_type'){if(!['password','refresh_token'].includes(value))throw new WebError(400,'invalid_grant');}
   else throw new WebError(400,'invalid_query');
  }
  bucket=(action==='token'&&url.searchParams.get('grant_type')==='refresh_token')||action==='user'||action==='logout'?'session':'auth';
 }else if(url.pathname.startsWith('/rest/v1/rpc/')){
  if(!RPCS.has(url.pathname.slice('/rest/v1/rpc/'.length))||method!=='POST'||url.search)throw new WebError(403,'route_not_allowed');
 }else{
  const table=url.pathname.slice('/rest/v1/'.length);
  if(!TABLES.has(table)||method==='PUT'||(READ_ONLY.has(table)&&method!=='GET'))throw new WebError(403,'route_not_allowed');
  if(method==='GET'){
   const limit=Number(url.searchParams.get('limit')||1000);
   if(!Number.isInteger(limit)||limit<1||limit>1000)throw new WebError(400,'invalid_limit');
   url.searchParams.set('limit',String(limit));
  }
 }
 return {url:url.href,method,body,prefer,bucket};
}
function gatewayHeaders(req,secret=process.env.CME_GATEWAY_SECRET){
 if(!secret||secret.length<48)throw new WebError(503,'security_unavailable');
 const ip=String(req.headers['x-vercel-forwarded-for']||req.headers['x-forwarded-for']||req.socket?.remoteAddress||'unknown').split(',')[0].trim();
 const h={apikey:PUBLIC_KEY,'Content-Type':'application/json','x-cme-gateway':secret,'x-cme-client':createHmac('sha256',secret).update(ip).digest('hex')};
 if(req.headers.authorization)h.Authorization=req.headers.authorization;
 return h;
}
async function verifyHuman(req,verify=checkBotId){
 const result=await verify({developmentOptions:{isDevelopment:false},advancedOptions:{checkLevel:'basic',headers:req.headers}});
 if(result?.isHuman!==true||result.isBot||result.isVerifiedBot)throw new WebError(403,'browser_verification_required');
}
async function reserve(headers,bucket,fetchImpl=fetch){
 const result=await fetchImpl(SUPABASE_URL+'/rest/v1/rpc/reserve_web_request',{method:'POST',headers,body:JSON.stringify({p_bucket:bucket}),signal:AbortSignal.timeout(10000),redirect:'error'});
 if(!result.ok)throw new WebError(result.status===401?401:503,result.status===401?'authentication_required':'security_unavailable');
 const quota=await result.json();
 if(!quota||quota.allowed!==true)throw new WebError(429,'rate_limit_exceeded');
}
function responseHeaders(res){res.setHeader('Cache-Control','private, no-store, max-age=0');res.setHeader('Vary','Origin, Authorization');res.setHeader('X-Content-Type-Options','nosniff');}
module.exports={SUPABASE_URL,PUBLIC_KEY,WebError,validateRequest,validateTarget,gatewayHeaders,verifyHuman,reserve,responseHeaders};
