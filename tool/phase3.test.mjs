import {ligoTestTarget} from './ligo/test-target.mjs';
import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import sharp from 'sharp';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,getDoc,getDocs,collection,query,where,limit,setDoc,updateDoc,deleteDoc,serverTimestamp} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';
import {ref,getMetadata,getDownloadURL,uploadBytes} from 'firebase/storage';
import {emulatorServices} from './backend/emulator.mjs';
import {VerificationBackend} from './backend/verification.mjs';
import {uploadChat} from './backend/chat-upload.mjs';
import {readChat} from './backend/chat-read.mjs';
import {sealPrivateObject} from './backend/private-object.mjs';
const stage=process.env.LIGO_STAGING_TESTS==='1';const ports=stage?ligoTestTarget().ports:{auth:9199,firestore:8188,storage:9298,hub:4410};const project=stage?ligoTestTarget().project:'demo-tinder-phase3-tests';let env,services,backend,png;
const context=uid=>env.authenticatedContext(uid,{email:uid+'@demo.test',email_verified:true});
const account=(status='approved',role='user',suspended=false)=>({role,verificationStatus:status,suspended,latestRequestId:null,createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
before(async()=>{
 services=await emulatorServices(project,ports);backend=new VerificationBackend(services);
 env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:ports.firestore,rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')},storage:{host:'127.0.0.1',port:ports.storage,rules:await readFile(new URL('../storage.rules',import.meta.url),'utf8')}});
 for(const uid of ['alice','bob','pending','admin','root','root2','missing']){
  try{await services.auth.getUser(uid);}catch{await services.auth.createUser({uid,email:uid+'@demo.test',emailVerified:true});}
 }
 png=await sharp({create:{width:8,height:8,channels:3,background:'#224488'}}).png().toBuffer();
});
after(async()=>{await env?.cleanup();});
beforeEach(async()=>{
 await env.clearFirestore();await env.clearStorage();
 for(const uid of ['alice','bob','pending','admin','root','root2'])await services.db.doc('accountAccess/'+uid).set(account(uid==='pending'?'pending':'approved',uid==='root'?'superadmin':uid==='admin'?'admin':'user'));
 await services.db.doc('administration/roles').set({superadminIds:['root']});
 await services.db.doc('matches/alice.bob').set({users:['alice','bob'],isActive:true,createdAt:Timestamp.now()});
 await services.db.doc('matches/alice.bob/messages/history').set({senderId:'bob',text:'historial',createdAt:Timestamp.now()});
 await services.db.doc('users/alice').set({isActive:true,datingAllowed:true});
 await services.db.doc('users/bob').set({isActive:true,datingAllowed:true});
 await services.db.doc('discoveryIndex/bob').set({isActive:true,updatedAt:Timestamp.now()});
});
test('Cuenta ausente: provisionamiento solo user pendiente; idempotente y sin aprobar',async()=>{
 await backend.provision('missing');await backend.provision('missing');
 const a=(await services.db.doc('accountAccess/missing').get()).data();assert.equal(a.role,'user');assert.equal(a.verificationStatus,'pending');assert.equal(a.suspended,false);
});
test('Backend se niega a inicializar cualquier proyecto real',async()=>{await assert.rejects(emulatorServices('tinder-universitario'),/demo-only/);});
test('Cliente no crea, cambia ni elimina acceso, roles, decisiones, auditoría o tareas',async()=>{
 for(const uid of ['pending','admin','root'])for(const path of ['accountAccess/'+uid,'administration/roles','administrativeAudit/forged','verificationCleanup/forged','verificationRequests/forged']){
  await assertFails(setDoc(doc(context(uid).firestore(),path),{role:'superadmin',verificationStatus:'approved',suspended:false}));
  await assertFails(deleteDoc(doc(context(uid).firestore(),path)));
 }
});
test('Claims administrativos falsificados no cambian autorización de servidor',async()=>{
 await assert.rejects(backend.changeRole('pending','alice','admin'));
 const fake=env.authenticatedContext('pending',{admin:true,role:'superadmin',email_verified:true});
 await assertFails(getDoc(doc(fake.firestore(),'accountAccess/root')));
});
for(const status of ['missing','pending','rejected','suspended','malformed'])test('Accesos a citas e historial denegados: '+status,async()=>{
 const ref=services.db.doc('accountAccess/alice');
 if(status==='missing')await ref.delete();else await ref.set(status==='malformed'?{role:'superadmin'}:account(status==='suspended'?'approved':status,'user',status==='suspended'));
 await services.db.doc('users/alice').update({datingAllowed:false});
 const db=context('alice').firestore();
 for(const p of ['matches/alice.bob','matches/alice.bob/messages/history','discoveryIndex/bob','discoveryCards/bob','matchProfiles/bob','swipes/alice.bob'])await assertFails(getDoc(doc(db,p)));
 await assertFails(getDocs(query(collection(db,'matches'),where('users','array-contains','alice'))));
 await assertFails(getDocs(query(collection(db,'matches/alice.bob/messages'),limit(50))));
 await assertFails(setDoc(doc(db,'matches/alice.bob/messages/new'),{senderId:'alice',text:'intrusión',createdAt:serverTimestamp()}));
 await assert.rejects(uploadChat(backend,'alice','chat_media/alice.bob/alice/new',Buffer.from([1,2,3]),'image/png'));
});
test('Aprobado explícito conserva historial y matches existentes',async()=>{
 const db=context('alice').firestore();await assertSucceeds(getDoc(doc(db,'matches/alice.bob')));await assertSucceeds(getDoc(doc(db,'matches/alice.bob/messages/history')));
});
test('Suspensión es independiente de isActive, revoca lectura de archivos previos',async()=>{
 await uploadChat(backend,'bob','chat_media/alice.bob/bob/file',png,'image/png');
 await services.db.doc('matches/alice.bob/messages/file').set({senderId:'bob',text:'',type:'image',mediaPath:'chat_media/alice.bob/bob/file',createdAt:Timestamp.now()});
 const file=ref(context('alice').storage(project+'.appspot.com'),'chat_media/alice.bob/bob/file');await assertFails(getMetadata(file));
 await readChat(backend,'alice',file.fullPath);
 await backend.suspend('admin','alice',true,'safety');
 assert.equal((await services.db.doc('users/alice').get()).data().isActive,true);
 await assertFails(getMetadata(file));await assert.rejects(readChat(backend,'alice',file.fullPath));
 await backend.suspend('admin','alice',false,'safety');await readChat(backend,'alice',file.fullPath);
});
test('Subida directa de chat denegada incluso para usuario aprobado',async()=>{
 await assertFails(uploadBytes(ref(context('alice').storage(project+'.appspot.com'),'chat_media/alice.bob/alice/direct'),png,{contentType:'image/png',customMetadata:{memberA:'alice',memberB:'bob'}}));
});
test('Migración revoca token real del emulador sin alterar bytes del archivo',async()=>{
 const path='chat_media/alice.bob/alice/old-token';await uploadChat(backend,'alice',path,png,'image/png');
 const file=services.bucket.file(path);await file.setMetadata({metadata:{firebaseStorageDownloadTokens:'old-token-fixture'}});
 const url=`http://127.0.0.1:${ports.storage}/v0/b/${project}.appspot.com/o/${encodeURIComponent(path)}?alt=media&token=old-token-fixture`;
 const before=await fetch(url);assert.equal(before.status,200);await before.body.cancel();
 await sealPrivateObject(file);const after=await fetch(url);assert.equal(after.status,403);
 assert.deepEqual((await file.download())[0],png);assert.ok(!(await file.getMetadata())[0].metadata?.firebaseStorageDownloadTokens);
});
test('Solicitud propia pendiente, sin acceso a solicitudes ajenas ni escritura cliente',async()=>{
 const {requestId}=await backend.begin('pending');
 assert.equal((await backend.begin('pending')).requestId,requestId);
 await assertSucceeds(getDoc(doc(context('pending').firestore(),'verificationRequests/'+requestId)));
 await assertSucceeds(getDocs(query(collection(context('pending').firestore(),'verificationRequests'),where('uid','==','pending'),limit(20))));
 await assertFails(getDoc(doc(context('alice').firestore(),'verificationRequests/'+requestId)));
 await assertFails(updateDoc(doc(context('pending').firestore(),'verificationRequests/'+requestId),{status:'approved'}));
});
async function ready(){const {requestId}=await backend.begin('pending');await backend.upload('pending',requestId,png);return requestId;}
test('Carnet decodificado, privado y sin token; solo lectura backend admin no propia',async()=>{
 const r=await ready(),data=(await services.db.doc('verificationRequests/'+r).get()).data(),[meta]=await services.bucket.file(data.documentPath).getMetadata();
 assert.equal(meta.contentType,'image/png');assert.ok(!meta.metadata?.firebaseStorageDownloadTokens);
 for(const uid of ['pending','alice','admin','root']){
  const file=ref(context(uid).storage(project+'.appspot.com'),data.documentPath);
  await assertFails(getMetadata(file));await assertFails(getDownloadURL(file));await assertFails(uploadBytes(file,png,{contentType:'image/png'}));
 }
 const response=await fetch(`http://127.0.0.1:${ports.storage}/v0/b/${project}.appspot.com/o/${encodeURIComponent(data.documentPath)}?alt=media`);assert.notEqual(response.status,200);
 await assert.rejects(backend.readDocument('pending',r));
 assert.ok((await backend.readDocument('admin',r)).length>0);
});
for(const [name,bytes]of [['HTML',Buffer.from('<html>fake</html>')],['SVG',Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>')],['vacío',Buffer.alloc(0)],['exceso',Buffer.alloc(5*1024*1024+1)]])test('Carnet rechaza contenido '+name,async()=>{
 const {requestId}=await backend.begin('pending');await assert.rejects(backend.upload('pending',requestId,bytes),e=>e.code==='invalid-image');
});
test('No hay aprobación sin documento, autoaprobación ni decisión doble',async()=>{
 const {requestId}=await backend.begin('pending');await assert.rejects(backend.decide('admin',requestId,'approved','verified'));
 await backend.upload('pending',requestId,png);await assert.rejects(backend.decide('pending',requestId,'approved','verified'));
 await services.db.doc('accountAccess/pending').update({role:'admin',verificationStatus:'approved'});
 await assert.rejects(backend.readDocument('pending',requestId));
 await assert.rejects(backend.decide('pending',requestId,'approved','verified'));
 await backend.decide('admin',requestId,'approved','verified');await assert.rejects(backend.decide('root',requestId,'rejected','other'));
});
test('Aprobar/rechazar actualiza autoridad, registra decisión y elimina carnet',async()=>{
 const r=await ready(),path=(await services.db.doc('verificationRequests/'+r).get()).data().documentPath;
 await backend.decide('admin',r,'approved','verified');assert.equal((await services.db.doc('accountAccess/pending').get()).data().verificationStatus,'approved');
 await assert.rejects(backend.readDocument('admin',r));await backend.cleanupDue();
 assert.equal((await services.bucket.file(path).exists())[0],false);
 const request=(await services.db.doc('verificationRequests/'+r).get()).data();assert.equal(request.documentStage,'deleted');assert.ok(!request.documentPath);
 const audit=await services.db.collection('administrativeAudit').get();assert.ok(audit.size>0);
 for(const row of audit.docs){assert.deepEqual(Object.keys(row.data()).sort(),['actorId','targetId','action','reasonCode','requestId','at'].sort());}
});
test('Limpieza reintenta sin volver a permitir revisión de un carnet resuelto',async()=>{
 const r=await ready();await backend.decide('admin',r,'rejected','unreadable');
 const failing=new VerificationBackend({...services,bucket:{file:()=>({delete:async()=>{throw new Error('offline');}})}});
 await failing.cleanupDue();const job=(await services.db.doc('verificationCleanup/'+r).get()).data();assert.equal(job.attempts,1);assert.equal(job.state,'pending');
 await assert.rejects(backend.readDocument('root',r));await backend.cleanupDue(Date.now()+180000);
 assert.equal((await services.db.doc('verificationCleanup/'+r).get()).data().state,'done');
});
test('Retiro de solicitud y expiración limpian documentos sin aprobar',async()=>{
 const r=await ready();await backend.withdraw('pending',r);await backend.cleanupDue();
 const next=(await backend.begin('pending')).requestId;assert.notEqual(next,r);
 await services.db.doc('verificationRequests/'+next).update({expiresAt:Timestamp.fromMillis(1)});await backend.cleanupDue();
 assert.equal((await services.db.doc('accountAccess/pending').get()).data().verificationStatus,'rejected');
});
test('Recupera carnet de subida interrumpida tras expirar la solicitud',async()=>{
 const {requestId}=await backend.begin('pending'),path=`university_cards/pending/${requestId}/document`;
 await services.db.doc('verificationRequests/'+requestId).update({documentStage:'uploading',documentPath:path,expiresAt:Timestamp.fromMillis(1)});
 await services.bucket.file(path).save(png,{resumable:false,metadata:{contentType:'image/png'}});
 await backend.cleanupDue();assert.equal((await services.bucket.file(path).exists())[0],false);
});
test('Gestión de roles solo superadmin, nunca rol propio; último protegido',async()=>{
 await assert.rejects(backend.changeRole('admin','alice','superadmin'));await assert.rejects(backend.changeRole('root','root','user'));
 await assert.rejects(backend.suspend('root','root',true,'safety'));await assert.rejects(backend.suspend('admin','root',true,'safety'));
 await backend.changeRole('root','alice','admin');assert.equal((await services.db.doc('accountAccess/alice').get()).data().role,'admin');
 await backend.changeRole('root','pending','admin');
 assert.equal((await services.db.doc('accountAccess/pending').get()).data().verificationStatus,'pending');
 await assert.rejects(backend.suspend('pending','alice',true,'safety'));
 await backend.changeRole('root','root2','superadmin');await backend.changeRole('root','root2','user');
 assert.deepEqual((await services.db.doc('administration/roles').get()).data().superadminIds,['root']);
});
test('Demociones simultáneas conservan un superadmin y actor revocado pierde permisos',async()=>{
 await backend.changeRole('root','root2','superadmin');
 const results=await Promise.allSettled([backend.changeRole('root','root2','user'),backend.changeRole('root2','root','user')]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal((await services.db.doc('administration/roles').get()).data().superadminIds.length,1);
});
test('Admin suspendido pierde facultades inmediatamente; no puede suspender administradores',async()=>{
 await backend.changeRole('root','root2','admin');
 await assert.rejects(backend.suspend('admin','root2',true,'safety'));
 await backend.suspend('root','admin',true,'safety');await assert.rejects(backend.suspend('admin','alice',true,'safety'));
});
test('Reportes se revisan en servidor sin auto-revisión y sin auditoría de texto sensible',async()=>{
 await services.db.doc('reports/alice.bob').set({reporterId:'alice',reportedId:'bob',status:'pending',details:'privado'});
 await backend.reviewReport('admin','alice.bob','reviewed');
 await assert.rejects(backend.reviewReport('alice','alice.bob','reviewed'));
});

test('Fase4: historial paginado sin rutas privadas y con fechas ISO',async()=>{
 const r=await ready();await backend.decide('admin',r,'rejected','unreadable');
 const history=await backend.listRequests('root',{status:'rejected'});
 assert.equal(history.length,1);assert.equal(history[0].id,r);assert.equal(history[0].reasonCode,'unreadable');
 assert.ok(!('documentPath' in history[0]));assert.ok(!('generation' in history[0]));assert.equal(typeof history[0].createdAt,'string');
 assert.equal(history[0].canReview,false);assert.equal((await backend.listRequests('root',{status:'rejected',cursor:r})).length,0);
 await assert.rejects(backend.listRequests('pending',{status:'rejected'}));await assert.rejects(backend.listRequests('admin',{status:'all'}));
});
test('Fase4: usuario solo consulta su solicitud actual sin secretos',async()=>{
 const r=await ready(),own=await backend.ownRequest('pending');assert.equal(own.id,r);assert.equal(own.documentStage,'ready');
 assert.equal(await backend.ownRequest('bob'),null);assert.ok(!JSON.stringify(own).includes('university_cards'));assert.ok(!('generation' in own));
 await backend.suspend('admin','pending',true,'safety');await assert.rejects(backend.ownRequest('pending'));
});
test('Fase4: auditoría solo superadmin y sin datos sensibles',async()=>{
 const r=await ready();await backend.decide('admin',r,'rejected','unreadable');
 for(const uid of ['pending','alice','admin'])await assert.rejects(backend.listAudit(uid));
 const rows=await backend.listAudit('root');assert.equal(rows.length,1);assert.equal(rows[0].action,'verification_rejected');
 assert.deepEqual(Object.keys(rows[0]).sort(),['id','actorId','targetId','action','reasonCode','requestId','at'].sort());
 assert.equal((await backend.listAudit('root',rows[0].id)).length,0);
});
test('Fase4: reenvío real rechazado conserva historial y aprobación habilita citas',async()=>{
 const old=await ready();await backend.decide('admin',old,'rejected','unreadable');const {requestId}=await backend.begin('pending');assert.notEqual(old,requestId);
 await services.db.doc('users/pending').set({isActive:false,datingAllowed:false});
 await backend.upload('pending',requestId,png);await backend.decide('root',requestId,'approved','verified');
 assert.equal((await services.db.doc('users/pending').get()).data().datingAllowed,true);
 assert.equal((await services.db.doc('verificationRequests/'+old).get()).data().status,'rejected');
 assert.equal((await backend.listRequests('admin',{status:'approved'}))[0].id,requestId);
 await backend.cleanupDue();await assert.rejects(backend.readDocument('admin',requestId));
});
test('Fase4: dos administradores simultáneos obtienen una sola decisión y conflicto explícito',async()=>{
 const r=await ready();const results=await Promise.allSettled([backend.decide('admin',r,'approved','verified'),backend.decide('root',r,'rejected','other')]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'conflict');
 assert.equal((await services.db.collection('administrativeAudit').get()).size,1);
});
test('Fase4: no aprobar un carnet cuya solicitud venció antes del worker',async()=>{
 const r=await ready();await services.db.doc('verificationRequests/'+r).update({expiresAt:Timestamp.fromMillis(Date.now()-1)});
 await assert.rejects(backend.decide('admin',r,'approved','verified'),e=>e.code==='conflict');
 assert.equal((await services.db.doc('accountAccess/pending').get()).data().verificationStatus,'pending');
});
test('Fase4: reportes sin metadatos extra y sin doble resolución',async()=>{
 await services.db.doc('reports/fase4').set({reporterId:'alice',reportedId:'bob',reason:'spam',details:'Ficticio',status:'pending',createdAt:Timestamp.now(),secret:'no debe salir'});
 const rows=await backend.listReports('admin');assert.equal(rows.length,1);assert.ok(!('secret' in rows[0]));assert.equal(typeof rows[0].createdAt,'string');
 await backend.reviewReport('admin','fase4','reviewed');await assert.rejects(backend.reviewReport('root','fase4','dismissed'),e=>e.code==='conflict');
});
test('Fase4: paginación de 25 solicitudes permite acceder a todos los registros',async()=>{
 for(let i=0;i<25;i++)await services.db.doc('verificationRequests/page'+String(i).padStart(2,'0')).set({uid:'pending',status:'rejected',documentStage:'deleted',createdAt:Timestamp.now()});
 const first=await backend.listRequests('admin',{status:'rejected'}),second=await backend.listRequests('admin',{status:'rejected',cursor:first.at(-1).id});
 assert.equal(first.length,20);assert.equal(second.length,5);assert.equal(new Set([...first,...second].map(r=>r.id)).size,25);
});

test('Excepción provisional: privada, pendiente, sin citas ni autoaprobación, expira y no gestiona roles',async()=>{
 const requestId=await ready(),until=Timestamp.fromMillis(Date.now()+600000);
 await services.db.doc('accountAccess/pending').update({role:'superadmin',provisionalAdminUntil:until});
 await services.db.doc('administration/roles').set({superadminIds:['pending']});
 await services.db.doc('administration/provisionalBootstrap').set({uid:'pending',requestId,state:'active',scope:'online_test',independentReview:false,expiresAt:until});
 await services.db.doc('users/pending').set({datingAllowed:false,isActive:true});
 assert.ok((await backend.listRequests('pending')).some(r=>r.id===requestId&&r.canReview===false));
 await assert.rejects(backend.decide('pending',requestId,'approved','verified'));
 await assert.rejects(backend.readDocument('pending',requestId));
 await assert.rejects(backend.changeRole('pending','alice','admin'));
 const db=context('pending').firestore();await assertFails(getDoc(doc(db,'matches/alice.bob')));
 await assertFails(setDoc(doc(db,'accountAccess/pending'),{verificationStatus:'approved'}));
 await assertFails(setDoc(doc(db,'administration/provisionalBootstrap'),{expiresAt:new Date(Date.now()+99999999)}));
 const r=(await services.db.doc('verificationRequests/'+requestId).get()).data();
 const file=services.bucket.file(r.documentPath),[meta]=await file.getMetadata();assert.ok(!meta.metadata?.firebaseStorageDownloadTokens);
 await services.db.doc('accountAccess/pending').update({suspended:true});await assert.rejects(backend.listRequests('pending'));
 await services.db.doc('accountAccess/pending').update({suspended:false});
 await services.db.doc('administration/provisionalBootstrap').update({expiresAt:Timestamp.fromMillis(1)});await assert.rejects(backend.listRequests('pending'));
 assert.equal((await services.db.doc('accountAccess/pending').get()).data().verificationStatus,'pending');
 assert.equal((await services.db.doc('users/pending').get()).data().datingAllowed,false);
});
