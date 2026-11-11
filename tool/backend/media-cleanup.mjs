import {FieldValue,Timestamp,FieldPath} from 'firebase-admin/firestore';
import {assetRef,chatPath,removeAsset} from './chat-upload.mjs';
export async function cleanupMedia(b,now=Date.now()){
 for(const collection of ['chatUploads','profilePhotoAssets']){
  // Reconciliar también publicaciones que perdieron su referencia después de
  // vencer el staging (p. ej. cierre del cliente antes de pedir eliminación).
  const cursorRef=b.db.doc('maintenanceCursors/'+collection),cursor=(await cursorRef.get()).data()?.after;
  let published=b.db.collection(collection).where('state','==','published').orderBy(FieldPath.documentId());
  if(cursor)published=published.startAfter(cursor);
  const page=await published.limit(50).get();
  for(const doc of page.docs)await b.db.runTransaction(async tx=>{
   const v=(await tx.get(doc.ref)).data();if(v?.state!=='published')return;
   let referenced;
   if(collection==='chatUploads'){const p=chatPath(v.path),m=(await tx.get(b.db.doc('matches/'+p[1]+'/messages/'+p[3]))).data();referenced=m?.mediaPath===v.path&&m.senderId===v.uid&&m.type===v.type;}
   else {const user=(await tx.get(b.db.doc('users/'+v.uid))).data(),manifest=b.db.doc('profilePhotoManifests/'+v.uid),m=await tx.get(manifest);referenced=user?.photoUrls?.includes(v.path);if(!referenced)tx.set(manifest,{paths:(m.data()?.paths??[]).filter(p=>p!==v.path)});}
   if(!referenced)tx.update(doc.ref,{state:'deleting',expiresAt:Timestamp.now()});
  });
  await cursorRef.set({after:page.size===50?page.docs.at(-1).id:null});
  // Solo tareas vencidas; los errores se reprograman y no bloquean la cola.
  const q=await b.db.collection(collection).where('expiresAt','<=',Timestamp.fromMillis(now)).orderBy('expiresAt').limit(50).get();
  for(const doc of q.docs){
   const a=await b.db.runTransaction(async tx=>{
    const s=await tx.get(doc.ref);if(!s.exists)return null;const v=s.data();if(!v.expiresAt||v.expiresAt.toMillis()>now||v.leaseUntil?.toMillis()>now)return null;
    if(collection==='chatUploads'){
     const p=chatPath(v.path),message=(await tx.get(b.db.doc('matches/'+p[1]+'/messages/'+p[3]))).data();
     if(message?.mediaPath===v.path&&message.senderId===v.uid&&message.type===v.type){tx.update(doc.ref,{state:'published',expiresAt:FieldValue.delete()});return null;}
    }else{
     const profile=(await tx.get(b.db.doc('users/'+v.uid))).data(),manifest=b.db.doc('profilePhotoManifests/'+v.uid),m=await tx.get(manifest);
     if(profile?.photoUrls?.includes(v.path)){tx.update(doc.ref,{state:'published',expiresAt:FieldValue.delete()});return null;}
     tx.set(manifest,{paths:(m.data()?.paths??[]).filter(p=>p!==v.path)});
    }
    tx.update(doc.ref,{state:'deleting',leaseUntil:Timestamp.fromMillis(now+60000)});return v;
   });
   if(!a)continue;
   try{await removeAsset(b,doc.ref,a);}catch{await doc.ref.update({leaseUntil:null,expiresAt:Timestamp.fromMillis(now+60000),lastError:'cleanup-retry'});}
  }
 }
}
