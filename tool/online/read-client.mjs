import {createRequire} from 'node:module';
export const PROJECT='tinder-universitario';
const require=createRequire(import.meta.url);
const hosts=new Set(['firebase.googleapis.com','identitytoolkit.googleapis.com','firestore.googleapis.com','storage.googleapis.com','firebaserules.googleapis.com']);
export async function sessionToken(){
 const auth=require('../node_modules/firebase-tools/lib/auth.js'),api=require('../node_modules/firebase-tools/lib/api.js');
 const a=auth.getGlobalDefaultAccount();if(!a)throw Error('login-required');
 let token=a.tokens.access_token;
 if(!token||a.tokens.expires_at<Date.now()+120000){
  const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'refresh_token',refresh_token:a.tokens.refresh_token,client_id:api.clientId(),client_secret:api.clientSecret()}),signal:AbortSignal.timeout(20000)});
  if(!r.ok)throw Error('login-required');token=(await r.json()).access_token;
 }
 return token;
}
export async function readClient(){
 const token=await sessionToken();
 return async(url,body,{binary=false}={})=>{
  const u=new URL(url);
  if(u.protocol!=='https:'||!hosts.has(u.hostname)||u.username||u.password)throw Error('read-host-denied');
  if(body&&!/:(listCollectionIds|runQuery)$/.test(u.pathname))throw Error('read-method-denied');
  const r=await fetch(u,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000),redirect:'error'});
  if(!r.ok){const e=await r.json().catch(()=>({}));const text=e.error?.message??'';const kind=u.pathname.includes('listCollectionIds')?'collections':u.pathname.endsWith('/indexes')?'indexes':u.pathname.includes('/documents/')?'documents':u.pathname.endsWith('runQuery')?'query':'other';throw Error('read-http-'+r.status+'-'+kind+(/read.?time|timestamp/i.test(text)?'-timestamp':'')+(/page.?size/i.test(text)?'-pagesize':'')+(/snapshot|consistency/i.test(text)?'-consistency':''));}
  return binary?Buffer.from(await r.arrayBuffer()):r.json();
 };
}
