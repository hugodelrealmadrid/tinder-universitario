import {FieldPath} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';
// Consultas de presentación: sin mutaciones, documentos privados ni cambios de permisos.
export class AdministrationRead {
 constructor(backend){this.backend=backend;this.db=backend.db;}
 async authorize(uid){const a=await this.db.runTransaction(tx=>this.backend.actor(tx,uid,true));if(a.verificationStatus!=='approved')throw new AccessError('permission-denied');}
 async summary(uid){await this.authorize(uid);const count=async q=>(await q.count().get()).data().count;const access=this.db.collection('accountAccess');const [totalUsers,verified,pending,rejected,suspended,matches,pendingRequests,reports]=await Promise.all([count(this.db.collection('users')),count(access.where('verificationStatus','==','approved')),count(access.where('verificationStatus','==','pending')),count(access.where('verificationStatus','==','rejected')),count(access.where('suspended','==',true)),count(this.db.collection('matches')),count(this.db.collection('verificationRequests').where('status','==','pending')),count(this.db.collection('reports').where('status','==','pending'))]);await this.authorize(uid);return {totalUsers,verified,pending,rejected,suspended,matches,pendingRequests,reports,generatedAt:new Date().toISOString()};}
 async users(uid,cursor=null){await this.authorize(uid);if(cursor!==null&&(typeof cursor!=='string'||! /^[A-Za-z0-9_-]{1,128}$/.test(cursor)))throw new AccessError('invalid-argument');let q=this.db.collection('users').orderBy(FieldPath.documentId());if(cursor)q=q.startAfter(cursor);const page=await q.limit(26).get();const items=await Promise.all(page.docs.slice(0,25).map(async d=>{const p=d.data();const a=(await this.db.doc('accountAccess/'+d.id).get()).data();let career=null;if(typeof p.careerId==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(p.careerId))career=(await this.db.doc('careers/'+p.careerId).get()).data()?.name??null;const safe=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value);const affiliation={};if(safe(p.universityId)){const uni=this.db.doc('universities/'+p.universityId);const [u,campus]=await Promise.all([uni.get(),safe(p.campusId)?uni.collection('campuses').doc(p.campusId).get():null]);affiliation.university=u.data()?.name??null;affiliation.campus=campus?.data()?.name??null;}return {uid:d.id,...affiliation,name:[p.firstName,p.lastName].filter(x=>typeof x==='string').join(' '),email:typeof p.email==='string'?p.email:null,career,role:a?.role??null,verificationStatus:a?.verificationStatus??null,suspended:a?.suspended===true,isActive:typeof p.isActive==='boolean'?p.isActive:null,createdAt:(typeof p.createdAt?.toDate==='function'?p.createdAt:d.createTime)?.toDate().toISOString(),photoPath:typeof p.mainPhotoUrl==='string'&&p.mainPhotoUrl.startsWith('profile_photos/'+d.id+'/')?p.mainPhotoUrl:null};}));await this.authorize(uid);return {items,nextCursor:page.docs.length>25?page.docs[24].id:null};}
 async identities(uid,ids){
  await this.authorize(uid);
  if(!Array.isArray(ids)||ids.length>40||ids.some(x=>typeof x!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(x)))throw new AccessError('invalid-argument');
  const unique = [...new Set(ids)];
  if (!unique.length) return {items: []};
  const profiles = await this.db.getAll(...unique.map(id => this.db.doc('users/' + id)));
  const catalogPath = (collection, id) =>
    typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id)
      ? collection + '/' + id
      : null;
  const paths = [...new Set(profiles.flatMap(profile => {
    const person = profile.data();
    return [catalogPath('careers', person?.careerId)];
  }).filter(Boolean))];
  const catalog = paths.length ? await this.db.getAll(...paths.map(path => this.db.doc(path))) : [];
  const names = new Map(catalog.map(doc => [doc.ref.path, doc.data()?.name]));
  const nameFor = (collection, id) => {
    const name = names.get(catalogPath(collection, id));
    return typeof name === 'string' ? name : null;
  };
  const items = profiles.map(profile => {
    const person = profile.data(), id = profile.id;
    return {
      uid: id,
      available: profile.exists,
      name: person ? [person.firstName, person.lastName].filter(value => typeof value === 'string').join(' ') : null,
      email: typeof person?.email === 'string' ? person.email : null,
      photoPath: typeof person?.mainPhotoUrl === 'string' && person.mainPhotoUrl.startsWith('profile_photos/' + id + '/') ? person.mainPhotoUrl : null,
      career: nameFor('careers', person?.careerId),
    };
  });
  await this.authorize(uid);return {items};
 }
 async eventFeed(uid,cursor=null){
  const rows=await this.backend.listAudit(uid,cursor); // Conserva acceso exclusivo del superadmin.
  const ids=[...new Set(rows.flatMap(r=>[r.actorId,r.targetId]).filter(x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(x)))];
  const actor=await this.db.runTransaction(tx=>this.backend.actor(tx,uid,true));const people=actor.verificationStatus==='approved'?await this.identities(uid,ids):{items:[]};const lookup=id=>people.items.find(p=>p.uid===id)??null;
  const items=await Promise.all(rows.map(async row=>{const snapshot=await this.db.doc('administrativeAudit/'+row.id).get(),raw=snapshot.data();let entity=null;
   if(['universities','careers','interests'].includes(raw?.catalog)&&typeof row.targetId==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(row.targetId)){const d=await this.db.doc(raw.catalog+'/'+row.targetId).get();entity={kind:raw.catalog,name:typeof d.data()?.name==='string'?d.data().name:null};}
   return {...row,actor:lookup(row.actorId),target:lookup(row.targetId),entity,result:['success','error','failed','warning'].includes(raw?.result)?raw.result:null};
  }));const finalActor=await this.db.runTransaction(tx=>this.backend.actor(tx,uid,true));if(finalActor.role!=='superadmin')throw new AccessError('permission-denied');return {items,nextCursor:rows.length===20?rows.at(-1).id:null};
 }
 async reportFeed(uid,{status='pending',cursor=null}={}){
  const actor=await this.db.runTransaction(tx=>this.backend.actor(tx,uid,true));if(!['pending','reviewed','dismissed'].includes(status)||cursor!==null&&(typeof cursor!=='string'||!/^[A-Za-z0-9_.-]{1,257}$/.test(cursor)))throw new AccessError('invalid-argument');
  let q=this.db.collection('reports').where('status','==',status).orderBy(FieldPath.documentId());if(cursor)q=q.startAfter(cursor);const page=await q.limit(21).get(),raw=page.docs.slice(0,20);
  const visible=raw.filter(d=>![d.data().reporterId,d.data().reportedId].includes(uid));const ids=[...new Set(visible.flatMap(d=>[d.data().reporterId,d.data().reportedId]).filter(x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(x)))];const people=actor.verificationStatus==='approved'?await this.identities(uid,ids):{items:[]},lookup=id=>people.items.find(p=>p.uid===id)??null;
  const items=visible.map(d=>{const r=d.data();return {id:d.id,reportedId:r.reportedId,reporterId:r.reporterId,reporter:lookup(r.reporterId),reported:lookup(r.reportedId),reason:r.reason??r.reasonCode??null,details:typeof r.details==='string'?r.details:null,status:r.status,createdAt:r.createdAt?.toDate().toISOString(),reviewedAt:r.reviewedAt?.toDate().toISOString(),reviewedBy:r.reviewedBy??null};});
  await this.db.runTransaction(tx=>this.backend.actor(tx,uid,true));return {items,nextCursor:page.docs.length>20?raw.at(-1).id:null};
 }

}
