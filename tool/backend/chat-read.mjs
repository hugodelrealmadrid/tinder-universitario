import {AccessError} from './verification.mjs';
import {chatAccess,chatPath,assetRef,digest} from './chat-upload.mjs';
export async function readChat(backend,uid,path,download=false){
 const p=chatPath(path),ref=assetRef(backend,path);
 const check=()=>backend.db.runTransaction(async tx=>{
  await chatAccess(backend,tx,uid,path);const a=(await tx.get(ref)).data(),m=(await tx.get(backend.db.doc('matches/'+p[1]+'/messages/'+p[3]))).data();
  if(!a||a.path!==path||a.uid!==p[2]||!['ready','published'].includes(a.state))throw new AccessError('permission-denied');
  if(m){if(m.mediaPath!==path||m.senderId!==p[2]||m.type!==a.type)throw new AccessError('permission-denied');}
  else if(uid!==p[2]||a.state!=='ready'||a.expiresAt.toMillis()<=Date.now())throw new AccessError('permission-denied');
  return a;
 });
 const asset=await check(),file=backend.bucket.file(path),[meta]=await file.getMetadata();
 if(meta.generation!==asset.generation||Number(meta.size)!==asset.size||meta.contentType!==asset.mime)throw new AccessError('invalid-media');
 if(!download)return {size:asset.size,contentType:asset.mime,durationMs:asset.durationMs};
 const [bytes]=await file.download();if(digest(bytes)!==asset.sha256)throw new AccessError('invalid-media');await check();
 return {bytes,contentType:asset.mime};
}
