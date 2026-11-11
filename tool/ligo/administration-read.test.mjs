import {ligoTestTarget} from './test-target.mjs';
const {project,ports}=ligoTestTarget();
import {test,before,after} from 'node:test';import assert from 'node:assert/strict';import {randomUUID,createHash} from 'node:crypto';import {createServer} from 'node:http';
import {emulatorServices} from '../backend/emulator.mjs';import {VerificationBackend} from '../backend/verification.mjs';import {AdministrationRead} from '../backend/administration-read.mjs';import {requestHandler} from '../backend/http-handler.mjs';
let s,api,server,origin;const prefix='visual_'+randomUUID().replaceAll('-','').slice(0,12);const created=[],authCreated=[];const ids={root:prefix+'_root',admin:prefix+'_admin',user:prefix+'_user',pending:prefix+'_pending',suspended:prefix+'_suspended'};let baseline;
const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
before(async()=>{s=await emulatorServices(project,ports);api=new AdministrationRead(new VerificationBackend(s));baseline=await Promise.all(['ligo_root','ligo_admin','ligo_student'].map(uid=>s.db.doc('users/'+uid).get()));
 for(const [kind,uid]of Object.entries(ids)){await s.auth.createUser({uid,email:uid+'@ligo.test',emailVerified:true,password:'Visual-fixture-2026!'});authCreated.push(uid);for(const [path,data]of [['users/'+uid,{firstName:'Persona',lastName:'Ficticia',email:uid+'@ligo.test',careerId:'career_a',privateDocument:'NO-EXPONER',secret:'NO-EXPONER',mainPhotoUrl:'https://invalid.example/?token=NO-EXPONER'}],['accountAccess/'+uid,{role:kind==='root'?'superadmin':kind==='admin'?'admin':'user',verificationStatus:kind==='pending'?'pending':'approved',suspended:kind==='suspended'}]]){await s.db.doc(path).create(data);created.push(path);}}
 baseline=[...baseline.filter(d=>d.exists),...await Promise.all(Object.values(ids).map(uid=>s.db.doc('users/'+uid).get()))];server=createServer(requestHandler(s));await new Promise(r=>server.listen(0,'127.0.0.1',r));origin='http://127.0.0.1:'+server.address().port;});
