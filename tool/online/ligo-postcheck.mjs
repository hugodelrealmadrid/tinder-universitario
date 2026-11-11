import {readFileSync,writeFileSync} from 'node:fs';
import {readClient,sessionToken} from './read-client.mjs';
import {verifiedBackup,assertRules} from './operator.mjs';
import {captureFirestore,listObjects} from './backup.mjs';
import {sha,canonical,saveEncrypted} from './private-backup.mjs';
import {tokenPlan} from './ligo-cutover.mjs';
const statePath='build/ligo-deployment-current.json',s=JSON.parse(readFileSync(statePath));
const need=(v,k)=>{if(!v)throw Error(k);};
async function main(){
 need(s.project==='tinder-universitario'&&s.backendPromoted&&s.tokensRevoked,'publication-preconditions-missing');
 const {data:b}=verifiedBackup(s.backup),read=await readClient(),report={at:new Date().toISOString(),userDataWrites:0};
 await assertRules(read,'production');report.rulesMatchValidatedFiles=true;
 const token=await sessionToken();
 const run=await fetch('https://run.googleapis.com/v2/projects/tinder-universitario/locations/us-east1/services/tinder-api',{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(30000)});need(run.ok,'cloudrun-read-failed');const service=await run.json();
 need(service.latestReadyRevision===s.newRevision&&service.terminalCondition?.state==='CONDITION_SUCCEEDED'&&service.trafficStatuses.some(t=>t.revision===s.newRevision.split('/').at(-1)&&t.percent===100),'wrong-active-revision');
 need(service.template.containers[0].image===s.publishedImage&&service.scaling.maxInstanceCount===1&&service.template.scaling.maxInstanceCount===1&&service.template.maxInstanceRequestConcurrency===8,'backend-image-or-limits-mismatch');report.backendReady=true;
 const base='https://tinder-api-rcgmfjcicq-ue.a.run.app',checks=[];
 for(const [path,headers,want] of [['/administration/summary',{},401],['/verification/requests',{},401],['/profile/media/',{},401],['/chat/metadata/',{},401],['/administration/summary',{Authorization:'Bearer invalid'},401],['/administration/summary',{Origin:'https://unauthorized.example'},403]]){
  const r=await fetch(base+path,{headers,signal:AbortSignal.timeout(30000),redirect:'error'});await r.body?.cancel();need(r.status===want,'backend-auth-or-cors-failed');checks.push({path,status:r.status});
 }
 report.httpProtection=checks;
 const fs=await captureFirestore(read),old=new Map(b.firestore.documents.map(d=>[d.name,canonical(d.fields??{})]));
 const changed=fs.documents.filter(d=>old.get(d.name)!==canonical(d.fields??{})).map(d=>sha(d.name).slice(0,12)),missing=[...old.keys()].filter(n=>!fs.documents.some(d=>d.name===n));
 report.firestore={before:old.size,after:fs.documents.length,changed:changed.length,missing:missing.length};need(!changed.length&&!missing.length&&old.size===fs.documents.length,'firestore-concurrent-change-stop-review');
 const users=[];let page;do{const q=new URLSearchParams({maxResults:'1000'});if(page)q.set('nextPageToken',page);const a=await read('https://identitytoolkit.googleapis.com/v1/projects/tinder-universitario/accounts:batchGet?'+q);users.push(...(a.users??[]));page=a.nextPageToken;}while(page);
 const security=u=>Object.fromEntries(Object.entries(u).filter(([k])=>!['lastLoginAt','lastRefreshAt','lastLoginTime'].includes(k)));
 need(users.length===b.auth.users.length&&users.every(u=>{const old=b.auth.users.find(v=>v.localId===u.localId);return old&&canonical(security(old))===canonical(security(u));}),'auth-account-change-stop-review');report.auth={accounts:users.length,securityFieldsUnchanged:true};
 const storage=await listObjects(read),objects=new Map(storage.objects.map(m=>[m.name+'/'+m.generation,m]));need(objects.size===b.storage.files.length,'storage-object-count-changed');
 const plan=tokenPlan(b);for(const f of b.storage.files){const m=objects.get(f.metadata.name+'/'+f.metadata.generation);need(m&&m.size===f.metadata.size&&m.md5Hash===f.metadata.md5Hash&&m.crc32c===f.metadata.crc32c,'storage-integrity-changed');}
 need(storage.objects.every(m=>!m.metadata?.firebaseStorageDownloadTokens),'active-download-token-detected');
 for(const o of plan.objects){for(const token of o.tokens){const r=await fetch('https://firebasestorage.googleapis.com/v0/b/tinder-universitario.firebasestorage.app/o/'+encodeURIComponent(o.name)+'?alt=media&token='+encodeURIComponent(token),{method:'HEAD',signal:AbortSignal.timeout(30000),redirect:'error'});need([401,403,404].includes(r.status),'old-token-accepted');}}
 report.storage={objects:objects.size,contentChecksumsUnchanged:true,oldTokenObjectsDenied:plan.objects.length,activeDownloadTokens:0};
 const inventory=JSON.parse(readFileSync('build/online-readiness/artifact-verification.json'));const webChecks=[];
 for(const file of ['index.html','main.dart.js','flutter_bootstrap.js','manifest.json']){const r=await fetch('https://tinder-universitario.web.app/'+file+'?ligo-check='+Date.now(),{cache:'no-store',signal:AbortSignal.timeout(60000)});need(r.ok,'hosting-file-unavailable');const digest=sha(Buffer.from(await r.arrayBuffer()));need(digest===inventory.webFilesSha256.find(f=>f.file===file)?.sha256,'hosting-file-hash-mismatch');webChecks.push(file);}
 report.hosting={url:'https://tinder-universitario.web.app/',matchedFiles:webChecks};
 const sealed=saveEncrypted(s.directory+'/post-deploy-inventory.dpapi',{firestore:fs,auth:users,storage});report.encryptedInventory=sealed;
 writeFileSync(s.directory+'/post-deploy-checks.json',JSON.stringify(report,null,2),{flag:'wx'});s.rulesPublished=true;s.hostingPublished=true;s.postChecksPassed=true;writeFileSync(statePath,JSON.stringify(s,null,2));console.log(JSON.stringify(report));
}
main().catch(e=>{console.error(JSON.stringify({passed:false,code:/^[a-z0-9-]+$/.test(e.message)?e.message:'postcheck-failed-no-sensitive-details'}));process.exitCode=1;});
