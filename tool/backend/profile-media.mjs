import {Timestamp,FieldValue} from 'firebase-admin/firestore';
import {AccessError} from './verification.mjs';
import {validateMedia} from './media-validation.mjs';
import {sealPrivateObject} from './private-object.mjs';
import {digest,removeAsset} from './chat-upload.mjs';
export function photoPath(path){const p=typeof path==='string'?path.split('/'):[];if(p.length!==3||p[0]!=='profile_photos'||!p.slice(1).every(s=>/^[A-Za-z0-9_-]{1,128}$/.test(s)))throw new AccessError('invalid-argument');return p;}
const manifest=(b,uid)=>b.db.doc('profilePhotoManifests/'+uid);
export const photoAsset=(b,path)=>{const p=photoPath(path);return b.db.doc('profilePhotoAssets/'+p[1]+'.'+p[2]);};
async function approved(b,tx,uid){const a=await b.actor(tx,uid);if(a.verificationStatus!=='approved')throw new AccessError('permission-denied');}
export async function uploadPhoto(b,uid,path,bytes,mime){
 const p=photoPath(path);if(uid!==p[1])throw new AccessError('permission-denied');
 await b.db.runTransaction(tx=>approved(b,tx,uid));await validateMedia(bytes,mime);
 const ref=photoAsset(b,path),file=b.bucket.file(path);
 await b.db.runTransaction(async tx=>{await approved(b,tx,uid);const a=await tx.get(ref),m=await tx.get(manifest(b,uid));if(a.exists||(m.data()?.paths?.length??0)>=12)throw new AccessError('conflict');tx.create(ref,{uid,path,mime,size:bytes.length,sha256:digest(bytes),state:'uploading',expiresAt:Timestamp.fromMillis(Date.now()+3600000)});});
 try{await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:mime,cacheControl:'private, no-store'}});await sealPrivateObject(file);const [meta]=await file.getMetadata();
 await b.db.runTransaction(async tx=>{await approved(b,tx,uid);const a=await tx.get(ref),m=await tx.get(manifest(b,uid));if(a.data()?.state!=='uploading'||(m.data()?.paths?.length??0)>=12)throw new AccessError('conflict');tx.update(ref,{state:'ready',generation:meta.generation});tx.set(manifest(b,uid),{paths:[...new Set([...(m.data()?.paths??[]),path])]});});
 }catch(e){await ref.update({expiresAt:Timestamp.now()}).catch(()=>{});throw e;}return {path};
}
export async function deletePhoto(b,uid,path){const p=photoPath(path);if(uid!==p[1])throw new AccessError('permission-denied');const ref=photoAsset(b,path);
 const a=await b.db.runTransaction(async tx=>{await approved(b,tx,uid);const asset=await tx.get(ref),profile=await tx.get(b.db.doc('users/'+uid)),m=await tx.get(manifest(b,uid));if(profile.data()?.photoUrls?.includes(path))throw new AccessError('conflict');if(!asset.exists)return null;
 if(asset.data().path!==path)throw new AccessError('permission-denied');tx.set(manifest(b,uid),{paths:(m.data()?.paths??[]).filter(v=>v!==path)});tx.update(ref,{state:'deleting',expiresAt:Timestamp.now()});return asset.data();});if(a)await removeAsset(b,ref,a);return {deleted:true};}
