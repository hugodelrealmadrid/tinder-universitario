import {randomUUID,createHash} from 'node:crypto';
import {FieldValue,FieldPath} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';
const kinds=['careers','interests'];
const need=(ok,code='invalid-argument')=>{if(!ok)throw new AccessError(code);};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const norm=s=>s.normalize('NFKD').replace(/\p{M}/gu,'').replace(/\s+/gu,' ').trim().toLowerCase();
function text(s,max=120){need(typeof s==='string');s=s.normalize('NFC').trim().replace(/\s+/gu,' ');need(s.length>=2&&s.length<=max&&!/\p{Cc}/u.test(s)&&/\p{L}/u.test(s));return s;}
function normalized(kind,data){
 need(data&&typeof data==='object'&&!Array.isArray(data)&&Object.keys(data).every(k=>['name','isActive'].includes(k)));
 const out={name:text(data.name,kind==='interests'?80:120),isActive:data.isActive};need(typeof out.isActive==='boolean');
 return out;
}
const fingerprint=(kind,name)=>createHash('sha256').update(JSON.stringify([kind,norm(name)])).digest('hex');
const stamp=()=>FieldValue.serverTimestamp();
export class CatalogBackend{
 constructor({db,authorize}){this.db=db;this.authorize=authorize;}
 async actor(tx,uid,kind){need(kinds.includes(kind));const a=await this.authorize(tx,uid);need(a.verificationStatus==='approved','permission-denied');return a;}
 async list(uid,kind,cursor=null){
  await this.db.runTransaction(tx=>this.actor(tx,uid,kind));need(cursor===null||id(cursor));
  let q=this.db.collection(kind).orderBy(FieldPath.documentId());if(cursor)q=q.startAfter(cursor);
  const rows=await q.limit(51).get();return {items:rows.docs.slice(0,50).map(d=>{const x=d.data();return {id:d.id,name:x.name,isActive:x.isActive,revision:x.revision??0};}),nextCursor:rows.docs.length>50?rows.docs[49].id:null};
 }
 async save(uid,kind,{id:target=null,data,expectedRevision=null,requestId}={}){
  need(kinds.includes(kind)&&id(uid)&&id(requestId)&& (target===null||id(target)));
  const newId=target??randomUUID(),payloadHash=createHash('sha256').update(JSON.stringify({kind,target,data,expectedRevision})).digest('hex');
  return this.db.runTransaction(async tx=>{
   await this.actor(tx,uid,kind);
   const operation=this.db.doc('catalogOperations/'+uid+'.'+requestId),prior=(await tx.get(operation)).data();
   if(prior){need(prior.payloadHash===payloadHash,'conflict');return {id:prior.targetId,revision:prior.revision,idempotent:true};}
   const ref=this.db.doc(kind+'/'+newId),snapshot=await tx.get(ref),old=snapshot.data();
   if(target){need(snapshot.exists,'not-found');need(Number.isInteger(expectedRevision)&&expectedRevision===(old.revision??0),'conflict');}else need(!snapshot.exists,'conflict');
   const next=normalized(kind,data);
   let key=null,oldKey=null;
   if(!old||norm(old.name)!==norm(next.name)){
    const hash=fingerprint(kind,next.name);
    key=this.db.doc('catalogUniqueKeys/'+hash);
    const claim=(await tx.get(key)).data();
    need(!claim||claim.targetId===newId,'duplicate-catalog');
    // Los catálogos históricos pueden contener homónimos. Se conservan sus
    // identificadores y se rechazan duplicados solo para altas o renombres.
    const all=await tx.get(this.db.collection(kind));
    need(!all.docs.some(d=>d.id!==newId&&typeof d.data().name==='string'&&norm(d.data().name)===norm(next.name)),'duplicate-catalog');
    if(old){
     const previous=this.db.doc('catalogUniqueKeys/'+fingerprint(kind,old.name));
     if((await tx.get(previous)).data()?.targetId===newId)oldKey=previous;
    }
   }
   const revision=(old?.revision??0)+1;
   const fields={...next,revision,updatedAt:stamp(),updatedBy:uid,...(!old?{schemaVersion:2,createdAt:stamp(),createdBy:uid}:{})};
   if(old)tx.update(ref,fields);else tx.create(ref,fields);
   if(oldKey)tx.delete(oldKey);if(key)tx.set(key,{kind,targetId:newId});
   const action=!old?'catalog_create':old.isActive!==next.isActive?(next.isActive?'catalog_activate':'catalog_deactivate'):'catalog_edit';
   tx.create(this.db.collection('administrativeAudit').doc(),{actorId:uid,targetId:newId,action,reasonCode:'catalog_management',catalog:kind,at:stamp()});
   tx.set(this.db.doc('registrationDirectory/version'),{revision:FieldValue.increment(1)},{merge:true});
   tx.create(operation,{actorId:uid,targetId:newId,payloadHash,revision,createdAt:stamp()});return {id:newId,revision,idempotent:false};
  });
 }
}
