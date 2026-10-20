import {Timestamp,FieldValue} from 'firebase-admin/firestore';
import {createHash} from 'node:crypto';
import {AccessError} from './verification.mjs';
import {sealPrivateObject} from './private-object.mjs';
import {validateMedia} from './media-validation.mjs';
export const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
export function chatPath(path){const p=typeof path==='string'?path.split('/'):[];if(p.length!==4||p[0]!=='chat_media'||!/^[A-Za-z0-9_-]{1,128}[.][A-Za-z0-9_-]{1,128}$/.test(p[1])||!p.slice(2).every(s=>/^[A-Za-z0-9_-]{1,128}$/.test(s)))throw new AccessError('invalid-argument');return p;}
export function assetRef(backend,path){const p=chatPath(path);return backend.db.doc('chatUploads/'+p[1]+'.'+p[3]);}
export async function chatAccess(backend,tx,uid,path){
 const p=chatPath(path),pair=(await tx.get(backend.db.doc('matches/'+p[1]))).data();
 if(pair?.users?.length!==2||pair.users[0]>=pair.users[1]||pair.users.join('.')!==p[1]||!pair.users.includes(uid)||!pair.users.includes(p[2])||pair.isActive!==true)throw new AccessError('permission-denied');
 for(const member of pair.users){const a=await backend.actor(tx,member);if(a.verificationStatus!=='approved')throw new AccessError('permission-denied');}
 for(const key of [pair.users.join('.'),[...pair.users].reverse().join('.')])if((await tx.get(backend.db.doc('blocks/'+key))).exists)throw new AccessError('permission-denied');
 return p;
}
export async function uploadChat(backend,uid,path,bytes,mime){
 const p=chatPath(path);if(p[2]!==uid)throw new AccessError('permission-denied');
 await backend.db.runTransaction(tx=>chatAccess(backend,tx,uid,path));
 const validation=await validateMedia(bytes,mime),ref=assetRef(backend,path),file=backend.bucket.file(path);
 await backend.db.runTransaction(async tx=>{await chatAccess(backend,tx,uid,path);const [asset,message]=await Promise.all([tx.get(ref),tx.get(backend.db.doc('matches/'+p[1]+'/messages/'+p[3]))]);if(asset.exists||message.exists)throw new AccessError('conflict');
 tx.create(ref,{path,uid,matchId:p[1],type:validation.type,mime,size:bytes.length,sha256:digest(bytes),durationMs:validation.durationMs,state:'uploading',createdAt:FieldValue.serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+3600000)});});
 try{
  await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:mime,cacheControl:'private, no-store',metadata:{memberA:p[1].split('.')[0],memberB:p[1].split('.')[1]}}});
  await sealPrivateObject(file);const [meta]=await file.getMetadata();
  await backend.db.runTransaction(async tx=>{await chatAccess(backend,tx,uid,path);const a=(await tx.get(ref)).data();if(a?.state!=='uploading')throw new AccessError('conflict');tx.update(ref,{state:'ready',generation:meta.generation});});
 }catch(e){await ref.update({expiresAt:Timestamp.now()}).catch(()=>{});throw e;}
 return {uploaded:true};
}
export async function deleteChat(backend,uid,path){
 const p=chatPath(path);if(uid!==p[2])throw new AccessError('permission-denied');
 const ref=assetRef(backend,path);
 const a=await backend.db.runTransaction(async tx=>{const actor=await backend.actor(tx,uid);if(actor.verificationStatus!=='approved')throw new AccessError('permission-denied');
 const asset=await tx.get(ref),message=await tx.get(backend.db.doc('matches/'+p[1]+'/messages/'+p[3]));if(message.exists)throw new AccessError('permission-denied');
 if(!asset.exists)return null;if(asset.data().uid!==uid||asset.data().path!==path)throw new AccessError('permission-denied');tx.update(ref,{state:'deleting',expiresAt:Timestamp.now()});return asset.data();});
 if(a){await removeAsset(backend,ref,a);}return {deleted:true};
}
export async function removeAsset(backend,ref,a){
 try{await backend.bucket.file(a.path).delete(a.generation?{ifGenerationMatch:a.generation}:{});}catch(e){if(e.code!==404){await ref.update({expiresAt:Timestamp.fromMillis(Date.now()+60000),lastError:'cleanup-retry'});throw e;}}
 await ref.update({state:'deleted',expiresAt:FieldValue.delete()});
}
