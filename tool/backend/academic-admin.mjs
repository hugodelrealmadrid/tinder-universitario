import {FieldPath,FieldValue} from 'firebase-admin/firestore';
import {randomUUID,createHash} from 'node:crypto';
import {AccessError} from './access-error.mjs';

const id = v => typeof v==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
const need = (ok,code='invalid-argument') => {if(!ok)throw new AccessError(code);};
const text = (v,max=120) => typeof v==='string' && v.trim().length>=2 && v.trim().length<=max && !/[\p{Cc}]/u.test(v);
const normalized = value => value.normalize('NFKD').replace(/\p{M}/gu,'').trim().toLowerCase().replace(/\s+/g,' ');
const source = value => {
 try { const url=new URL(value); return typeof value==='string'&&value.length<=500&&url.protocol==='https:'&&!url.username&&!url.password&&!url.search&&!url.hash; }
 catch {return false;}
};
const output = doc => {
 const {name,abbreviation,city,countryCode,isActive,source,verifiedOn,revision}=doc.data();
 return {id:doc.id,name,abbreviation,city,countryCode,isActive,source,verifiedOn,revision:revision??0};
};

export class AcademicAdmin {
 constructor(backend){this.backend=backend;this.db=backend.db;}
 async actor(tx,uid){
  const a=await this.backend.actor(tx,uid,true);
  need(a.role==='superadmin'&&a.verificationStatus==='approved','permission-denied');
 }
 collection(university,campus){
  if(university==null){need(campus==null);return this.db.collection('universities');}
  need(id(university));
  const campuses=this.db.collection('universities/'+university+'/campuses');
  if(campus==null)return campuses;
  need(id(campus));
  return campuses.doc(campus).collection('offerings');
 }
 async list(uid,{university,campus,cursor}){
  await this.db.runTransaction(tx=>this.actor(tx,uid));
  let q=this.collection(university,campus).orderBy(FieldPath.documentId());
  if(cursor!=null){need(id(cursor));q=q.startAfter(cursor);}
  const page=await q.limit(31).get();
  await this.db.runTransaction(tx=>this.actor(tx,uid));
  return {items:page.docs.slice(0,30).map(output),nextCursor:page.size>30?page.docs[29].id:null};
 }
 async save(uid,{university=null,campus=null,target=null,revision=null,data}){
  const collection=this.collection(university,campus);
  need(data&&typeof data==='object'&&!Array.isArray(data)&&typeof data.isActive==='boolean');
  const offering=campus!==null;
  const allowed=offering?['isActive','source','verifiedOn']:university?['name','city','isActive']:['name','abbreviation','city','countryCode','isActive'];
  need(Object.keys(data).every(k=>allowed.includes(k)));
  if(target!==null)need(id(target));
  if(offering)need(target!==null && (!data.isActive || source(data.source)&&/^20\d{2}-\d{2}-\d{2}$/.test(data.verifiedOn)
    && Number.isFinite(Date.parse(data.verifiedOn)) && new Date(data.verifiedOn).toISOString().slice(0,10)===data.verifiedOn
    && data.verifiedOn<=new Date().toISOString().slice(0,10)));
  if(!offering)need(text(data.name)&&text(data.city,80));
  if(!university)need(text(data.abbreviation,20)&&/^[A-Z]{2}$/.test(data.countryCode));
  return this.db.runTransaction(async tx=>{
   await this.actor(tx,uid);
   const ref=collection.doc(target??randomUUID());
   const previous=await tx.get(ref);
   need(previous.exists?revision===(previous.data().revision??0):revision===null,'conflict');
   if(!offering&&target!==null)need(previous.exists,'not-found');
   if(university)need((await tx.get(this.db.doc('universities/'+university))).exists,'not-found');
   let name=offering?null:data.name.trim();
   if(offering){
    const campusDoc=await tx.get(this.db.doc('universities/'+university+'/campuses/'+campus));
    const career=await tx.get(this.db.doc('careers/'+target));
    need(campusDoc.exists&&career.exists,'not-found');
    need(!data.isActive||career.data().isActive===true);
    name=career.data().name;
   }
   let key,oldKey;
   if(!offering&&normalized(previous.data()?.name??'')!==normalized(name)){
    const unique = value => this.db.doc('catalogUniqueKeys/'+createHash('sha256').update(collection.path+':'+normalized(value)).digest('hex'));
    key=unique(name);
    need(!(await tx.get(key)).exists,'duplicate-catalog');
    const exact=await tx.get(collection.where('name','==',name).limit(2));
    need(exact.docs.every(doc=>doc.id===ref.id),'duplicate-catalog');
    if(previous.exists){
     const old=unique(previous.data().name);
     if((await tx.get(old)).data()?.targetId===ref.id)oldKey=old;
    }
   }
   const next=(previous.data()?.revision??0)+1;
   tx.set(ref,{...data,name,revision:next,...(!university?{directory:true}:{})},{merge:true});
   if(key)tx.create(key,{targetId:ref.id});
   if(oldKey)tx.delete(oldKey);
   tx.set(this.db.doc('registrationDirectory/version'),{revision:FieldValue.increment(1)},{merge:true});
   this.backend.audit(tx,uid,university??ref.id,
    !previous.exists?'academic_create':data.isActive?'academic_save':'academic_deactivate',
    offering?'academic_offering':university?'academic_campus':'academic_university');
   return {id:ref.id,revision:next};
  });
 }
}
