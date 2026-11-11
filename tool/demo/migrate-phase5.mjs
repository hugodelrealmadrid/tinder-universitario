import {FieldValue,Timestamp} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {writeFile} from 'node:fs/promises';
import {emulatorServices} from '../backend/emulator.mjs';
import {VerificationBackend} from '../backend/verification.mjs';
import {validateMedia} from '../backend/media-validation.mjs';
import {sealPrivateObject} from '../backend/private-object.mjs';
import {digest,assetRef,chatPath} from '../backend/chat-upload.mjs';
import {photoAsset,photoPath} from '../backend/profile-media.mjs';
if(process.argv[2]!=='--revoke-demo-tokens')throw Error('Requiere --revoke-demo-tokens; nunca producción.');
const services=await emulatorServices(),{db,bucket}=services,b=new VerificationBackend(services);
const result={photos:0,chat:0,revokedTokens:0,oldUrlsDenied:0,quarantined:0,missingReferences:0};
const [objects]=await bucket.getFiles();const present=new Set(objects.map(f=>f.name));
for(const file of objects){if(!/^(profile_photos|chat_media)\//.test(file.name))continue;
 const [old]=await file.getMetadata();if(Number(old.size)>15*1024*1024)throw Error('Oversize legacy: revisar manualmente');
 const [bytes]=await file.download();let valid;try{valid=await validateMedia(bytes,old.contentType);}catch{result.quarantined++;}
 const oldTokens=(old.metadata?.firebaseStorageDownloadTokens??'').split(',').filter(Boolean);
 await sealPrivateObject(file);const [meta]=await file.getMetadata();
 for(const token of oldTokens){const response=await fetch(`http://127.0.0.1:9198/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${encodeURIComponent(token)}`);if(response.status===200)throw Error('Token antiguo sigue activo');await response.body?.cancel();result.revokedTokens++;result.oldUrlsDenied++;}
 if(file.name.startsWith('profile_photos/')){
  const p=photoPath(file.name),profile=(await db.doc('users/'+p[1]).get()).data();
  const referenced=profile?.photoUrls?.some(v=>legacyPath(v,p[1])===file.name);
  await photoAsset(b,file.name).set({uid:p[1],path:file.name,mime:meta.contentType,size:bytes.length,sha256:digest(bytes),generation:meta.generation,state:valid?(referenced?'published':'ready'):'quarantined',...(!referenced?{expiresAt:Timestamp.fromMillis(Date.now()+3600000)}:{})});result.photos++;
 }else{
  const p=chatPath(file.name),m=(await db.doc('matches/'+p[1]+'/messages/'+p[3]).get()).data();
  const published=m?.mediaPath===file.name&&m.senderId===p[2]&&m.type===valid?.type;
  await assetRef(b,file.name).set({uid:p[2],matchId:p[1],path:file.name,type:valid?.type??'invalid',mime:meta.contentType,size:bytes.length,sha256:digest(bytes),durationMs:valid?.durationMs??null,generation:meta.generation,state:valid?(published?'published':'ready'):'quarantined',...(!published?{expiresAt:Timestamp.fromMillis(Date.now()+3600000)}:{})});result.chat++;
 }
}
function legacyPath(value,uid){
 if(typeof value!=='string')throw Error('Referencia legacy inválida');if(value.startsWith('profile_photos/')){const p=photoPath(value);if(p[1]!==uid)throw Error('Propietario incorrecto');return value;}
 const u=new URL(value);if(u.origin!=='http://127.0.0.1:9198'||u.username||u.password||u.hash||!u.pathname.startsWith('/v0/b/'+bucket.name+'/o/'))throw Error('URL ajena: detener migración');
 const path=decodeURIComponent(u.pathname.slice(('/v0/b/'+bucket.name+'/o/').length));if(photoPath(path)[1]!==uid)throw Error('Foto ajena');return path;
}
const users=await db.collection('users').get();
for(const doc of users.docs){const old=doc.data(),photos=(old.photoUrls??[]).map(v=>legacyPath(v,doc.id));
 for(const path of photos)if(!present.has(path))throw Error('Foto referenciada ausente; restaurar antes de continuar');
 const main=old.mainPhotoUrl?legacyPath(old.mainPhotoUrl,doc.id):null;
 await db.runTransaction(async tx=>{const current=await tx.get(doc.ref);if(JSON.stringify(current.data().photoUrls)!==JSON.stringify(old.photoUrls))throw Error('Perfil concurrente: repetir migración');
 const card=db.doc('discoveryCards/'+doc.id),gallery=db.doc('matchProfiles/'+doc.id),c=await tx.get(card),g=await tx.get(gallery);
 tx.update(doc.ref,{photoUrls:photos,mainPhotoUrl:main});tx.set(db.doc('profilePhotoManifests/'+doc.id),{paths:photos});
 if(c.exists)tx.update(card,{mainPhotoUrl:main});if(g.exists)tx.update(gallery,{mainPhotoUrl:main,photoUrls:photos});});
}
const matches=await db.collection('matches').get();for(const match of matches.docs){const messages=await match.ref.collection('messages').get();for(const m of messages.docs)if(m.data().mediaPath&&!present.has(m.data().mediaPath))result.missingReferences++;}
await writeFile(new URL('../../audit-phase5-migration.json',import.meta.url),JSON.stringify(result,null,2));console.log(JSON.stringify(result));await deleteApp(services.app);
