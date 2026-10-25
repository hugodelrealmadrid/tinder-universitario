import {canonical,sha} from './private-backup.mjs';
export const PROJECT='tinder-universitario',MIGRATION='five-phases-v1';
const prefix=`projects/${PROJECT}/databases/(default)/documents/`;
export const value=x=>x?.stringValue??x?.booleanValue??(x?.integerValue!==undefined?Number(x.integerValue):x?.timestampValue!==undefined?new Date(x.timestampValue):x?.nullValue!==undefined?null:x?.arrayValue?x.arrayValue.values?.map(value)??[]:undefined);
export function encode(v){if(v===null||v===undefined)return {nullValue:null};if(v instanceof Date)return {timestampValue:v.toISOString()};if(Array.isArray(v))return {arrayValue:{values:v.map(encode)}};if(typeof v==='boolean')return {booleanValue:v};if(typeof v==='number')return {integerValue:String(v)};if(typeof v==='string')return {stringValue:v};return {mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,encode(x)]))}};}
const id=s=>{if(!/^[A-Za-z0-9_-]{1,128}$/.test(s??''))throw Error('invalid-identity');return s;};
export function legacyPath(url,uid,bucket){
 if(typeof url!=='string')throw Error('invalid-photo-reference');
 let path=url;
 if(!url.startsWith('profile_photos/')){const u=new URL(url);const base='/v0/b/'+bucket+'/o/';if(u.origin!=='https://firebasestorage.googleapis.com'||u.username||u.password||u.hash||!u.pathname.startsWith(base))throw Error('foreign-photo-url');path=decodeURIComponent(u.pathname.slice(base.length));}
 if(!path.startsWith('profile_photos/'+id(uid)+'/')||path.split('/').length!==3||path.includes('..')||path.includes('\\'))throw Error('foreign-photo-owner');return path;
}
export function buildPlan(backup){
 if(backup.project!==PROJECT||backup.format!=='tinder-private-backup-v1')throw Error('wrong-backup-project');
 const docs=new Map(backup.firestore.documents.map(d=>[d.name.slice(prefix.length),d]));
 if([...docs.keys()].some(k=>k.startsWith('accountAccess/'))||docs.has('administration/roles')||docs.has('migrationState/'+MIGRATION))throw Error('already-modernized-requires-review');
 const bucket=backup.storage.buckets?.[0]?.name;
 if(backup.storage.buckets?.length!==1||!bucket)throw Error('bucket-review-required');
 const now=new Date(backup.completedAt),users=backup.auth.users,authIds=new Set(users.map(u=>id(u.localId))),photos=[],profiles=[];
 const latest=new Map();for(const f of backup.storage.files){if(f.metadata.bucket!==bucket)throw Error('foreign-bucket');const old=latest.get(f.metadata.name);if(!old||BigInt(f.metadata.generation)>BigInt(old.metadata.generation))latest.set(f.metadata.name,f);}
 for(const [name,doc]of docs){if(!/^users\/[^/]+$/.test(name))continue;const uid=id(name.split('/')[1]);if(!authIds.has(uid))throw Error('profile-without-auth');
  const old=doc.fields??{},references=value(old.photoUrls)??[];if(!Array.isArray(references)||references.length>6)throw Error('photo-list-review-required');const paths=[];
  for(const ref of references){const path=legacyPath(ref,uid,bucket),file=latest.get(path);if(!file)throw Error('missing-photo');const bytes=Buffer.from(file.bytesBase64,'base64');if(sha(bytes)!==file.sha256||bytes.length!==Number(file.metadata.size))throw Error('backup-photo-corrupt');
   const target='profile_photos/'+uid+'/migrated_'+sha(path+'@'+file.metadata.generation).slice(0,24);paths.push(target);
   if(!photos.some(p=>p.target===target))photos.push({uid,source:path,target,sha256:file.sha256,mime:file.metadata.contentType,size:bytes.length,sourceGeneration:file.metadata.generation,sourceMetageneration:file.metadata.metageneration,legacyTokens:(file.metadata.metadata?.firebaseStorageDownloadTokens??'').split(',').filter(Boolean)});
  }
  const originalMain=value(old.mainPhotoUrl);const main=originalMain?paths[references.indexOf(originalMain)]:null;if(originalMain&&!main)throw Error('main-photo-not-in-gallery');
  const changed={...old,datingAllowed:encode(false),role:encode('user'),photoUrls:encode(paths),mainPhotoUrl:encode(main)};
  const birth=value(old.birthDate);let age=null;if(birth instanceof Date){age=now.getUTCFullYear()-birth.getUTCFullYear()-((now.getUTCMonth()<birth.getUTCMonth()||(now.getUTCMonth()===birth.getUTCMonth()&&now.getUTCDate()<birth.getUTCDate()))?1:0);}
  const card={age:encode(age)};for(const k of ['firstName','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'])card[k]=changed[k]??encode(null);
  profiles.push({uid,source:doc,patch:{datingAllowed:encode(false),role:encode('user'),photoUrls:encode(paths),mainPhotoUrl:encode(main)},card,gallery:{...card,photoUrls:encode(paths)},paths});
 }
 if(profiles.length!==users.length)throw Error('auth-profile-mismatch');
 if([...latest.values()].some(f=>!photos.some(p=>p.source===f.metadata.name)))throw Error('unreferenced-or-nonphoto-object-review-required');
 const legacyMessages=[...docs].filter(([k])=>/^matches\/[^/]+\/messages\/[^/]+$/.test(k));
 if(legacyMessages.some(([,d])=>!d.fields?.senderId?.stringValue||!d.fields?.text?.stringValue||!d.fields?.createdAt?.timestampValue||!['text',undefined].includes(d.fields?.type?.stringValue)||d.fields?.mediaPath||d.fields?.mediaUrl))throw Error('legacy-messages-review-required');
 return {format:'tinder-migration-plan-v1',project:PROJECT,migration:MIGRATION,bucket,sourceSha256:sha(canonical(backup)),profiles,users:users.map(u=>({uid:u.localId,disabled:!!u.disabled})),photos,sourceDocuments:[...backup.firestore.documents].sort((a,b)=>a.name.localeCompare(b.name)),preserved:{auth:users.length,matches:[...docs.keys()].filter(k=>/^matches\/[^/]+$/.test(k)).length,messages:legacyMessages.length,preferences:[...docs.keys()].filter(k=>/^preferences\/[^/]+$/.test(k)).length}};
}
export function firestoreWrites(plan,generations){
 const source=new Map(plan.sourceDocuments.map(d=>[d.name,d])),writes=[];
 function put(path,fields,patch=false){const name=prefix+path,old=source.get(name);writes.push({update:{name,fields},...(patch?{updateMask:{fieldPaths:Object.keys(fields)}}:{}),currentDocument:old?{updateTime:old.updateTime}:{exists:false}});}
 for(const u of plan.users)put('accountAccess/'+u.uid,encode({role:'user',verificationStatus:'pending',suspended:u.disabled,latestRequestId:null,createdAt:new Date(),updatedAt:new Date()}).mapValue.fields);
 for(const p of plan.profiles){put('users/'+p.uid,p.patch,true);put('profilePhotoManifests/'+p.uid,encode({paths:p.paths}).mapValue.fields);put('discoveryCards/'+p.uid,p.card);put('matchProfiles/'+p.uid,p.gallery);put('discoveryIndex/'+p.uid,{isActive:p.card.isActive,updatedAt:p.card.updatedAt});}
 for(const p of plan.photos){const generation=generations[p.target];if(!generation)throw Error('copy-not-verified');put('profilePhotoAssets/'+p.uid+'.'+p.target.split('/')[2],encode({uid:p.uid,path:p.target,mime:p.mime,size:p.size,sha256:p.sha256,generation,state:'published'}).mapValue.fields);}
 put('administration/roles',encode({superadminIds:[],updatedAt:new Date()}).mapValue.fields);
 if(writes.length>450)throw Error('atomic-write-limit');return writes;
}
export function bootstrapWrites({uid,email,authUser,access,registry,profile,reviewConfirmed}){
 id(uid);if(!reviewConfirmed||!email||!authUser||authUser.localId!==uid||authUser.email!==email||!authUser.emailVerified||authUser.disabled||/(@demo\.test$|@example\.|@demo\.)/i.test(email)||uid.startsWith('demo_')||/\.(test|invalid|localhost)$/i.test(email))throw Error('confirmed-real-verified-account-required');
 const a=access.fields,r=value(registry.fields.superadminIds)??[];
 if(r.length===1&&r[0]===uid&&value(a.role)==='superadmin'&&value(a.verificationStatus)==='approved'&&value(a.suspended)===false)return [];
 if(r.length||value(a.role)!=='user'||value(a.verificationStatus)!=='pending'||value(a.suspended)!==false)throw Error('bootstrap-consumed-or-account-ineligible');
 const patch=(d,fields)=>({update:{name:d.name,fields:encode(fields).mapValue.fields},updateMask:{fieldPaths:Object.keys(fields)},currentDocument:{updateTime:d.updateTime}});
 return [patch(access,{role:'superadmin',verificationStatus:'approved',updatedAt:new Date()}),patch(registry,{superadminIds:[uid],updatedAt:new Date()}),patch(profile,{datingAllowed:true}),{update:{name:prefix+'administrativeAudit/first_superadmin_bootstrap',fields:encode({actorId:'authorized_operator',targetId:uid,action:'bootstrap',reasonCode:'explicit_identity_and_university_review',requestId:null,at:new Date()}).mapValue.fields},currentDocument:{exists:false}}];
}
