'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const s=require('../server/web-security.cjs');
const req=()=>({method:'POST',headers:{origin:'https://cubamatchexplorer.org','content-type':'application/json','sec-fetch-site':'same-origin','x-vercel-forwarded-for':'192.0.2.10'},body:{path:'/rest/v1/rpc/similar_cohort',method:'POST',body:{}}});
test('reject cross-site, missing origin, invalid credentials and oversized input',()=>{
 for(const mutate of [r=>delete r.headers.origin,r=>r.headers.origin='https://evil.test',r=>r.headers['sec-fetch-site']='cross-site',r=>r.headers.authorization='Bearer a\r\nX-Evil: yes',r=>r.body.data='x'.repeat(65537)]){const r=req();mutate(r);assert.throws(()=>s.validateRequest(r),s.WebError);}
 assert.doesNotThrow(()=>s.validateRequest(req()));
});
test('only fixed routes and verbs; no SSRF, header injection, batching or privileged methods',()=>{
 for(const input of [{path:'https://evil.test/x'},{path:'/rest/v1/../../auth/v1/admin/users'},{path:'/rest/v1/%2e%2e/admin'},{path:'/rest/v1/rpc/reserve_web_request',method:'POST'},{path:'/rest/v1/rpc/ai_begin_request_v50',method:'POST'},{path:'/auth/v1/admin/users',method:'POST'},{path:'/rest/v1/programs',method:'DELETE'},{path:'/rest/v1/profiles?limit=999999'},{path:'/rest/v1/profiles',prefer:'tx=rollback'},{path:'/rest/v1/profiles',method:'POST',body:[{id:'a'},{id:'b'}]},{path:'/auth/v1/recover?redirect_to=https://evil.test/',method:'POST',body:{email:'a@test.invalid'}},{path:'/rest/v1/rpc/similar_cohort?select=*',method:'POST'}])assert.throws(()=>s.validateTarget(input),s.WebError);
 assert.equal(s.validateTarget(req().body).bucket,'data');
 assert.equal(s.validateTarget({path:'/auth/v1/token?grant_type=password',method:'POST',body:{email:'a@test.invalid',password:'pw'}}).bucket,'auth');
 assert.equal(s.validateTarget({path:'/auth/v1/token?grant_type=refresh_token',method:'POST',body:{refresh_token:'test'}}).bucket,'session');
 assert.match(s.validateTarget({path:'/rest/v1/programs?specialty=eq.Internal%20Medicine'}).url,/limit=1000/);
});
test('only trusted server headers are forwarded; user JWT is unchanged and IP is hashed',()=>{
 const r=req();r.headers.authorization='Bearer test.jwt.token';r.headers['x-cme-gateway']='attacker';r.headers.apikey='attacker';r.headers['x-cme-client']='attacker';r.headers['accept-profile']='cme_private';
 const h=s.gatewayHeaders(r,'s'.repeat(96));assert.equal(h.Authorization,r.headers.authorization);assert.equal(h['x-cme-gateway'],'s'.repeat(96));assert.equal(h.apikey,s.PUBLIC_KEY);assert.match(h['x-cme-client'],/^[a-f0-9]{64}$/);assert.equal(h['accept-profile'],undefined);assert.throws(()=>s.gatewayHeaders(r,''));
});
test('bots including verified bots are denied; human verification is mandatory and fail closed',async()=>{
 for(const result of [{isHuman:false,isBot:true},{isHuman:true,isVerifiedBot:true},{},null])await assert.rejects(s.verifyHuman(req(),async()=>result),s.WebError);
 await assert.rejects(s.verifyHuman(req(),async()=>{throw Error('unavailable')}));
 await s.verifyHuman(req(),async config=>{assert.equal(config.developmentOptions.isDevelopment,false);assert.equal(config.advancedOptions.checkLevel,'basic');return {isHuman:true,isBot:false,isVerifiedBot:false};});
});
test('quota denial prevents upstream work; database errors fail closed',async()=>{
 await assert.rejects(s.reserve({},'data',async()=>({ok:true,json:async()=>({allowed:false})})),e=>e.status===429);
 await assert.rejects(s.reserve({},'data',async()=>({ok:false,status:500})),e=>e.status===503);
 await s.reserve({},'data',async(url,options)=>{assert.match(url,/reserve_web_request$/);assert.equal(options.redirect,'error');return {ok:true,json:async()=>({allowed:true})};});
});
test('static publication contains no imports, SQL migrations, tests or server files',()=>{
 assert(fs.existsSync('public-build/bot-protection.js'));for(const file of ['supabase','server','tests','package.json','SECURITY.md'])assert(!fs.existsSync('public-build/'+file));
 const config=JSON.parse(fs.readFileSync('vercel.json'));assert.equal(config.outputDirectory,'public-build');assert(config.headers[0].headers.some(x=>x.key==='X-Frame-Options'&&x.value==='DENY'));
 const app=fs.readFileSync('public-build/app.js','utf8');assert(!app.includes('fetch(CLOUD.url'));assert(app.includes('fetch(CLOUD.gateway'));assert(!fs.readFileSync('public-build/cloud-config.js','utf8').includes('supabase.co'));
});
test('edge rule matches declared AI clients and preserves ordinary browser signatures',()=>{
 const rule=JSON.parse(fs.readFileSync('vercel.json')).routes[0];const pattern=new RegExp(rule.has[0].value);
 for(const ua of ['GPTBot/1.2','Mozilla/5.0 ChatGPT-User/1.0','claudebot','Perplexity-User/1.0','HeadlessChrome/130.0'])assert(pattern.test(ua));
 for(const ua of ['Mozilla/5.0 Chrome/140.0 Safari/537.36','Mozilla/5.0 iPhone Version/18.0 Mobile Safari/604.1'])assert(!pattern.test(ua));
 assert.equal(rule.mitigate.action,'deny');
});
