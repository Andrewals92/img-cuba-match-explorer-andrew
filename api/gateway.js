'use strict';
const security=require('../server/web-security.cjs');
module.exports=async function handler(req,res){
 security.responseHeaders(res);
 try{
  security.validateRequest(req);
  const target=security.validateTarget(req.body);
  await security.verifyHuman(req);
  const headers=security.gatewayHeaders(req);
  await security.reserve(headers,target.bucket);
  if(target.prefer)headers.Prefer=target.prefer;
  const upstream=await fetch(target.url,{method:target.method,headers,body:target.body===null?undefined:JSON.stringify(target.body),signal:AbortSignal.timeout(20000),redirect:'error'});
  const text=await upstream.text();
  res.setHeader('Content-Type','application/json; charset=utf-8');
  if(upstream.headers.has('retry-after'))res.setHeader('Retry-After',upstream.headers.get('retry-after'));
  return res.status(upstream.status).send(text);
 }catch(error){
  const status=error instanceof security.WebError?error.status:503;
  if(status===429)res.setHeader('Retry-After','60');
  if(status===405)res.setHeader('Allow','POST');
  return res.status(status).json({message:error instanceof security.WebError?error.message:'security_unavailable'});
 }
};
