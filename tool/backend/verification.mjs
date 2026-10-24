import {randomUUID} from 'node:crypto';
import {FieldValue,Timestamp,FieldPath} from 'firebase-admin/firestore';
import sharp from 'sharp';
import {sealPrivateObject} from './private-object.mjs';
const roles=['user','admin','superadmin'],statuses=['pending','approved','rejected'];
export class AccessError extends Error {constructor(code){super(code);this.code=code;}}
function requireThat(ok,code='permission-denied'){if(!ok)throw new AccessError(code);}
function id(uid){requireThat(typeof uid==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(uid),'invalid-argument');return uid;}
const stamp=()=>FieldValue.serverTimestamp();
export class VerificationBackend {
 constructor({db,bucket,auth,firestoreOrigin}){this.db=db;this.bucket=bucket;this.auth=auth;this.firestoreOrigin=firestoreOrigin;}
 account(uid){return this.db.doc('accountAccess/'+id(uid));}
 request(requestId){return this.db.doc('verificationRequests/'+id(requestId));}
 async actor(tx,uid,administrative=false){
  const a=(await tx.get(this.account(uid))).data();
  requireThat(a&&roles.includes(a.role)&&statuses.includes(a.verificationStatus)&&a.suspended===false);
  if(administrative)requireThat(a.verificationStatus==='approved'&&a.role!=='user');
  return a;
 }
 audit(tx,actorId,targetId,action,reasonCode,requestId=null){
  tx.create(this.db.collection('administrativeAudit').doc(),{actorId,targetId,action,reasonCode,requestId,at:stamp()});
 }
 cleanup(tx,requestId,path,generation=null){
  tx.set(this.db.doc('verificationCleanup/'+id(requestId)),{requestId,path,generation,state:'pending',attempts:0,nextAttemptAt:Timestamp.now(),leaseUntil:null,updatedAt:stamp()});
 }
 async provision(uid){
  const user=await this.auth.getUser(id(uid));requireThat(!user.disabled);
  return this.db.runTransaction(async tx=>{
   const ref=this.account(uid),existing=await tx.get(ref);
   const profile=await tx.get(this.db.doc('users/'+uid)),a=existing.data();
   if(profile.exists)tx.update(profile.ref,{datingAllowed:!!a&&a.verificationStatus==='approved'&&a.suspended===false&&roles.includes(a.role)});
   if(!existing.exists)tx.create(ref,{role:'user',verificationStatus:'pending',suspended:false,createdAt:stamp(),updatedAt:stamp(),latestRequestId:null});
   return {created:!existing.exists};
  });
 }
 async begin(uid){
  const user=await this.auth.getUser(id(uid));requireThat(user.emailVerified&&!user.disabled);
  await this.provision(uid);
  return this.db.runTransaction(async tx=>{
   const a=await this.actor(tx,uid);requireThat(a.verificationStatus!=='approved','already-approved');
   const old=a.latestRequestId?(await tx.get(this.request(a.latestRequestId))).data():null;
   if(old?.status==='pending')return {requestId:a.latestRequestId};
   const requestId=randomUUID();
   tx.create(this.request(requestId),{uid,institution:'univalle_cochabamba',status:'pending',documentStage:'awaiting_upload',createdAt:stamp(),updatedAt:stamp(),expiresAt:Timestamp.fromMillis(Date.now()+86400000)});
   tx.update(this.account(uid),{verificationStatus:'pending',latestRequestId:requestId,updatedAt:stamp()});
   return {requestId};
  });
 }
 async upload(uid,requestId,bytes){
  requireThat(Buffer.isBuffer(bytes)&&bytes.length>0&&bytes.length<=5*1024*1024,'invalid-image');
  const pngMagic=bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const jpegMagic=bytes[0]===255&&bytes[1]===216&&bytes[2]===255;
  const webpMagic=bytes.subarray(0,4).toString()==='RIFF'&&bytes.subarray(8,12).toString()==='WEBP';
  requireThat(pngMagic||jpegMagic||webpMagic,'invalid-image');
  // Decodifica realmente, limita píxeles y elimina metadatos/EXIF al recodificar.
  let png;
  try{
   const image=sharp(bytes,{limitInputPixels:16000000,failOn:'warning'}),meta=await image.metadata();
   requireThat(['png','jpeg','webp'].includes(meta.format)&&(!meta.pages||meta.pages===1),'invalid-image');
   png=await image.rotate().png().toBuffer();requireThat(png.length<=5*1024*1024,'invalid-image');
  }catch{throw new AccessError('invalid-image');}
  const path=`university_cards/${id(uid)}/${id(requestId)}/document`,file=this.bucket.file(path);
  await this.db.runTransaction(async tx=>{
   await this.actor(tx,uid);const r=(await tx.get(this.request(requestId))).data();
   requireThat(r?.uid===uid&&r.status==='pending'&&r.documentStage==='awaiting_upload'&&r.expiresAt.toMillis()>Date.now());
   tx.update(this.request(requestId),{documentStage:'uploading',documentPath:path,updatedAt:stamp()});
  });
  let generation=null;
  try{
   await file.save(png,{resumable:false,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:'image/png',cacheControl:'private, no-store',metadata:{}}});
   // No emitir token Firebase. El emulador puede añadirlo al guardar: eliminarlo.
   await sealPrivateObject(file);
   const [meta]=await file.getMetadata();generation=meta.generation;
   requireThat(!meta.metadata?.firebaseStorageDownloadTokens,'private-storage-required');
   await this.db.runTransaction(async tx=>{
    await this.actor(tx,uid);const r=(await tx.get(this.request(requestId))).data();
    requireThat(r?.uid===uid&&r.status==='pending'&&r.documentStage==='uploading');
    tx.update(this.request(requestId),{documentStage:'ready',generation,updatedAt:stamp()});
   });
   return {ready:true};
  }catch(error){
   await this.db.runTransaction(async tx=>{
    const r=(await tx.get(this.request(requestId))).data();
    const a=(await tx.get(this.account(uid))).data();
    if(r){this.cleanup(tx,requestId,path,generation);tx.update(this.request(requestId),{status:'rejected',reasonCode:'upload_failed',resolvedAt:stamp(),updatedAt:stamp()});
     if(a?.latestRequestId===requestId)tx.update(this.account(uid),{verificationStatus:'rejected',updatedAt:stamp()});}
   });
   throw error;
  }
 }
 async withdraw(uid,requestId){
  return this.db.runTransaction(async tx=>{
   await this.actor(tx,uid);const r=(await tx.get(this.request(requestId))).data();
   requireThat(r?.uid===uid&&r.status==='pending');
   tx.update(this.request(requestId),{status:'rejected',reasonCode:'withdrawn',updatedAt:stamp(),resolvedAt:stamp()});
   tx.update(this.account(uid),{verificationStatus:'rejected',updatedAt:stamp()});
   if(r.documentPath)this.cleanup(tx,requestId,r.documentPath,r.generation??null);
  });
 }
 async decide(actorId,requestId,status,reasonCode){
  requireThat(['approved','rejected'].includes(status),'invalid-argument');
  requireThat(status==='approved'?reasonCode==='verified':['unreadable','expired','not_univalle_cochabamba','information_mismatch','other'].includes(reasonCode),'invalid-argument');
  return this.db.runTransaction(async tx=>{
   await this.actor(tx,actorId,true);const r=(await tx.get(this.request(requestId))).data();
   requireThat(r&&r.uid!==actorId);
   requireThat(r.status==='pending'&&r.documentStage==='ready'&&r.expiresAt.toMillis()>Date.now(),'conflict');
   const a=(await tx.get(this.account(r.uid))).data();requireThat(a?.latestRequestId===requestId&&a.suspended===false);
   const profile=await tx.get(this.db.doc('users/'+r.uid));
   tx.update(this.request(requestId),{status,reasonCode,resolvedAt:stamp(),updatedAt:stamp(),reviewedBy:actorId});
   tx.update(this.account(r.uid),{verificationStatus:status,updatedAt:stamp()});
   if(profile.exists)tx.update(profile.ref,{datingAllowed:status==='approved'});
   this.audit(tx,actorId,r.uid,'verification_'+status,reasonCode,requestId);
   this.cleanup(tx,requestId,r.documentPath,r.generation);
  });
 }
 async changeRole(actorId,uid,role){
  requireThat(roles.includes(role),'invalid-argument');requireThat(actorId!==uid);
  return this.db.runTransaction(async tx=>{
   const actor=await this.actor(tx,actorId,true);requireThat(actor.role==='superadmin');
   const target=(await tx.get(this.account(uid))).data(),ref=this.db.doc('administration/roles');
   const registry=(await tx.get(ref)).data();requireThat(target&&roles.includes(target.role)&&registry&&Array.isArray(registry.superadminIds)&&registry.superadminIds.includes(actorId));
   const ids=new Set(registry.superadminIds);
   requireThat((target.role==='superadmin')===ids.has(uid),'registry-inconsistent');
   if(role==='superadmin')ids.add(uid);else ids.delete(uid);
   requireThat(ids.size>0,'last-superadmin');
   tx.set(ref,{superadminIds:[...ids].sort(),updatedAt:stamp()});
   tx.update(this.account(uid),{role,updatedAt:stamp()});this.audit(tx,actorId,uid,'role_'+role,'role_management');
  });
 }
 async suspend(actorId,uid,suspended,reasonCode){
  requireThat(actorId!==uid&&typeof suspended==='boolean');
  requireThat(['abuse','spam','safety','other'].includes(reasonCode),'invalid-argument');
  return this.db.runTransaction(async tx=>{
   const actor=await this.actor(tx,actorId,true),target=(await tx.get(this.account(uid))).data();
   requireThat(target&&roles.includes(target.role)&&(target.role==='user'||actor.role==='superadmin'));
   const registry=(await tx.get(this.db.doc('administration/roles'))).data();
   const profile=await tx.get(this.db.doc('users/'+uid));
   if(suspended&&target.role==='superadmin')requireThat(registry?.superadminIds?.length>1,'last-superadmin');
   tx.update(this.account(uid),{suspended,updatedAt:stamp()});
   if(profile.exists)tx.update(profile.ref,{datingAllowed:!suspended&&target.verificationStatus==='approved'});
   this.audit(tx,actorId,uid,suspended?'suspend':'restore',reasonCode);
  });
 }
 async readDocument(actorId,requestId){
  const r=await this.db.runTransaction(async tx=>{
   await this.actor(tx,actorId,true);const data=(await tx.get(this.request(requestId))).data();
   requireThat(data&&data.uid!==actorId&&data.status==='pending'&&data.documentStage==='ready'&&data.expiresAt.toMillis()>Date.now());
   this.audit(tx,actorId,data.uid,'document_review','review',requestId);return data;
  });
  const bytes=(await this.bucket.file(r.documentPath).download())[0];
  // Revalidar tras la E/S: una suspensión o decisión concurrente invalida la vista.
  await this.db.runTransaction(async tx=>{await this.actor(tx,actorId,true);const current=(await tx.get(this.request(requestId))).data();requireThat(current?.status==='pending'&&current.documentStage==='ready'&&current.expiresAt.toMillis()>Date.now());});
  return bytes;
 }
 async listRequests(actorId,{status='pending',cursor=null}={}){
  await this.db.runTransaction(tx=>this.actor(tx,actorId,true));
  requireThat(['pending','approved','rejected'].includes(status),'invalid-argument');
  let query=this.db.collection('verificationRequests').where('status','==',status).orderBy(FieldPath.documentId());
  if(cursor)query=query.startAfter(id(cursor));
  const q=await query.limit(20).get();
  // Lista blanca: ninguna ruta privada, generación ni metadato de almacenamiento.
  return q.docs.map(d=>{const r=d.data();return {id:d.id,uid:r.uid,status:r.status,documentStage:r.documentStage,createdAt:r.createdAt?.toDate().toISOString(),resolvedAt:r.resolvedAt?.toDate().toISOString(),reasonCode:r.reasonCode??null,reviewedBy:r.reviewedBy??null,canReview:r.uid!==actorId&&r.status==='pending'&&r.documentStage==='ready'};});
 }
 async ownRequest(uid){
  return this.db.runTransaction(async tx=>{const a=await this.actor(tx,uid);
   if(!a.latestRequestId)return null;
   const r=(await tx.get(this.request(a.latestRequestId))).data();requireThat(r?.uid===uid);
   return {id:a.latestRequestId,uid,status:r.status,documentStage:r.documentStage,createdAt:r.createdAt?.toDate().toISOString(),resolvedAt:r.resolvedAt?.toDate().toISOString(),reasonCode:r.reasonCode??null};
  });
 }
 async listAudit(actorId,cursor=null){
  const a=await this.db.runTransaction(tx=>this.actor(tx,actorId,true));requireThat(a.role==='superadmin');
  let q=this.db.collection('administrativeAudit').orderBy(FieldPath.documentId());if(cursor)q=q.startAfter(id(cursor));
  return (await q.limit(20).get()).docs.map(d=>{const r=d.data();return {id:d.id,actorId:r.actorId,targetId:r.targetId,action:r.action,reasonCode:r.reasonCode,requestId:r.requestId,at:r.at?.toDate().toISOString()};});
 }
 async listReports(actorId){
  await this.db.runTransaction(tx=>this.actor(tx,actorId,true));
  const q=await this.db.collection('reports').where('status','==','pending').limit(20).get();
  return q.docs.filter(d=>![d.data().reporterId,d.data().reportedId].includes(actorId)).map(d=>{const r=d.data();return {id:d.id,reportedId:r.reportedId,reason:r.reason,details:r.details,status:r.status,createdAt:r.createdAt?.toDate().toISOString()};});
 }
 async lookupAccount(actorId,uid){
  return this.db.runTransaction(async tx=>{await this.actor(tx,actorId,true);const a=(await tx.get(this.account(uid))).data();requireThat(a,'not-found');
   return {uid,role:a.role,verificationStatus:a.verificationStatus,suspended:a.suspended};});
 }
 async reviewReport(actorId,reportId,resolution){
  requireThat(['reviewed','dismissed'].includes(resolution),'invalid-argument');
  return this.db.runTransaction(async tx=>{
   await this.actor(tx,actorId,true);requireThat(typeof reportId==='string'&&/^[A-Za-z0-9_.-]{1,257}$/.test(reportId),'invalid-argument');
   const ref=this.db.doc('reports/'+reportId),r=(await tx.get(ref)).data();
   requireThat(r&&r.reporterId!==actorId&&r.reportedId!==actorId);
   requireThat(r.status==='pending','conflict');
   tx.update(ref,{status:resolution,reviewedAt:stamp(),reviewedBy:actorId});this.audit(tx,actorId,r.reportedId,'report_'+resolution,'report_review');
  });
 }
 async cleanupDue(now=Date.now()){
  // Recupera también solicitudes abandonadas y subidas interrumpidas.
  const stale=await this.db.collection('verificationRequests').where('status','==','pending').get();
  for(const doc of stale.docs){const r=doc.data();if(r.expiresAt?.toMillis()<=now){
   await this.db.runTransaction(async tx=>{const current=(await tx.get(doc.ref)).data();if(current?.status!=='pending')return;
    const a=(await tx.get(this.account(current.uid))).data();
    tx.update(doc.ref,{status:'rejected',reasonCode:'expired',resolvedAt:stamp(),updatedAt:stamp()});
    if(a?.latestRequestId===doc.id)tx.update(this.account(current.uid),{verificationStatus:'rejected',updatedAt:stamp()});
    if(current.documentPath)this.cleanup(tx,doc.id,current.documentPath,current.generation??null);
   });
  }}
  now=Math.max(now,Date.now()); // Incluye tareas creadas al expirar en esta pasada.
  const jobs=await this.db.collection('verificationCleanup').where('state','==','pending').limit(100).get();
  for(const doc of jobs.docs){
   const job=await this.db.runTransaction(async tx=>{const j=(await tx.get(doc.ref)).data();if(!j||j.state!=='pending'||j.nextAttemptAt.toMillis()>now||j.leaseUntil?.toMillis()>now)return null;
    tx.update(doc.ref,{leaseUntil:Timestamp.fromMillis(now+60000)});return j;});
   if(!job)continue;
   try{
    requireThat(/^university_cards\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/document$/.test(job.path),'invalid-path');
    try{await this.bucket.file(job.path).delete(job.generation?{ifGenerationMatch:job.generation}:{});}catch(e){if(e.code!==404)throw e;}
    await this.db.runTransaction(async tx=>{const r=await tx.get(this.request(job.requestId));
     tx.update(doc.ref,{state:'done',leaseUntil:null,updatedAt:stamp()});
     if(r.exists)tx.update(r.ref,{documentPath:FieldValue.delete(),generation:FieldValue.delete(),documentStage:'deleted',updatedAt:stamp()});
    });
   }catch{
    const attempts=job.attempts+1;
    await doc.ref.update({attempts,leaseUntil:null,nextAttemptAt:Timestamp.fromMillis(now+Math.min(86400000,60000*2**Math.min(attempts,10))),lastErrorCode:'delete_failed',updatedAt:stamp()});
   }
  }
 }
}
