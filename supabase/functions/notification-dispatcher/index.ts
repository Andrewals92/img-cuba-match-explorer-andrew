import webpush from 'npm:web-push@3.6.7';
const origin='https://cubamatchexplorer.org';
const base=Deno.env.get('SUPABASE_URL')!;
const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default;
const resend=Deno.env.get('RESEND_API_KEY');
const from=Deno.env.get('NOTIFICATION_EMAIL_FROM');
const verified=Deno.env.get('NOTIFICATION_EMAIL_DOMAIN_VERIFIED')==='true';
const emailReady=Boolean(resend&&from&&verified);
const esc=(s:string)=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
const safePath=(s:string)=>/^#\/(program\/[a-f0-9-]{36}|radar|interviews|notification-settings|notification-center)$/.test(s)?s:'#/notification-center';
const allowedEndpoint=(s:string)=>{try{const u=new URL(s);return u.protocol==='https:'&&!u.username&&!u.password&&['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].includes(u.hostname);}catch{return false;}};
async function db(path:string,init:RequestInit={}){const r=await fetch(base+'/rest/v1/'+path,{...init,headers:{apikey:key,...(key?.startsWith('eyJ')?{Authorization:'Bearer '+key}:{}),'Content-Type':'application/json',...(init.headers||{})},signal:AbortSignal.timeout(15000)});if(!r.ok){let c='';try{const err=await r.json();c=err.code||'';if(err.code==='21000')c+='_'+(String(err.message).includes('multiple')?'multiple':String(err.message).includes('more than one')?'cardinality':String(err.message).includes('JSON')?'json':'other');}catch{}throw Error('db_'+r.status+'_'+String(c).replace(/[^A-Z0-9_]/gi,'').slice(0,30));}const t=await r.text();return t?JSON.parse(t):null;}
const rpc=(name:string,args:object)=>db('rpc/'+name,{method:'POST',body:JSON.stringify(args)});
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return Response.json({error:'method_not_allowed'},{status:405});
 const token=req.headers.get('x-dispatch-token');if(!token||!key)return Response.json({error:'unauthorized'},{status:401});
 let config:any;
 try{config=await rpc('notification_worker_config',{p_token:token,p_email_ready:emailReady});}catch(err){console.log(JSON.stringify({stage:'worker_config',code:String(err.message).slice(0,80)}));return Response.json({error:'worker_config_unavailable',code:String(err.message).slice(0,80)},{status:503});}
 try{
 if(!config.vapid_private){const keys=webpush.generateVAPIDKeys();config=await rpc('notification_worker_config',{p_token:token,p_public:keys.publicKey,p_private:keys.privateKey,p_email_ready:emailReady});}
 webpush.setVapidDetails(origin,config.vapid_public,config.vapid_private);
 const jobs=await rpc('notification_claim_jobs',{p_limit:5});let sent=0,failed=0;
 for(const j of jobs){let status='transient',code:string|null=null,provider:string|null=null;
 try{
 const n=j.notification;if(n.expires_at&&Date.parse(n.expires_at)<=Date.now()){await rpc('notification_finish_job',{p_id:j.id,p_lease:j.lease_token,p_status:'cancelled',p_code:'expired'});continue;}const url=origin+'/'+safePath(n.action_path),prefs=origin+'/#/notification-settings';
 if(j.channel==='email'){
 if(!emailReady){code='provider_unconfigured';status='permanent';}
 else{
 const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+resend,'Content-Type':'application/json','Idempotency-Key':j.dedupe_key},body:JSON.stringify({from,to:[j.email],subject:n.title,text:n.body+'\n\nAbrir: '+url+'\nRecibes esta alerta por tus preferencias de Cuba Match Explorer. Desactivar alertas: '+prefs,html:'<h2>'+esc(n.title)+'</h2><p>'+esc(n.body)+'</p><p><a href="'+esc(url)+'">Abrir Cuba Match Explorer</a></p><p>Recibes esta alerta por tus preferencias.</p><p><a href="'+prefs+'">Preferencias / desactivar alertas</a></p>'}),signal:AbortSignal.timeout(15000)});
 if(r.ok){provider=(await r.json()).id;status='sent';}else{code='email_http_'+r.status;status=(r.status===429||r.status>=500)?'transient':'permanent';}
 }
 }else{
 const subs=await db('push_subscriptions?user_id=eq.'+j.user_id+'&enabled=eq.true&select=id,endpoint,p256dh,auth');
 if(!subs.length){status='cancelled';code='no_active_device';}
 else{let retry=false,delivered=false;
 for(const s of subs){
 const prior=await db('notification_deliveries?outbox_id=eq.'+j.id+'&subscription_id=eq.'+s.id+'&status=eq.sent&select=id&limit=1');if(prior.length){delivered=true;continue;}
 if(!allowedEndpoint(s.endpoint)){await db('push_subscriptions?id=eq.'+s.id,{method:'PATCH',body:JSON.stringify({enabled:false})});continue;}
 let ds='sent',dc=null;
 try{await webpush.sendNotification({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},JSON.stringify({title:'Cuba Match Explorer',body:'Tienes una nueva alerta. Abre la app para ver los detalles.',path:safePath(n.action_path),id:j.notification_id}),{TTL:3600,timeout:12000,topic:j.notification_id.replaceAll('-','').slice(0,32)});}
 catch(err:any){const http=Number(err.statusCode)||0;dc='push_http_'+http;ds='failed';if(http===404||http===410){await db('push_subscriptions?id=eq.'+s.id,{method:'PATCH',body:JSON.stringify({enabled:false})});}else if(http===429||http>=500||http===0)retry=true;}
 if(ds==='sent')delivered=true;
 await db('notification_deliveries',{method:'POST',body:JSON.stringify({outbox_id:j.id,subscription_id:s.id,attempt:j.attempt_count,status:ds,error_code:dc})});
 }
 status=retry?'transient':delivered?'sent':'permanent';code=retry?'push_transient':delivered?null:'no_deliverable_device';
 }
 }
 }catch{code='transport_error';status='transient';}
 await rpc('notification_finish_job',{p_id:j.id,p_lease:j.lease_token,p_status:status,p_code:code,p_provider:provider});
 if(status==='sent')sent++;else failed++;
 // Safe operational IDs/codes only. No email addresses, body, endpoint, or keys.
 console.log(JSON.stringify({notification_id:j.notification_id,channel:j.channel,status,code,attempt:j.attempt_count}));
 }
 return Response.json({ok:true,sent,failed,email_ready:emailReady,push_ready:true});
 }catch{return Response.json({error:'dispatcher_failed'},{status:503});}
});
