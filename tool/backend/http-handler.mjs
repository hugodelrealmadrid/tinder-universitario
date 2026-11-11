import {decideDiscovery,sendChat,readChatReceipt} from './dating-writes.mjs';
import {Stories} from './stories.mjs';
import {Notifications} from './notifications.mjs';
import {registrationOptions} from './registration-directory.mjs';
import {AcademicAdmin} from './academic-admin.mjs';
import {readDossierHistory} from './administration-dossier-history.mjs';
import {readDossier} from './administration-dossier.mjs';
import {AdministrationRead} from './administration-read.mjs';
import {VerificationBackend,AccessError} from './verification.mjs';
import {uploadChat,deleteChat} from './chat-upload.mjs';
import {uploadPhoto,readPhoto,deletePhoto,readDossierPhoto} from './profile-media.mjs';
import {readChat} from './chat-read.mjs';
import {CatalogBackend} from './catalogs.mjs';
export function requestHandler(services,{origins=['http://127.0.0.1:7357'],operationsEnabled=true,publicRegistrationEnabled=false,notificationsEnabled=false,storiesEnabled=false}={}){
const notifications=new Notifications(services);
const backend=new VerificationBackend({...services,notifications:notificationsEnabled?notifications:null});
const catalogs=new CatalogBackend({db:services.db,authorize:(tx,uid)=>backend.actor(tx,uid,true)});
const administrationRead=new AdministrationRead(backend);
const academic=new AcademicAdmin(backend);
const stories=new Stories(backend);
const limits=new Map();
let inflight=0;
let registrationWindow=0,registrationReads=0;
async function body(req,max){let size=0;const chunks=[];for await(const b of req){size+=b.length;if(size>max)throw new AccessError('payload-too-large');chunks.push(b);}return Buffer.concat(chunks);}
return async(req,res)=>{
 if(inflight>=16){res.writeHead(503).end();return;}inflight++;
 res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
 try{
  const origin=req.headers.origin;
  if(origin&&!origins.includes(origin))throw new AccessError('permission-denied');
  if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
  if(req.method==='OPTIONS'){
   const headers=(req.headers['access-control-request-headers']??'').toLowerCase().split(',').map(v=>v.trim()).filter(Boolean);
   if(!origin||!['GET','POST'].includes(req.headers['access-control-request-method'])||headers.some(h=>!['authorization','content-type','x-chat-path','x-story-caption'].includes(h)))throw new AccessError('permission-denied');
   res.setHeader('Access-Control-Allow-Methods','GET, POST');res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type, X-Chat-Path, X-Story-Caption');res.writeHead(204).end();return;
  }
  const url=new URL(req.url,'http://127.0.0.1:7360'),path=url.pathname;
  if(req.method==='GET'&&path==='/registration/options'&&publicRegistrationEnabled){
   if(!operationsEnabled)throw new AccessError('maintenance');
   const now=Date.now();
   if(now>=registrationWindow){registrationWindow=now+60000;registrationReads=0;}
   if(++registrationReads>240)throw new AccessError('rate-limited');
   const items=await registrationOptions(services.db,url.searchParams.get('kind'),url.searchParams.get('university'),url.searchParams.get('campus'));
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify({items}));return;
  }
  const token=/^Bearer (.+)$/.exec(req.headers.authorization??'')?.[1];if(!token)throw new AccessError('unauthenticated');
  let claims;try{claims=await services.auth.verifyIdToken(token,true);}catch{throw new AccessError('unauthenticated');}
  if(!operationsEnabled)throw new AccessError('maintenance');
  const uid=claims.uid,now=Date.now(),rateKey=uid+':'+(path==='/chat/receipt'||path==='/discovery/decide'?path:req.method==='GET'?'read':'write'),previous=limits.get(rateKey);
  const rate=previous&&previous.until>now?previous:{until:now+60000,count:0};limits.set(rateKey,rate);
  if(++rate.count>(req.method==='GET'||path==='/chat/receipt'||path==='/discovery/decide'?120:30))throw new AccessError('rate-limited');
  if(limits.size>1000)for(const [k,v]of limits)if(v.until<now)limits.delete(k);
  let result;
  if(path.startsWith('/stories/')){
   if(!storiesEnabled)throw new AccessError('not-found');
   const id=url.searchParams.get('id');
   const cursor=url.searchParams.get('cursor');
   let data;
   if(req.method==='GET'&&path==='/stories/feed')data=await stories.feed(uid,cursor);
   else if(req.method==='GET'&&path==='/stories/viewers')data=await stories.viewers(uid,id,cursor);
   else if(req.method==='GET'&&path==='/stories/media'){
    const media=await stories.media(uid,id);
    res.setHeader('Content-Type',media.mime);res.end(media.bytes);return;
   }else if(req.method==='POST'&&path==='/stories/publish'){
    data=await stories.publish(uid,await body(req,15*1024*1024),req.headers['content-type'],decodeURIComponent(req.headers['x-story-caption']??''));
   }else if(req.method==='POST'&&path==='/stories/view')data=await stories.view(uid,id);
   else if(req.method==='POST'&&path==='/stories/delete')data=await stories.remove(uid,id);
   else if(req.method==='POST'&&path==='/stories/report')data=await stories.report(uid,id);
   else if(req.method==='POST'&&path==='/stories/reply'){
    data=await stories.reply(uid,id,(await body(req,4096)).toString());
   }else throw new AccessError('not-found');
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify(data));return;
  }
  if(req.method==='GET'&&path==='/administration/profile-photo'){
   const data=await readDossierPhoto(backend,uid,url.searchParams.get('photo'));
   res.setHeader('Cache-Control','private, no-store');
   res.setHeader('Content-Type',data.contentType);res.end(data.bytes);return;
  }
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
  else if(req.method==='GET'&&path.startsWith('/administration/catalogs/'))result=await catalogs.list(uid,path.split('/').at(-1),url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/verification/own')result=await backend.ownRequest(uid);
  else if(req.method==='GET'&&path==='/administration/identities')result=await administrationRead.identities(uid,(url.searchParams.get('ids')??'').split(',').filter(Boolean));
  else if(req.method==='GET'&&path==='/administration/event-feed')result=await administrationRead.eventFeed(uid,url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/administration/report-feed')result=await administrationRead.reportFeed(uid,{status:url.searchParams.get('status')??'pending',cursor:url.searchParams.get('cursor')});
  else if(req.method==='GET'&&path==='/administration/academic')result=await academic.list(uid,{university:url.searchParams.get('university'),campus:url.searchParams.get('campus'),cursor:url.searchParams.get('cursor')});
  else if(req.method==='GET'&&path==='/administration/summary')result=await administrationRead.summary(uid);
  else if(req.method==='GET'&&path==='/administration/dossier/history')result=await readDossierHistory(backend,uid,url.searchParams.get('user'),url.searchParams.get('kind'),url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/administration/dossier')result=await readDossier(backend,uid,url.searchParams.get('user'));
  else if(req.method==='GET'&&path==='/administration/users')result=await administrationRead.users(uid,url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/administration/audit')result=await backend.listAudit(uid,url.searchParams.get('cursor'));
  else if(req.method==='GET'&&path==='/administration/reports')result=await backend.listReports(uid);
  else if(req.method==='GET'&&path.startsWith('/administration/account/'))result=await backend.lookupAccount(uid,path.split('/').at(-1));
  else if(req.method==='POST'&&path.startsWith('/verification/upload/'))result=await backend.upload(uid,path.split('/').at(-1),await body(req,5*1024*1024));
  else if(req.method==='POST'){
   let data;try{data=JSON.parse((await body(req,path==='/chat/send'?8192:4096)).toString()||'{}');}catch(e){if(e instanceof AccessError)throw e;throw new AccessError('invalid-argument');}
   if(!data||Array.isArray(data)||typeof data!=='object')throw new AccessError('invalid-argument');
   const only=keys=>{if(Object.keys(data).some(k=>!keys.includes(k)))throw new AccessError('invalid-argument');};
   switch(path){
    case '/discovery/decide':if(!notificationsEnabled)throw new AccessError('not-found');only(['target','type']);result=await decideDiscovery(backend,uid,data);break;
    case '/chat/send':if(!notificationsEnabled)throw new AccessError('not-found');only(['matchId','messageId','type','text','durationMs']);result=await sendChat(backend,uid,data);break;
    case '/chat/receipt':if(!notificationsEnabled)throw new AccessError('not-found');only(['matchId','messageId']);result=await readChatReceipt(backend,uid,data);break;
    case '/notifications/read':if(!notificationsEnabled)throw new AccessError('not-found');only(['id']);result=await notifications.mark(uid,data.id);break;
    case '/notifications/preferences':if(!notificationsEnabled)throw new AccessError('not-found');only(['push']);result=await notifications.preferences(uid,data.push);break;
    case '/notifications/device':if(!notificationsEnabled)throw new AccessError('not-found');only(['token','platform']);result=await notifications.device(uid,data.token,data.platform);break;
    case '/notifications/device/remove':if(!notificationsEnabled)throw new AccessError('not-found');only(['token']);result=await notifications.device(uid,data.token,null,true);break;
    case '/administration/academic':only(['university','campus','target','revision','data']);result=await academic.save(uid,data);break;
    case '/administration/catalog':only(['kind','id','data','expectedRevision','requestId']);result=await catalogs.save(uid,data.kind,data);break;
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
 }catch(e){const code=e instanceof AccessError?e.code:'operation-failed';res.writeHead(code==='maintenance'?503:code==='unauthenticated'?401:(code==='conflict'||code==='already-decided')?409:code==='payload-too-large'?413:code==='rate-limited'?429:code==='invalid-argument'||code==='invalid-image'?400:403,{'Content-Type':'application/json'});res.end(JSON.stringify({error:code}));}
 finally{inflight--;}
};
}
