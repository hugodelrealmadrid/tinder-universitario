// Operaciones de corte aditivas. Importar este módulo nunca escribe ni consulta red.
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {verifiedBackup,createOperatorClient} from './operator.mjs';
import {canonical,sha,saveEncrypted,loadEncrypted,privateDirectory} from './private-backup.mjs';
import {value,encode} from './migration-plan.mjs';
const PROJECT='tinder-universitario',BUCKET='tinder-universitario.firebasestorage.app',root=`projects/${PROJECT}/databases/(default)/documents/`;
const need=(ok,code)=>{if(!ok)throw Error(code);};
const field=(doc,key)=>value(doc?.fields?.[key]);
export function tokenPlan(backup){need(backup.project===PROJECT,'wrong-project');return {format:'ligo-token-plan-v1',project:PROJECT,bucket:BUCKET,sourceSha256:sha(canonical(backup)),objects:backup.storage.files.filter(f=>f.metadata.metadata?.firebaseStorageDownloadTokens).map(f=>{need(f.metadata.bucket===BUCKET&&/^(profile_photos|chat_media|university_cards)\//.test(f.metadata.name),'unexpected-token-path');return {name:f.metadata.name,generation:f.metadata.generation,metageneration:f.metadata.metageneration,size:f.metadata.size,sha256:f.sha256,tokens:f.metadata.metadata.firebaseStorageDownloadTokens.split(',').filter(Boolean)};})};}
export async function revokePlannedTokens({authorization,plan,backup,client,head=async url=>{const r=await fetch(url,{method:'HEAD',redirect:'error',signal:AbortSignal.timeout(20000)});await r.body?.cancel();return r.status;}}){
 need(authorization==='LIGO_REVOKE_ONLY_PLANNED_TOKENS','explicit-revocation-authorization-required');need(canonical(plan)===canonical(tokenPlan(backup)),'plan-backup-mismatch');const policy=await client.read(`https://storage.googleapis.com/storage/v1/b/${BUCKET}/iam`);need(!policy.bindings?.some(b=>b.members?.some(m=>['allUsers','allAuthenticatedUsers'].includes(m))),'public-bucket-iam-review-required');let changed=0;
 for(const o of plan.objects){const url=`https://storage.googleapis.com/storage/v1/b/${BUCKET}/o/${encodeURIComponent(o.name)}`;const m=await client.read(url+'?projection=full');need(!m.acl?.some(a=>['allUsers','allAuthenticatedUsers'].includes(a.entity)),'public-object-acl-review-required');need(m.generation===o.generation&&String(m.size)===String(o.size),'object-changed');const bytes=await client.read(url+'?alt=media&generation='+o.generation,undefined,{binary:true});need(sha(bytes)===o.sha256,'object-checksum-mismatch');
  if(m.metadata?.firebaseStorageDownloadTokens||m.cacheControl!=='private, no-store'){
   need(m.metageneration===o.metageneration,'metadata-changed-new-plan-required');
   await client.write(url+`?ifGenerationMatch=${encodeURIComponent(o.generation)}&ifMetagenerationMatch=${encodeURIComponent(o.metageneration)}`,'PATCH',{cacheControl:'private, no-store',metadata:{...(m.metadata??{}),firebaseStorageDownloadTokens:null}});changed++;
  }
  const fresh=await client.read(url);need(!fresh.metadata?.firebaseStorageDownloadTokens&&fresh.cacheControl==='private, no-store'&&fresh.generation===o.generation,'revocation-incomplete');const after=await client.read(url+'?alt=media&generation='+o.generation,undefined,{binary:true});need(sha(after)===o.sha256,'post-revocation-checksum-mismatch');
  need([401,403,404].includes(await head(`https://storage.googleapis.com/${BUCKET}/${encodeURIComponent(o.name)}?generation=${o.generation}`)),'raw-storage-still-public');
  for(const token of o.tokens)need([401,403,404].includes(await head(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(o.name)}?alt=media&token=${encodeURIComponent(token)}`)),'old-token-still-active');
 }
 return {project:PROJECT,checked:plan.objects.length,metadataPatches:changed,deleted:0,bytesChanged:0};
}
export function activationWrites(backup,actorId,requestId){
 need(backup.project===PROJECT&&/^[A-Za-z0-9_-]{1,128}$/.test(actorId??'')&&/^[A-Za-z0-9_-]{1,128}$/.test(requestId??''),'invalid-activation');const docs=backup.firestore.documents,doc=path=>docs.find(d=>d.name===root+path),a=doc('accountAccess/'+actorId),auth=backup.auth.users.find(u=>u.localId===actorId);
 need(auth&&!auth.disabled&&auth.emailVerified===true&&field(a,'role')==='superadmin'&&field(a,'verificationStatus')==='approved'&&field(a,'suspended')===false,'approved-superadmin-required');
 need(!doc('platformSettings/academic'),'academic-policy-already-exists');
 const universities=docs.filter(d=>d.name.startsWith(root+'universities/')&&field(d,'isActive')===true).map(d=>d.name.split('/').at(-1));
 need(docs.some(d=>d.name.startsWith(root+'careers/')&&field(d,'isActive')===true&&universities.includes(field(d,'universityId'))),'create-active-university-and-linked-career-first');
 return [{verify:a.name,currentDocument:{updateTime:a.updateTime}},{update:{name:root+'platformSettings/academic',fields:encode({multiUniversityEnabled:true,activationId:requestId}).mapValue.fields},currentDocument:{exists:false},updateTransforms:['legacyBefore','createdAt','updatedAt'].map(fieldPath=>({fieldPath,setToServerValue:'REQUEST_TIME'}))},{update:{name:root+'administrativeAudit/'+requestId,fields:encode({actorId,targetId:'platformSettings/academic',action:'academic_policy_activation',reasonCode:'explicit_owner_authorization',requestId}).mapValue.fields},currentDocument:{exists:false},updateTransforms:[{fieldPath:'at',setToServerValue:'REQUEST_TIME'}]}];
}
async function main(){const [mode,backupDir,arg,...flags]=process.argv.slice(2);need(['plan','revoke','activate-academics'].includes(mode)&&backupDir,'usage-plan-revoke-activate-academics');
 const {data,manifest}=verifiedBackup(backupDir);
 if(mode==='plan'){const plan=tokenPlan(data),dir=fileURLToPath(new URL('../../build/ligo-cutover-plans/'+new Date().toISOString().replace(/[:.]/g,'-')+'/',import.meta.url));privateDirectory(dir);const integrity=saveEncrypted(dir+'tokens.dpapi',plan);writeFileSync(dir+'verified.json',JSON.stringify({project:PROJECT,backup:backupDir,sourceBackupSha256:manifest.cipherSha256,objects:plan.objects.length,...integrity},null,2),{flag:'wx'});console.log(JSON.stringify({planDirectory:dir,objects:plan.objects.length,remoteWrites:0}));return;}
 need(flags.includes('--authorized-production-write'),'explicit-production-authorization-required');need(Date.now()-Date.parse(data.completedAt)<15*60*1000,'fresh-backup-required');
 if(mode==='revoke'){need(arg,'encrypted-plan-directory-required');const proof=JSON.parse(readFileSync(arg+'/verified.json'));need(proof.sourceBackupSha256===manifest.cipherSha256&&sha(readFileSync(arg+'/tokens.dpapi'))===proof.cipherSha256,'plan-integrity-mismatch');const plan=loadEncrypted(arg+'/tokens.dpapi'),client=await createOperatorClient(BUCKET);const result=await revokePlannedTokens({authorization:'LIGO_REVOKE_ONLY_PLANNED_TOKENS',plan,backup:data,client});const receipt={...result,completedAt:new Date().toISOString()};writeFileSync(arg+'/revoke-receipt-'+Date.now()+'.json',JSON.stringify(receipt,null,2),{flag:'wx'});console.log(JSON.stringify(receipt));return;}
 const writes=activationWrites(data,arg,'ligo_activation_'+randomUUID().replaceAll('-',''));const client=await createOperatorClient(BUCKET);await client.commit(writes);console.log(JSON.stringify({academicPolicyActivated:true,historicalDocumentsWritten:0,rolesChanged:0}));
}
if(process.argv[1]&&import.meta.url===new URL('file:///'+process.argv[1].replaceAll('\\','/')).href)main().catch(e=>{console.error(JSON.stringify({completed:false,code:/^[a-z0-9-]+$/.test(e.message)?e.message:'operation-failed-no-sensitive-details'}));process.exitCode=1;});
