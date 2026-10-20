import {createServer} from 'node:http';
import {emulatorServices} from './emulator.mjs';
import {VerificationBackend,AccessError} from './verification.mjs';
import {uploadChat,deleteChat} from './chat-upload.mjs';
import {uploadPhoto,readPhoto,deletePhoto} from './profile-media.mjs';
import {cleanupMedia} from './media-cleanup.mjs';
import {readChat} from './chat-read.mjs';
const services=await emulatorServices(),backend=new VerificationBackend(services);
const limits=new Map();
let inflight=0;
async function body(req,max){let size=0;const chunks=[];for await(const b of req){size+=b.length;if(size>max)throw new AccessError('payload-too-large');chunks.push(b);}return Buffer.concat(chunks);}
createServer(async(req,res)=>{
 if(inflight>=16){res.writeHead(503).end();return;}inflight++;
 res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
 try{
  if(req.headers.origin&&req.headers.origin!=='http://127.0.0.1:7357')throw new AccessError('permission-denied');
  const token=/^Bearer (.+)$/.exec(req.headers.authorization??'')?.[1];if(!token)throw new AccessError('unauthenticated');
  let claims;try{claims=await services.auth.verifyIdToken(token,true);}catch{throw new AccessError('unauthenticated');}
  const uid=claims.uid,now=Date.now(),rateKey=uid+':'+(req.method==='GET'?'read':'write'),previous=limits.get(rateKey);
  const rate=previous&&previous.until>now?previous:{until:now+60000,count:0};limits.set(rateKey,rate);
  if(++rate.count>(req.method==='GET'?120:30))throw new AccessError('rate-limited');
  if(limits.size>1000)for(const [k,v]of limits)if(v.until<now)limits.delete(k);
  const url=new URL(req.url,'http://127.0.0.1:7360'),path=url.pathname;
  let result;
  if(req.method==='GET'&&path.startsWith('/profile/media/')){const data=await readPhoto(backend,uid,decodeURIComponent(path.slice('/profile/media/'.length)),token);res.setHeader('Content-Type',data.contentType);res.end(data.bytes);return;}
  if(req.method==='GET'&&path.startsWith('/verification/document/')){
   const bytes=await backend.readDocument(uid,path.split('/').at(-1));res.setHeader('Content-Type','image/png');res.end(bytes);return;
  }
  if(req.method==='GET'&&(path.startsWith('/chat/metadata/')||path.startsWith('/chat/media/'))){
   const download=path.startsWith('/chat/media/');const data=await readChat(backend,uid,decodeURIComponent(path.slice((download?'/chat/media/':'/chat/metadata/').length)),download);
   if(download){res.setHeader('Content-Type',data.contentType);res.end(data.bytes);return;}result=data;
  }
  else if(req.method==='POST'&&path==='/chat/upload')result=await uploadChat(backend,uid,req.headers['x-chat-path'],await body(req,15*1024*1024),req.headers['content-type']);
  else if(req.method==='POST'&&path==='/profile/upload')result=await uploadPhoto(backend,uid,req.headers['x-chat-path'],await body(req,5*1024*1024),req.headers['content-type']);
  else if(req.method==='GET'&&path==='/verification/requests')result=await backend.listRequests(uid,{status:url.searchParams.get('status')??'pending',cursor:url.searchParams.get('cursor')});
  else if(req.method==='GET'&&path==='/verification/own')result=await backend.ownRequest(uid);
  else if(req.method==='GET'&&path==='/administration/audit')result=await backend.listAudit(uid,url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/administration/reports')result=await backend.listReports(uid);
  else if(req.method==='GET'&&path.startsWith('/administration/account/'))result=await backend.lookupAccount(uid,path.split('/').at(-1));
  else if(req.method==='POST'&&path.startsWith('/verification/upload/'))result=await backend.upload(uid,path.split('/').at(-1),await body(req,5*1024*1024));
  else if(req.method==='POST'){
   let data;try{data=JSON.parse((await body(req,4096)).toString()||'{}');}catch(e){if(e instanceof AccessError)throw e;throw new AccessError('invalid-argument');}
   if(!data||Array.isArray(data)||typeof data!=='object')throw new AccessError('invalid-argument');
   const only=keys=>{if(Object.keys(data).some(k=>!keys.includes(k)))throw new AccessError('invalid-argument');};
   switch(path){
    case '/account/provision':only([]);result=await backend.provision(uid);break;
    case '/profile/delete':only(['path']);result=await deletePhoto(backend,uid,data.path);break;
    case '/chat/delete':only(['path']);result=await deleteChat(backend,uid,data.path);break;
    case '/verification/begin':only([]);result=await backend.begin(uid);break;
    case '/verification/withdraw':only(['requestId']);result=await backend.withdraw(uid,data.requestId);break;
    case '/verification/decide':only(['requestId','status','reasonCode']);result=await backend.decide(uid,data.requestId,data.status,data.reasonCode);break;
    case '/administration/role':only(['uid','role']);result=await backend.changeRole(uid,data.uid,data.role);break;
    case '/administration/suspend':only(['uid','suspended','reasonCode']);result=await backend.suspend(uid,data.uid,data.suspended,data.reasonCode);break;
    case '/administration/report':only(['reportId','resolution']);result=await backend.reviewReport(uid,data.reportId,data.resolution);break;
    default:throw new AccessError('not-found');
   }
  }else if(result===undefined)throw new AccessError('not-found');
  res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result===undefined?{ok:true}:result));
 }catch(e){const code=e instanceof AccessError?e.code:'operation-failed';res.writeHead(code==='unauthenticated'?401:code==='conflict'?409:code==='payload-too-large'?413:code==='rate-limited'?429:code==='invalid-argument'||code==='invalid-image'?400:403,{'Content-Type':'application/json'});res.end(JSON.stringify({error:code}));}
 finally{inflight--;}
}).listen(7360,'127.0.0.1',()=>console.log('Backend demo: 127.0.0.1:7360; sin credenciales ni recursos remotos.'));
let cleaning=false;
const clean=async()=>{if(cleaning)return;cleaning=true;try{await backend.cleanupDue();await cleanupMedia(backend);}catch{console.error('private-cleanup-retry');}finally{cleaning=false;}};
setInterval(clean,5000).unref();void clean();