// La autorización de otras personas se delega a las MISMAS reglas de las fichas.
// No duplicar aquí filtros de edad/carrera, bloqueos, visibilidad o matches.
export async function permittedCard(b,token,uid,path){
 const claims=await b.auth.verifyIdToken(token,true);if(claims.uid!==uid)throw new AccessError('permission-denied');
 const owner=photoPath(path)[1],project=b.db.projectId,host=process.env.FIRESTORE_EMULATOR_HOST;
 const origin=b.firestoreOrigin;
 const remote=origin==='https://firestore.googleapis.com'&&!project.startsWith('demo-')&&!host;
 const local=project.startsWith('demo-')&&(/^127\.0\.0\.1:(8088|8188)$/.test(host)||(project==='demo-ligo-staging'&&host==='127.0.0.1:8288')||(project==='demo-ligo-validation'&&host==='127.0.0.1:8488'));
 if(!remote&&!local)throw new AccessError('permission-denied');
 const base=remote?origin:`http://${host}`;
 for(const collection of ['discoveryCards','matchProfiles']){
  const r=await fetch(`${base}/v1/projects/${project}/databases/(default)/documents/${collection}/${owner}`,{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(10000)});
  if(r.status!==200){await r.body?.cancel();continue;}
  const d=(await r.json()).fields;
  if(collection==='discoveryCards'&&d.mainPhotoUrl?.stringValue===path)return;
  if(collection==='matchProfiles'&&d.photoUrls?.arrayValue?.values?.some(v=>v.stringValue===path))return;
 }
 throw new AccessError('permission-denied');
}
export async function readPhoto(b,uid,path,token){
 const p=photoPath(path),ref=photoAsset(b,path);
 const check=async()=>{
  const a=await b.db.runTransaction(async tx=>{await approved(b,tx,uid);if(p[1]!==uid)await approved(b,tx,p[1]);
   const profile=(await tx.get(b.db.doc('users/'+p[1]))).data(),asset=(await tx.get(ref)).data();
   if(!asset||!['ready','published'].includes(asset.state)||asset.path!==path)throw new AccessError('permission-denied');
   if(!profile?.photoUrls?.includes(path)&&!(p[1]===uid&&asset.state==='ready'&&asset.expiresAt.toMillis()>Date.now()))throw new AccessError('permission-denied');return asset;});
  if(p[1]!==uid)await permittedCard(b,token,uid,path);return a;
 };
 const asset=await check();
 const result=await verifiedPhotoBytes(b,path,asset);
 await check();
 return result;
}

async function verifiedPhotoBytes(b,path,asset){
 const file=b.bucket.file(path),[meta]=await file.getMetadata();
 if(meta.generation!==asset.generation||meta.contentType!==asset.mime||Number(meta.size)!==asset.size)throw new AccessError('invalid-media');
 const [bytes]=await file.download();
 if(digest(bytes)!==asset.sha256)throw new AccessError('invalid-media');
 return {bytes,contentType:asset.mime};
}

// Únicamente referencias privadas del propietario; nunca URLs ni carnets.
export function dossierPhotoPaths(profile,uid){
 const listed=Array.isArray(profile?.photoUrls)?profile.photoUrls:[];
 const owned=listed.filter(path=>{
  try{return photoPath(path)[1]===uid;}catch{return false;}
 });
 return [...new Set([...(owned.includes(profile?.mainPhotoUrl)?[profile.mainPhotoUrl]:[]),...owned])].slice(0,6);
}

export async function readDossierPhoto(b,actorId,path){
 const check=async(previous)=>b.db.runTransaction(async tx=>{
  const actor=await b.actor(tx,actorId,true);
  if(actor.verificationStatus!=='approved')throw new AccessError('permission-denied');
  const [,owner]=photoPath(path);
  const profile=(await tx.get(b.db.doc('users/'+owner))).data();
  const asset=(await tx.get(photoAsset(b,path))).data();
  if(!dossierPhotoPaths(profile,owner).includes(path)||asset?.uid!==owner||asset.path!==path||
    !['ready','published'].includes(asset.state)||!['image/jpeg','image/png','image/webp'].includes(asset.mime)){
   throw new AccessError('permission-denied');
  }
  if(previous){
   if(asset.generation!==previous.generation||asset.sha256!==previous.sha256||
      asset.size!==previous.size||asset.mime!==previous.mime)throw new AccessError('permission-denied');
   b.audit(tx,actorId,owner,'profile_photo_viewed','administrative_dossier',null,'success');
  }
  return asset;
 });
 const asset=await check();
 const result=await verifiedPhotoBytes(b,path,asset);
 await check(asset);
 return result;
}
