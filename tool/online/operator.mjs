// Operaciones privilegiadas de operador. Ninguna se ejecuta al importar el módulo.
import {readClient,sessionToken,PROJECT} from './read-client.mjs';
import {canonical,sha,loadEncrypted} from './private-backup.mjs';
import {MIGRATION,firestoreWrites,bootstrapWrites,value,encode} from './migration-plan.mjs';
import {captureFirestore} from './backup.mjs';
import {readFileSync} from 'node:fs';
const root=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`,marker=root+'/migrationState/'+MIGRATION;
const prefix=`projects/${PROJECT}/databases/(default)/documents/`;
export function assertExecution({apply,maintenance,kind}){if(apply!==true||!['migrate','revoke','bootstrap'].includes(kind)||(kind!=='bootstrap'&&maintenance!==true))throw Error('explicit-authorization-required');}
export function verifiedBackup(dir){
 const m=JSON.parse(readFileSync(dir+'/verified.json','utf8')),bytes=readFileSync(dir+'/backup.dpapi');
 if(!m.verified||m.project!==PROJECT||sha(bytes)!==m.cipherSha256)throw Error('backup-not-verified');
 const data=loadEncrypted(dir+'/backup.dpapi');if(sha(Buffer.from(JSON.stringify(data)))!==m.payloadSha256)throw Error('backup-payload-mismatch');return {data,manifest:m};
}
export async function assertRules(read,mode){
 const releases=await read(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases?pageSize=100`);
 const expected={firestore:readFileSync(new URL(mode==='maintenance'?'../../deploy/firestore.maintenance.rules':'../../firestore.rules',import.meta.url),'utf8'),storage:readFileSync(new URL('../../storage.rules',import.meta.url),'utf8')};
 for(const kind of ['firestore','storage']){const r=releases.releases?.find(r=>r.name.endsWith(kind==='firestore'?'/cloud.firestore':'/firebase.storage/tinder-universitario.firebasestorage.app'));if(!r)throw Error('required-rules-not-published');
  const rules=await read('https://firebaserules.googleapis.com/v1/'+r.rulesetName);const normalize=s=>s.replace(/\r\n/g,'\n').trim();if(normalize(rules.source?.files?.map(f=>f.content).join('\n')??'')!==normalize(expected[kind]))throw Error('published-rules-mismatch');
 }
}
async function io(bucket){
 const read=await readClient(),token=await sessionToken();
 const write=async(url,method,body,contentType='application/json')=>{
  const u=new URL(url),firestore=u.origin==='https://firestore.googleapis.com'&&u.pathname===`/v1/projects/${PROJECT}/databases/(default)/documents:commit`,storage=u.origin==='https://storage.googleapis.com'&&(u.pathname===`/upload/storage/v1/b/${bucket}/o`||u.pathname.startsWith(`/storage/v1/b/${bucket}/o/`));
  if(!((firestore&&method==='POST')||(storage&&['POST','PATCH'].includes(method))))throw Error('write-scope-denied');
  const response=await fetch(u,{method,headers:{Authorization:'Bearer '+token,'Content-Type':contentType},body:Buffer.isBuffer(body)?body:JSON.stringify(body),signal:AbortSignal.timeout(45000),redirect:'error'});
  if(!response.ok){await response.body?.cancel();throw Error('operator-http-'+response.status);}return response.json();
 };
 const get=async url=>{try{return await read(url);}catch(e){if(e.message.startsWith('read-http-404'))return null;throw e;}};
 return {read,get,write,commit:async writes=>write(root+':commit','POST',{writes})};
}
export async function migrate({plan,backup,apply,maintenance,clientFactory=io}){
 assertExecution({apply,maintenance,kind:'migrate'});
 if(plan.project!==PROJECT||plan.sourceSha256!==sha(canonical(backup)))throw Error('plan-backup-mismatch');
 const client=await clientFactory(plan.bucket),state=await client.get(marker);
 if(['committed','revoked'].includes(value(state?.fields?.state))){if(value(state.fields.sourceSha256)!==plan.sourceSha256)throw Error('different-migration');return {idempotent:true};}
 await assertRules(client.read,'maintenance');
 const bucketPolicy=await client.read(`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/iam`);
 if(bucketPolicy.bindings?.some(b=>b.members?.some(m=>['allUsers','allAuthenticatedUsers'].includes(m))))throw Error('public-bucket-iam-review-required');
 if(state&&value(state.fields.sourceSha256)!==plan.sourceSha256)throw Error('different-migration');
 const accounts=await client.read(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet?maxResults=1000&fields=users(localId,disabled),nextPageToken`);
 const identities=(accounts.users??[]).map(u=>({uid:u.localId,disabled:!!u.disabled})).sort((a,b)=>a.uid.localeCompare(b.uid));
 if(accounts.nextPageToken||canonical(identities)!==canonical([...plan.users].sort((a,b)=>a.uid.localeCompare(b.uid))))throw Error('auth-changed-new-backup-required');
 const inventory=await client.read(`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o?versions=true&maxResults=1000`);
 const inventoryKey=objects=>objects.map(o=>[o.name,o.generation,o.metageneration]).sort((a,b)=>canonical(a).localeCompare(canonical(b)));
 const stagedTargets=new Set(plan.photos.map(p=>p.target));
 const actualObjects=inventoryKey((inventory.items??[]).filter(o=>!stagedTargets.has(o.name)));
 const expectedObjects=inventoryKey(backup.storage.objects??backup.storage.files.map(f=>f.metadata));
 if(inventory.nextPageToken||canonical(actualObjects)!==canonical(expectedObjects))throw Error('storage-changed-new-backup-required');
 const snapshot=await captureFirestore(client.read);
 const actual=snapshot.documents.filter(d=>d.name!==marker.replace('https://firestore.googleapis.com/v1/',''));
 if(canonical(actual)!==canonical(plan.sourceDocuments))throw Error('source-changed-new-backup-required');
 if(!state)await client.commit([{update:{name:marker.replace('https://firestore.googleapis.com/v1/',''),fields:encode({state:'staging',sourceSha256:plan.sourceSha256,createdAt:new Date()}).mapValue.fields},currentDocument:{exists:false}}]);
 const generations={};
 for(const photo of plan.photos){
  const source=backup.storage.files.find(f=>f.metadata.name===photo.source&&f.metadata.generation===photo.sourceGeneration);const bytes=Buffer.from(source.bytesBase64,'base64');if(sha(bytes)!==photo.sha256)throw Error('source-checksum');
  const old=await client.read(`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o/${encodeURIComponent(photo.source)}?projection=full`);
  if(old.acl?.some(a=>['allUsers','allAuthenticatedUsers'].includes(a.entity)))throw Error('public-legacy-object-review-required');
  if(old.generation!==photo.sourceGeneration||old.metageneration!==photo.sourceMetageneration||old.md5Hash!==source.metadata.md5Hash)throw Error('source-object-changed');
  const target=`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o/${encodeURIComponent(photo.target)}`;
  let m=await client.get(target+'?projection=full');
  if(!m){const q=new URLSearchParams({uploadType:'media',name:photo.target,ifGenerationMatch:'0',...(!backup.storage.buckets[0].iamConfiguration?.uniformBucketLevelAccess?.enabled?{predefinedAcl:'private'}:{})});m=await client.write(`https://storage.googleapis.com/upload/storage/v1/b/${plan.bucket}/o?${q}`,'POST',bytes,photo.mime);}
  m=await client.read(target+'?projection=full');if(m.acl?.some(a=>['allUsers','allAuthenticatedUsers'].includes(a.entity)))throw Error('public-target-object');
  if(Number(m.size)!==photo.size||m.contentType!==photo.mime||m.metadata?.firebaseStorageDownloadTokens)throw Error('target-object-mismatch');
  const copy=await client.read(target+'?alt=media&generation='+m.generation,undefined,{binary:true});if(sha(copy)!==photo.sha256)throw Error('target-checksum');
  generations[photo.target]=m.generation;
 }
 const current=await client.read(marker),writes=firestoreWrites(plan,generations);
 writes.push({update:{name:marker.replace('https://firestore.googleapis.com/v1/',''),fields:encode({state:'committed',sourceSha256:plan.sourceSha256,completedAt:new Date()}).mapValue.fields},currentDocument:{updateTime:current.updateTime}});
 await client.commit(writes);return {migrated:plan.users.length,photos:plan.photos.length,grants:0};
}
export async function revoke({plan,apply,maintenance,clientFactory=io}){
 assertExecution({apply,maintenance,kind:'revoke'});const client=await clientFactory(plan.bucket);await assertRules(client.read,'strict');const state=await client.read(marker);
 if(value(state.fields.sourceSha256)!==plan.sourceSha256||!['committed','revoked'].includes(value(state.fields.state)))throw Error('migration-not-committed');
 // Confirmar referencias y pruebas actuales antes de revocar; nunca borrar objetos originales.
 for(const p of plan.profiles){const d=await client.read(root+'/users/'+p.uid);if(canonical(value(d.fields.photoUrls))!==canonical(p.paths)||value(d.fields.mainPhotoUrl)!==value(p.patch.mainPhotoUrl))throw Error('references-changed');}
 for(const photo of plan.photos){const proof=await client.read(root+'/profilePhotoAssets/'+photo.uid+'.'+photo.target.split('/')[2]);const asset=await client.read(`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o/${encodeURIComponent(photo.target)}`);const data=await client.read(`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o/${encodeURIComponent(photo.target)}?alt=media&generation=${asset.generation}`,undefined,{binary:true});if(value(proof.fields.sha256)!==photo.sha256||value(proof.fields.generation)!==asset.generation||sha(data)!==photo.sha256||asset.metadata?.firebaseStorageDownloadTokens)throw Error('private-copy-not-verified');}
 for(const photo of plan.photos){const url=`https://storage.googleapis.com/storage/v1/b/${plan.bucket}/o/${encodeURIComponent(photo.source)}`;let m=await client.read(url);if(m.generation!==photo.sourceGeneration)throw Error('source-generation-changed');const currentTokens=(m.metadata?.firebaseStorageDownloadTokens??'').split(',').filter(Boolean),tokens=[...new Set([...(photo.legacyTokens??[]),...currentTokens])];
  if(currentTokens.length||m.cacheControl!=='private, no-store')m=await client.write(url+`?ifGenerationMatch=${m.generation}&ifMetagenerationMatch=${m.metageneration}`,'PATCH',{metadata:{...(m.metadata??{}),firebaseStorageDownloadTokens:null},cacheControl:'private, no-store'});
  const fresh=await client.read(url);if(fresh.metadata?.firebaseStorageDownloadTokens)throw Error('token-revocation-incomplete');
  for(const token of tokens){const r=await fetch(`https://firebasestorage.googleapis.com/v0/b/${plan.bucket}/o/${encodeURIComponent(photo.source)}?alt=media&token=${encodeURIComponent(token)}`,{method:'HEAD',signal:AbortSignal.timeout(15000),redirect:'error'});if(![401,403,404].includes(r.status))throw Error('old-token-still-usable-or-unverified');}
 }
 await client.commit([{update:{name:state.name,fields:{state:encode('revoked')}},updateMask:{fieldPaths:['state']},currentDocument:{updateTime:state.updateTime}}]);return {revoked:true,deleted:0};
}
export async function bootstrap({uid,email,reviewConfirmed,apply,bucket}){
 assertExecution({apply,kind:'bootstrap'});if(!/^[A-Za-z0-9_-]{1,128}$/.test(uid??'')||typeof email!=='string')throw Error('confirmed-account-required');const client=await io(bucket);await assertRules(client.read,'strict');const state=await client.read(marker);if(value(state.fields.state)!=='revoked')throw Error('revocation-required-before-bootstrap');
 const [access,registry,profile,accounts]=await Promise.all([client.read(root+'/accountAccess/'+uid),client.read(root+'/administration/roles'),client.read(root+'/users/'+uid),client.read(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet?maxResults=1000&fields=users(localId,email,emailVerified,disabled),nextPageToken`)]);
 if(accounts.nextPageToken)throw Error('account-pagination-review-required');
 const writes=bootstrapWrites({uid,email,authUser:accounts.users?.find(u=>u.localId===uid),access,registry,profile,reviewConfirmed});if(writes.length)await client.commit(writes);return {bootstrap:writes.length>0,idempotent:!writes.length};
}