after(async()=>{for(const path of created)await s.db.doc(path).delete();for(const uid of authCreated)await s.auth.deleteUser(uid);await new Promise(r=>server.close(r));await s.db.terminate();});
async function token(uid){const custom=await s.auth.createCustomToken(uid,{admin:true,superadmin:true});const r=await fetch(`http://127.0.0.1:${ports.auth}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true})});const d=await r.json();assert.ok(d.idToken);return d.idToken;}
test('Lecturas HTTP deniegan anónimos, user, pendientes y suspendidos aunque falsifiquen claims',async()=>{for(const path of ['/administration/summary','/administration/users']){assert.equal((await fetch(origin+path)).status,401);for(const kind of ['user','pending','suspended'])assert.equal((await fetch(origin+path,{headers:{Authorization:'Bearer '+await token(ids[kind])}})).status,403);}});
test('Admin y superadmin obtienen métricas reales sin modificar documentos',async()=>{for(const kind of ['root','admin']){const r=await fetch(origin+'/administration/summary',{headers:{Authorization:'Bearer '+await token(ids[kind])}});assert.equal(r.status,200);const d=await r.json();assert.equal(d.totalUsers,(await s.db.collection('users').count().get()).data().count);assert.equal(d.verified,(await s.db.collection('accountAccess').where('verificationStatus','==','approved').count().get()).data().count);assert.ok(Number.isInteger(d.pendingRequests));assert.ok(!JSON.stringify(d).includes('@'));}for(const before of baseline){const now=await before.ref.get();assert.equal(digest(now.data()),digest(before.data()));assert.ok(now.updateTime.isEqual(before.updateTime));}});
test('Usuarios paginados: lista blanca, no URLs con token ni documentos y cursor validado',async()=>{for(let i=0;i<28;i++){const path='users/'+prefix+'_page_'+String(i).padStart(3,'0');await s.db.doc(path).create({firstName:'Fixture',lastName:String(i),privateDocument:'NO-EXPONER'});created.push(path);}let cursor=null,seen=new Set();do{const p=await api.users(ids.admin,cursor);assert.ok(p.items.length<=25);for(const u of p.items){assert.ok(!seen.has(u.uid));seen.add(u.uid);assert.ok(Object.keys(u).every(k=>['uid','name','email','career','role','verificationStatus','suspended','createdAt','photoPath','isActive','university','campus'].includes(k)));assert.ok(!JSON.stringify(u).includes('NO-EXPONER'));}cursor=p.nextCursor;}while(cursor);assert.ok(seen.has(ids.user));await assert.rejects(api.users(ids.admin,'../../accountAccess'),e=>e.code==='invalid-argument');});

test('Identidades acotadas: acceso vigente, lista blanca y sin documentos privados',async()=>{
 const result=await api.identities(ids.root,[ids.user,ids.user,ids.admin]);assert.equal(result.items.length,2);assert.ok(result.items.every(p=>Object.keys(p).every(k=>['uid','available','name','email','photoPath','career'].includes(k))));assert.ok(!JSON.stringify(result).includes('NO-EXPONER'));
 for(const uid of [ids.user,ids.pending,ids.suspended])await assert.rejects(api.identities(uid,[ids.admin]),e=>e.code==='permission-denied');
 await assert.rejects(api.identities(ids.root,Array(41).fill(ids.user)),e=>e.code==='invalid-argument');await assert.rejects(api.identities(ids.root,['../../private']),e=>e.code==='invalid-argument');
});
test('Auditoría legible es solo superadmin: no reescribe historia ni inventa resultados',async()=>{
 const path='administrativeAudit/'+prefix+'_event';await s.db.doc(path).create({actorId:ids.root,targetId:ids.user,action:'role_admin',reasonCode:'role_management',secret:'NO-EXPONER'});created.push(path);
 const before=await s.db.doc(path).get();const feed=await api.eventFeed(ids.root);const row=feed.items.find(r=>r.id===prefix+'_event');assert.equal(row.actor.name,'Persona Ficticia');assert.equal(row.result,null);assert.ok(!JSON.stringify(row).includes('NO-EXPONER'));assert.ok((await s.db.doc(path).get()).updateTime.isEqual(before.updateTime));await assert.rejects(api.eventFeed(ids.admin),e=>e.code==='permission-denied');
});
test('Reportes paginados con estados existentes y exclusión de revisión propia',async()=>{
 for(const [suffix,status,reporter]of [['a','pending',ids.user],['b','reviewed',ids.user],['c','pending',ids.root]]){const path='reports/'+prefix+'_'+suffix;await s.db.doc(path).create({reporterId:reporter,reportedId:ids.pending,status,reason:'spam',privateEvidence:'NO-EXPONER'});created.push(path);}
 const pending=await api.reportFeed(ids.root),resolved=await api.reportFeed(ids.root,{status:'reviewed'});assert.ok(pending.items.some(r=>r.id===prefix+'_a'));assert.ok(!pending.items.some(r=>r.id===prefix+'_c'));assert.ok(resolved.items.some(r=>r.id===prefix+'_b'));assert.ok(!JSON.stringify(pending).includes('NO-EXPONER'));await assert.rejects(api.reportFeed(ids.root,{status:'in_review'}),e=>e.code==='invalid-argument');await assert.rejects(api.reportFeed(ids.pending),e=>e.code==='permission-denied');
});
test('Revocación efectiva en la siguiente consulta; los endpoints no asignan roles',async()=>{await s.db.doc('accountAccess/'+ids.admin).update({suspended:true});await assert.rejects(api.summary(ids.admin),e=>e.code==='permission-denied');await assert.rejects(api.users(ids.admin),e=>e.code==='permission-denied');assert.equal((await s.db.doc('accountAccess/'+ids.user).get()).data().role,'user');});

test('Expediente autorizado agrega mensajes sin entregar contenido privado', async () => {
 const {readDossier} = await import('../backend/administration-dossier.mjs');
 const backend = new VerificationBackend(s);
 const match = 'matches/' + prefix + '_dossier';
 const documents = [
   [match, {users: [ids.root, ids.user], isActive: true}],
   [match + '/messages/one', {text: 'NO-EXPONER'}],
   ['swipes/' + prefix + '_dossier', {fromUserId: ids.user, toUserId: ids.root, type: 'like'}],
   ['verificationRequests/' + prefix + '_dossier', {uid: ids.user, status: 'approved', documentPath: 'NO-EXPONER'}],
 ];
 for (const [path, data] of documents) {
   await s.db.doc(path).create(data);
   created.unshift(path);
 }
 const result = await readDossier(backend, ids.root, ids.user);
 assert.equal(result.profile.name, 'Persona Ficticia');
 assert.equal(result.profile.university, null);
 assert.equal(result.activity.sent, 1);
 assert.equal(result.activity.matches, 1);
 assert.equal(result.activity.messages, 1);
 assert.equal(result.activity.active, 1);
 assert.equal(result.activity.complete, true);
 assert.equal(result.activity.contacts[0].name, 'Persona Ficticia');
 assert.equal(result.verifications[0].status, 'approved');
 assert.ok(result.audit.some(row => row.action === 'role_admin'));
 assert.ok(!JSON.stringify(result).includes('NO-EXPONER'));
 const adminAccess = s.db.doc('accountAccess/' + ids.admin);
 await adminAccess.update({suspended:false});
 try {
   const restricted = await readDossier(backend, ids.admin, ids.user);
   assert.equal(restricted.audit, null);
   assert.equal(restricted.activity.messages, 1);
 } finally { await adminAccess.update({suspended:true}); }
 for (const kind of ['user', 'pending', 'suspended', 'admin']) {
   await assert.rejects(readDossier(backend, ids[kind], ids.user), e => e.code === 'permission-denied');
 }
 const response = await fetch(origin + '/administration/dossier?user=' + ids.user,
   {headers: {Authorization: 'Bearer ' + await token(ids.root)}});
 assert.equal(response.status, 200);
 assert.equal((await response.json()).activity.messages, 1);
});

test('Fotos del expediente: sesión vigente, roles, integridad y auditoría', async () => {
 const {uploadPhoto} = await import('../backend/profile-media.mjs');
 const {readFile} = await import('node:fs/promises');
 const backend = new VerificationBackend(s);
 const target = ids.user;
 const path = 'profile_photos/'+target+'/gallery_one';
 const second = 'profile_photos/'+target+'/gallery_two';
 const unlisted = 'profile_photos/'+target+'/not_published';
 const document = 'university_cards/'+target+'/fake_request/document';
 const bytes = await readFile(new URL('../../staging/fixtures/ana-ficticia.png',import.meta.url));
 const admin = s.db.doc('accountAccess/'+ids.admin);
 const audit = () => s.db.collection('administrativeAudit').where('targetId','==',target).get();
 const photo = (ref, jwt) => fetch(origin+'/administration/profile-photo?photo='+encodeURIComponent(ref),
   jwt ? {headers:{Authorization:'Bearer '+jwt}} : {});
 await admin.update({suspended:false});
 try {
   for (const [ref,id] of [[path,'gallery_one'],[second,'gallery_two'],[unlisted,'not_published']]) {
     await uploadPhoto(backend,target,ref,bytes,'image/png');
     created.push('profilePhotoAssets/'+target+'.'+id);
   }
   created.push('profilePhotoManifests/'+target);
   const profile = s.db.doc('users/'+target);
   await profile.update({mainPhotoUrl:second,photoUrls:[path,document,second,'https://invalid.example/?token=SECRET','profile_photos/'+ids.root+'/bad']});
   const baseline = (await audit()).size;
   assert.equal((await photo(path)).status,401);
   const ordinary = await token(target);
   assert.equal((await photo(path,ordinary)).status,403);
   const [root, manager] = await Promise.all([token(ids.root),token(ids.admin)]);
   const [header,body,signature] = root.split('.');
   const expired = JSON.parse(Buffer.from(body,'base64url').toString());
   expired.exp = Math.floor(Date.now()/1000)-100;
   expired.iat = expired.exp-3600;
   assert.equal((await photo(path,[header,Buffer.from(JSON.stringify(expired)).toString('base64url'),signature].join('.'))).status,401);
   assert.equal((await photo(document,root)).status,400);
   assert.equal((await photo(unlisted,root)).status,403);
   assert.equal((await photo('profile_photos/'+target+'/../gallery_one',root)).status,400);
   assert.equal((await audit()).size,baseline);
   const response = await fetch(origin+'/administration/dossier?user='+target,{headers:{Authorization:'Bearer '+manager}});
   assert.equal(response.status,200);
   const dossier = await response.json();
   assert.deepEqual(dossier.profile.photoPaths,[second,path]);
   assert.ok(!JSON.stringify(dossier).includes('SECRET'));
   for (const [ref,jwt] of [[path,root],[second,manager]]) {
     const result = await photo(ref,jwt);
     assert.equal(result.status,200);
     assert.equal(result.headers.get('content-type'),'image/png');
     assert.equal(result.headers.get('cache-control'),'private, no-store');
     assert.deepEqual(Buffer.from(await result.arrayBuffer()),bytes);
   }
   const views = (await audit()).docs.map(d=>d.data()).filter(event=>event.action==='profile_photo_viewed');
   assert.deepEqual(views.map(v=>v.actorId).sort(),[ids.admin,ids.root].sort());
   for (const view of views) {
     assert.equal(view.targetId,target);
     assert.equal(view.result,'success');
     assert.ok(view.at.toMillis() > 0);
     assert.deepEqual(Object.keys(view).sort(),['action','actorId','at','reasonCode','requestId','result','targetId']);
   }
   await admin.update({suspended:true});
   assert.equal((await photo(path,manager)).status,403);
   await s.db.doc('profilePhotoAssets/'+target+'.gallery_one').update({sha256:'bad-hash'});
   assert.equal((await photo(path,root)).status,403);
   assert.equal((await audit()).size,baseline+2);
 } finally {
   await admin.update({suspended:true});
   for (const ref of [path,second,unlisted]) await s.bucket.file(ref).delete({ignoreNotFound:true});
   for (const doc of (await audit()).docs) {
     if(doc.data().action==='profile_photo_viewed') await doc.ref.delete();
   }
 }
});

test('Historial del expediente: páginas cronológicas, permisos y proyecciones privadas', async () => {
 const {Timestamp} = await import('firebase-admin/firestore');
 const target = ids.user;
 const batch = s.db.batch();
 const add = (path,data) => {batch.create(s.db.doc(path),data);created.unshift(path);};
 const fixed = Timestamp.fromMillis(1770000000000);
 for(let index=0;index<12;index++){
   const suffix = prefix+'_history_'+String(index).padStart(2,'0');
   const other=suffix+'_partner';
   const createdAt=index<10?fixed:Timestamp.fromMillis(1770000000000+index);
   add('users/'+other,{firstName:'Contacto',lastName:String(index)});
   add('swipes/'+suffix+'s',{fromUserId:target,toUserId:other,type:'like',createdAt});
   add('swipes/'+suffix+'r',{fromUserId:other,toUserId:target,type:'like',createdAt});
   add('matches/'+suffix,{users:[target,other],isActive:index%2===0,createdAt});
   if(index===11)add('matches/'+suffix+'/messages/one',{createdAt,senderId:other,text:'PRIVATE-CHAT',mediaPath:'PRIVATE-MEDIA'});
   add('reports/'+suffix+'s',{reporterId:target,reportedId:other,createdAt,status:'dismissed',reviewedBy:ids.admin,reviewedAt:createdAt,details:'PRIVATE-REPORT'});
   add('reports/'+suffix+'r',{reporterId:other,reportedId:target,createdAt,status:'reviewed',reviewedBy:ids.admin,reviewedAt:createdAt,details:'PRIVATE-REPORT'});
   add('verificationRequests/'+suffix,{uid:target,createdAt,status:'approved',reviewedBy:ids.admin,documentPath:'PRIVATE-CARD'});
   add('administrativeAudit/'+suffix,{actorId:other,targetId:target,at:createdAt,action:'suspend',secret:'PRIVATE-AUDIT'});
 }
 await batch.commit();
 const root = await token(ids.root);
 const admin = await token(ids.admin);
 const student = await token(target);
 const fetchHistory = (kind,jwt,cursor,user=target) => {
   const query=new URLSearchParams({kind,user,...(cursor?{cursor}:{})});
   return fetch(origin+'/administration/dossier/history?'+query,jwt?{headers:{Authorization:'Bearer '+jwt}}:{});
 };
 assert.equal((await fetchHistory('matches')).status,401);
 assert.equal((await fetchHistory('matches',student)).status,403);
 const adminAccess=s.db.doc('accountAccess/'+ids.admin);
 await adminAccess.update({suspended:false});
 try{
   assert.equal((await fetchHistory('audit',admin)).status,403);
   assert.equal((await fetchHistory('matches',admin)).status,200);
   for(const kind of ['likesSent','likesReceived','matches','conversations','reportsReceived','reportsSent','verifications','audit']){
     const first = await fetchHistory(kind,root);
     assert.equal(first.status,200);
     const page=await first.json();
     assert.equal(page.items.length,10);
     assert.ok(page.nextCursor);
     const second=await fetchHistory(kind,root,page.nextCursor);
     assert.equal(second.status,200);
     const tail=await second.json();
     assert.equal(tail.items.length,2);
     assert.equal(tail.nextCursor,null);
     assert.ok(!JSON.stringify([page.items,tail.items]).includes('PRIVATE-'));
     assert.ok(!JSON.stringify([page.items,tail.items]).includes(prefix));
     const all=[...page.items,...tail.items];
     for(let i=1;i<all.length;i++)assert.ok(all[i-1].date>=all[i].date);
     assert.equal((await fetchHistory(kind,root,'malformed')).status,400);
     if(kind==='conversations'){
       assert.equal(page.items[0].person.name,'Contacto 11');
       assert.equal(page.items[0].messages,1);
       assert.equal(page.items[0].firstMessageAt,page.items[0].lastMessageAt);
       assert.equal(page.items[1].messages,0);
       assert.equal(page.items[1].firstMessageAt,null);
     }
     if(kind==='matches'){
       assert.equal(new Set(all.map(row=>row.person.name)).size,12);
       assert.equal((await fetchHistory('conversations',root,page.nextCursor)).status,400);
       assert.equal((await fetchHistory(kind,root,page.nextCursor,ids.admin)).status,400);
     }
   }
 } finally { await adminAccess.update({suspended:true}); }
});
