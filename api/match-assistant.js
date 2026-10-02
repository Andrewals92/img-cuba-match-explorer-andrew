'use strict';
const {createAssistant}=require('../server/match-ai.cjs');
const {getVercelOidcToken}=require('@vercel/oidc');
const assistant=createAssistant({getProviderToken:async()=>process.env.AI_GATEWAY_API_KEY||getVercelOidcToken()});
module.exports=async function handler(req,res){
 res.setHeader('Cache-Control','private, no-store, max-age=0');res.setHeader('Vary','Authorization');
 res.setHeader('X-Content-Type-Options','nosniff');
 if(req.method!=='POST'){res.setHeader('Allow','POST');return res.status(405).json({error:'method_not_allowed'});}
 if(!String(req.headers['content-type']||'').startsWith('application/json'))return res.status(415).json({error:'json_required'});
 const origin=req.headers.origin;
 const allowed=['https://cubamatchexplorer.org','https://cubamatchexplorer.com','https://cuba-match-explorer.vercel.app',process.env.VERCEL_URL?'https://'+process.env.VERCEL_URL:null,process.env.VERCEL_BRANCH_URL?'https://'+process.env.VERCEL_BRANCH_URL:null].filter(Boolean);
 if(origin&&!allowed.includes(origin))return res.status(403).json({error:'origin_not_allowed'});
 if(Number(req.headers['content-length']||0)>10000||Buffer.byteLength(JSON.stringify(req.body||{}))>10000)return res.status(413).json({error:'input_too_large'});
 try{const token=/^Bearer ([^\s]+)$/.exec(req.headers.authorization||'')?.[1];
  const result=await assistant.run(req.body,token);if(result.status===429)res.setHeader('Retry-After',String(result.body.retry_after||60));return res.status(result.status).json(result.body);
 }catch(e){const status=[400,401,403].includes(e.status)?e.status:503;return res.status(status).json({error:status===401?'authentication_required':status===403?'not_authorized':status===400?'invalid_request':'temporarily_unavailable'});}
};
