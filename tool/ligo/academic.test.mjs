import {ligoTestTarget} from './test-target.mjs';
import {test,before,beforeEach,after} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,updateDoc,serverTimestamp,Timestamp as ClientTimestamp} from 'firebase/firestore';
import {Timestamp} from 'firebase-admin/firestore';import {emulatorServices} from '../backend/emulator.mjs';import {VerificationBackend} from '../backend/verification.mjs';import {CatalogBackend} from '../backend/catalogs.mjs';
const {project,ports}=ligoTestTarget();let env,s,b,c;const user=uid=>env.authenticatedContext(uid,{email:uid+'@ligo.test',email_verified:true}).firestore();
const access=(role='user')=>({role,verificationStatus:'approved',suspended:false});
const old=()=>({firstName:'Legado',lastName:'Ficticio',email:'legacy@ligo.test',birthDate:Timestamp.fromDate(new Date('2000-01-01')),gender:'masculino',description:'Fixture de compatibilidad',careerId:'legacy_career',interestIds:['legacy_interest'],photoUrls:['profile_photos/legacy/photo'],mainPhotoUrl:'profile_photos/legacy/photo',role:'user',isActive:true,datingAllowed:true,createdAt:Timestamp.fromMillis(Date.now()-86400000),updatedAt:Timestamp.fromMillis(Date.now()-10000)});
const initial=(uid,universityId=null,careerId=null)=>({firstName:'',lastName:'',email:uid+'@ligo.test',birthDate:ClientTimestamp.fromDate(new Date('2000-01-01')),gender:'',description:'',careerId,interestIds:[],photoUrls:[],mainPhotoUrl:null,role:'user',isActive:false,createdAt:serverTimestamp(),updatedAt:serverTimestamp(),...(universityId?{universityId}:{})});
let n=0;const op=(data,id=null,expectedRevision=null)=>({data,id,expectedRevision,requestId:'operation_'+(++n)});
before(async()=>{
 s=await emulatorServices(project,ports);b=new VerificationBackend(s);c=new CatalogBackend({db:s.db,authorize:(tx,uid)=>b.actor(tx,uid,true)});
 env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:ports.firestore,rules:await readFile(new URL('../../firestore.rules',import.meta.url),'utf8')},storage:{host:'127.0.0.1',port:ports.storage,rules:await readFile(new URL('../../storage.rules',import.meta.url),'utf8')}});
 for(const uid of ['root','admin','legacy','newstudent'])try{await s.auth.createUser({uid,email:uid+'@ligo.test',emailVerified:true,password:'Fixture-only-2026!'});}catch(e){if(e.code!=='auth/uid-already-exists'&&e.code!=='auth/email-already-exists')throw e;await s.auth.updateUser(uid,{email:uid+'@ligo.test',emailVerified:true,disabled:false,password:'Fixture-only-2026!'});}
});
beforeEach(async()=>{
 await env.clearFirestore();const db=s.db;
 for(const [id,data]of Object.entries({root:access('superadmin'),admin:access('admin'),legacy:access(),newstudent:{...access(),verificationStatus:'pending'}}))await db.doc('accountAccess/'+id).set(data);
 await db.doc('administration/roles').set({superadminIds:['root']});
 await db.doc('universities/uni_a').set({name:'Universidad Ficticia A',countryCode:'BO',city:'Cochabamba',isActive:true,revision:1});
 await db.doc('universities/uni_b').set({name:'Universidad Ficticia B',countryCode:'MX',city:'Ciudad de México',isActive:true,revision:1});
 await db.doc('careers/career_a').set({name:'Sistemas',universityId:'uni_a',isActive:true,revision:1});await db.doc('careers/career_b').set({name:'Sistemas',universityId:'uni_b',isActive:true,revision:1});
 await db.doc('careers/legacy_career').set({name:'Carrera histórica',isActive:true});await db.doc('interests/legacy_interest').set({name:'Música',isActive:true});await db.doc('interests/active_interest').set({name:'Deportes',isActive:true});
 await db.doc('users/legacy').set(old());await db.doc('profilePhotoManifests/legacy').set({paths:['profile_photos/legacy/photo']});await db.doc('matches/legacy.other').set({users:['legacy','other'],isActive:true,createdAt:Timestamp.now()});await db.doc('matches/legacy.other/messages/old').set({text:'Mensaje histórico ficticio',senderId:'legacy',type:'text',createdAt:Timestamp.now()});
 const created=(await db.doc('users/legacy').get()).createTime;await db.doc('platformSettings/academic').set({multiUniversityEnabled:true,legacyBefore:Timestamp.fromMillis(created.toMillis()+1)});
});

after(async()=>{await env.cleanup();await s.db.terminate();});
test('Usuario normal, pendiente y suspendido no gestionan catálogos; admin no gestiona universidades',async()=>{
 for(const uid of ['legacy','newstudent'])await assert.rejects(c.save(uid,'interests',op({name:'Nuevo',isActive:true})),e=>e.code==='permission-denied');
 await s.db.doc('accountAccess/admin').update({suspended:true});await assert.rejects(c.list('admin','careers'),e=>e.code==='permission-denied');await s.db.doc('accountAccess/admin').update({suspended:false});
 await assert.rejects(c.save('root','universities',op({name:'Universidad X',isActive:true})),e=>e.code==='invalid-argument');
 await assert.rejects(c.list('root','universities'),e=>e.code==='invalid-argument');
});
test('CRUD auditado, idempotente y sin eliminación física; no altera históricos',async()=>{
 const paths=['users/legacy','careers/legacy_career','interests/legacy_interest','matches/legacy.other','matches/legacy.other/messages/old','accountAccess/root','administration/roles'];const before=await Promise.all(paths.map(p=>s.db.doc(p).get()));
 const input=op({name:'Ingeniería Nueva',isActive:true});const created=await c.save('root','careers',input);const replay=await c.save('root','careers',input);assert.equal(replay.id,created.id);assert.equal(replay.idempotent,true);
 await c.save('root','careers',op({name:'Ingeniería Nueva',isActive:false},created.id,1));assert.equal((await s.db.doc('careers/'+created.id).get()).data().isActive,false);
 assert.equal((await s.db.collection('administrativeAudit').get()).size,2);
 const after=await Promise.all(paths.map(p=>s.db.doc(p).get()));for(let i=0;i<paths.length;i++){assert.deepEqual(after[i].data(),before[i].data());assert.ok(after[i].updateTime.isEqual(before[i].updateTime));}
});
test('Carreras generales rechazan duplicados nuevos y preservan homónimos históricos',async()=>{
 const created=await c.save('admin','careers',op({name:'Ingeniería Civil',isActive:true}));
 assert.equal((await s.db.doc('careers/'+created.id).get()).data().universityId,undefined);
 await assert.rejects(c.save('admin','careers',op({name:' INGENIERIA CIVIL ',isActive:true})),e=>e.code==='duplicate-catalog');
 await assert.rejects(c.save('admin','careers',op({name:'Sistemas',isActive:true})),e=>e.code==='duplicate-catalog');
 await c.save('admin','careers',op({name:'Sistemas',isActive:false},'career_a',1));
 assert.equal((await s.db.doc('careers/career_a').get()).data().universityId,'uni_a');
 assert.equal((await s.db.doc('careers/career_b').get()).data().isActive,true);
 await assert.rejects(c.save('admin','careers',op({name:'Antiguo',isActive:true},'career_a',1)),e=>e.code==='conflict');
 await assert.rejects(c.save('admin','interests',op({name:' MUSICA ',isActive:true})),e=>e.code==='duplicate-catalog');
 await assert.rejects(c.save('admin','careers',op({name:'Reasignación',universityId:'uni_b',isActive:true},'career_a',2)),e=>e.code==='invalid-argument');
});
test('Reglas deniegan escritura directa de catálogos, índices, política y roles incluso a admin',async()=>{
 for(const path of ['universities/x','careers/x','interests/x','catalogUniqueKeys/x','catalogOperations/x','platformSettings/academic','accountAccess/legacy'])await assertFails(setDoc(doc(user('admin'),path),{name:'Ataque',isActive:true}));
});
test('Registro admite perfil sin universidad, rechaza inyección de campo y menores',async()=>{
 await assertSucceeds(setDoc(doc(user('learner'),'users/learner'),initial('learner')));
 await assertFails(setDoc(doc(user('wrong'),'users/wrong'),initial('wrong','uni_a','career_a')));
 await assertFails(setDoc(doc(user('minor'),'users/minor'),{...initial('minor'),birthDate:ClientTimestamp.now()}));
 await assertFails(updateDoc(doc(user('learner'),'users/learner'),{universityId:'uni_b',updatedAt:serverTimestamp()}));
});
test('Desactivar carrera e interés permite conservar referencias y editar datos; no permite nuevas selecciones',async()=>{
 await s.db.doc('careers/legacy_career').update({isActive:false});await s.db.doc('interests/legacy_interest').update({isActive:false});
 await assertSucceeds(updateDoc(doc(user('legacy'),'users/legacy'),{description:'Descripción actualizada',interestIds:['legacy_interest','active_interest'],updatedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(doc(user('legacy'),'users/legacy'),{interestIds:['active_interest'],updatedAt:serverTimestamp()}));
 await assertFails(updateDoc(doc(user('legacy'),'users/legacy'),{interestIds:['active_interest','legacy_interest'],updatedAt:serverTimestamp()}));
});
test('Perfil histórico puede elegir cualquier carrera activa y conserva su campo histórico',async()=>{
 const ref=s.db.doc('users/legacy');
 await ref.update({universityId:'historical_missing_university'});
 await assertSucceeds(updateDoc(doc(user('legacy'),'users/legacy'),{careerId:'career_b',updatedAt:serverTimestamp()}));
 assert.equal((await ref.get()).data().universityId,'historical_missing_university');
 await assertFails(updateDoc(doc(user('legacy'),'users/legacy'),{universityId:'uni_a',updatedAt:serverTimestamp()}));
});
test('Solicitud nueva usa acreditación general y mantiene intacta la evidencia previa',async()=>{
 await s.db.doc('verificationRequests/old').set({uid:'legacy',status:'rejected',institution:'univalle_cochabamba'});
 await s.db.doc('accountAccess/legacy').update({verificationStatus:'rejected',latestRequestId:'old'});
 const r=await b.begin('legacy');
 const value=(await s.db.doc('verificationRequests/'+r.requestId).get()).data();
 assert.equal(value.institution,'university_student');
 assert.equal(value.universityId,undefined);
 assert.equal((await s.db.doc('verificationRequests/old').get()).data().institution,'univalle_cochabamba');
});
test('Preferencias ignoran datos históricos y no permiten agregarlos ni modificarlos',async()=>{
 const db=user('legacy');const ref=doc(db,'preferences/legacy');const prefs={minAge:18,maxAge:100,preferredGender:'ambos',updatedAt:serverTimestamp()};
 await assertFails(setDoc(ref,{...prefs,universityIds:['uni_a']}));
 await assertSucceeds(setDoc(ref,prefs));
 await s.db.doc('preferences/legacy').update({universityIds:['uni_a']});
 await assertFails(updateDoc(ref,{universityIds:['uni_b'],updatedAt:serverTimestamp()}));
 await assertSucceeds(updateDoc(ref,{minAge:19,careerIds:['career_b'],updatedAt:serverTimestamp()}));
});
import {createServer} from 'node:http';
import {writeBatch} from 'firebase/firestore';
import {requestHandler} from '../backend/http-handler.mjs';
import {imageFixture,audioFixture} from '../test-media.mjs';
import {uploadChat} from '../backend/chat-upload.mjs';
import {readChat} from '../backend/chat-read.mjs';
async function tokenFor(uid){const r=await fetch(`http://127.0.0.1:${ports.auth}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fixture-only`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:uid+'@ligo.test',password:'Fixture-only-2026!',returnSecureToken:true})});const data=await r.json();assert.ok(data.idToken);return data.idToken;}

test('API HTTP con tokens reales del emulador protege CRUD y registra la operación',async()=>{
 const server=createServer(requestHandler(s,{origins:['http://127.0.0.1:7465']}));await new Promise(ok=>server.listen(0,'127.0.0.1',ok));const url='http://127.0.0.1:'+server.address().port;
 try{
  assert.equal((await fetch(url+'/administration/catalogs/careers')).status,401);
  const admin=await tokenFor('admin'),student=await tokenFor('legacy');
  const payload={kind:'universities',...op({name:'Universidad HTTP',countryCode:'BO',city:'Tarija',isActive:true})};
  assert.equal((await fetch(url+'/administration/catalog',{method:'POST',headers:{Authorization:'Bearer '+admin,'Content-Type':'application/json'},body:JSON.stringify(payload)})).status,400);
  assert.equal((await fetch(url+'/administration/catalogs/careers',{headers:{Authorization:'Bearer '+student}})).status,403);
  const r=await fetch(url+'/administration/catalog',{method:'POST',headers:{Authorization:'Bearer '+admin,'Content-Type':'application/json'},body:JSON.stringify({kind:'interests',...op({name:'Interés HTTP',isActive:true})})});assert.equal(r.status,200);const result=await r.json();assert.equal((await s.db.doc('interests/'+result.id).get()).exists,true);
 }finally{server.closeAllConnections();await new Promise(ok=>server.close(ok));}
});
test('Duplicados concurrentes no crean dos documentos; metadatos y países inválidos son rechazados',async()=>{
 const results=await Promise.allSettled([c.save('admin','interests',op({name:'Lectura',isActive:true})),c.save('root','interests',op({name:' LECTURA ',isActive:true}))]);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal(results.find(x=>x.status==='rejected').reason.code,'duplicate-catalog');
 for(const data of [{name:'Universidad',isActive:true,countryCode:'ZZ',city:'Ciudad'},{name:'Universidad',isActive:true,countryCode:'BO',city:'Ciudad',role:'superadmin'},{name:'',isActive:true,countryCode:'BO',city:'Ciudad'}])await assert.rejects(c.save('root','universities',op(data)),e=>e.code==='invalid-argument');
});
test('Lista administrativa pagina sin exponer campos privados o permitir cambios de rol',async()=>{
 const batch=s.db.batch();for(let i=0;i<55;i++)batch.set(s.db.doc('interests/page_'+i.toString().padStart(3,'0')),{name:'Elemento '+i,isActive:true,secret:'No devolver'});await batch.commit();
 const first=await c.list('admin','interests');assert.equal(first.items.length,50);assert.ok(first.nextCursor);assert.ok(first.items.every(x=>!('secret'in x)));const second=await c.list('admin','interests',first.nextCursor);assert.ok(second.items.length>0);assert.ok(!second.items.some(x=>first.items.some(a=>a.id===x.id)));
 await assert.rejects(b.changeRole('admin','legacy','admin'),e=>e.code==='permission-denied');
});
test('Flujo nuevo + histórico: carnet, aprobación, filtros recíprocos, match, texto, foto, audio y suspensión',async()=>{
 const before=(await s.db.doc('users/legacy').get()).data();
 const p={...old(),firstName:'Nueva',gender:'femenino',email:'newstudent@ligo.test',careerId:'career_b',photoUrls:['profile_photos/newstudent/photo'],mainPhotoUrl:'profile_photos/newstudent/photo',datingAllowed:false,createdAt:Timestamp.now()};await s.db.doc('users/newstudent').set(p);
 const request=await b.begin('newstudent');await b.upload('newstudent',request.requestId,await imageFixture());await b.decide('root',request.requestId,'approved','verified');
 assert.equal((await s.db.doc('accountAccess/newstudent').get()).data().verificationStatus,'approved');
 const card=x=>({firstName:x.firstName,age:new Date().getUTCFullYear()-2000,gender:x.gender,description:x.description,careerId:x.careerId,mainPhotoUrl:x.mainPhotoUrl,interestIds:x.interestIds,isActive:x.isActive,updatedAt:x.updatedAt,...(x.universityId?{universityId:x.universityId}:{})});
 for(const uid of ['legacy','newstudent']){const x=(await s.db.doc('users/'+uid).get()).data();await s.db.doc('discoveryCards/'+uid).set(card(x));await s.db.doc('matchProfiles/'+uid).set({...card(x),photoUrls:x.photoUrls});await s.db.doc('preferences/'+uid).set({minAge:18,maxAge:100,preferredGender:'ambos',careerIds:[],updatedAt:Timestamp.now(),...(uid==='legacy'?{universityIds:['uni_b']}:{universityIds:['uni_a']})});}
 await assertSucceeds(getDoc(doc(user('legacy'),'discoveryCards/newstudent')));
 await assertSucceeds(setDoc(doc(user('legacy'),'swipes/legacy.newstudent'),{fromUserId:'legacy',toUserId:'newstudent',type:'like',createdAt:serverTimestamp()}));
 const senderDb=user('newstudent');const batch=writeBatch(senderDb);batch.set(doc(senderDb,'swipes/newstudent.legacy'),{fromUserId:'newstudent',toUserId:'legacy',type:'like',createdAt:serverTimestamp()});batch.set(doc(senderDb,'matches/legacy.newstudent'),{users:['legacy','newstudent'],isActive:true,createdAt:serverTimestamp()});await assertSucceeds(batch.commit());
 const path='matches/legacy.newstudent/messages/text';await assertSucceeds(setDoc(doc(user('legacy'),path),{senderId:'legacy',text:'Mensaje de staging',type:'text',createdAt:serverTimestamp()}));await assertSucceeds(updateDoc(doc(user('newstudent'),path),{readAt:serverTimestamp()}));
 for(const [type,mime,bytes] of [['image','image/png',await imageFixture()],['audio','audio/wav',await audioFixture()]]){
  const media='chat_media/legacy.newstudent/legacy/'+type;await uploadChat(b,'legacy',media,bytes,mime);
  await assertSucceeds(setDoc(doc(user('legacy'),'matches/legacy.newstudent/messages/'+type),{senderId:'legacy',text:'',type,mediaPath:media,createdAt:serverTimestamp()}));
  const download=await readChat(b,'newstudent',media,true);assert.deepEqual(download.bytes,bytes);await assert.rejects(readChat(b,'admin',media,true),e=>e.code==='permission-denied');
 }
 await b.suspend('admin','newstudent',true,'safety');await assertFails(getDoc(doc(user('newstudent'),path)));await assert.rejects(readChat(b,'legacy','chat_media/legacy.newstudent/legacy/audio',true),e=>e.code==='permission-denied');
 assert.deepEqual((await s.db.doc('users/legacy').get()).data(),before);
});

test('Fase 4: registro por sede, preferencia universitaria y compatibilidad histórica',async()=>{
 const {programs,universities}=await import('./bolivia-academic-catalog.mjs');
 const {collection,getDocs,query,where}=await import('firebase/firestore');
 const batch=s.db.batch();
 for(const [id,name] of Object.entries(programs))batch.set(s.db.doc('careers/'+id),{name,isActive:true});
 for(const [id,name,,campuses] of universities.slice(0,4)){
   const root='universities/'+id;
   batch.set(s.db.doc(root),{name,directory:true,isActive:true});
   for(const [campus,label,,,ids] of campuses){
     batch.set(s.db.doc(root+'/campuses/'+campus),{name:label,isActive:true});
     for(const career of ids)batch.set(s.db.doc(root+'/campuses/'+campus+'/offerings/'+career),{name:programs[career],isActive:true});
   }
 }
 batch.update(s.db.doc('platformSettings/academic'),{campusRegistrationEnabled:true});
 await batch.commit();
 const choices=[
   ['univalle','cochabamba','sistemas'],['umss','central','sistemas_general'],
   ['ucb','cochabamba','sistemas_general'],['unifranz','cochabamba','medicina'],
 ];
 for(const [university,campus,career] of choices){
  const uid='registration_'+university;
  await assertSucceeds(setDoc(doc(user(uid),'users/'+uid),{...initial(uid,university,career),campusId:campus}));
 }
 const client=env.unauthenticatedContext().firestore();
 await assertFails(getDocs(query(collection(client,'universities'),
   where('directory','==',true),where('isActive','==',true))));
 await assertFails(getDoc(doc(client,'universities/uni_a')));
 await assertFails(getDocs(query(collection(client,'universities/ucb/campuses/cochabamba/offerings'),where('isActive','==',true))));
 await assertFails(setDoc(doc(user('bad'),'users/bad'),{...initial('bad','ucb','sistemas'),campusId:'cochabamba'}));
 await assertFails(setDoc(doc(user('no_affiliation'),'users/no_affiliation'),initial('no_affiliation')));
 const prepared=s.db.batch();
 const profiles=[
  ['legacy',null,'legacy_career','masculino'],
  ['viewer','ucb','sistemas_general','femenino'],
  ['same','ucb','sistemas_general','masculino'],
  ['different','umss','sistemas_general','masculino'],
 ];
 const age=new Date().getUTCFullYear()-2000;
 for(const [uid,university,careerId,gender] of profiles){
  const affiliation=university?{universityId:university}:{};
  const photo='profile_photos/'+uid+'/photo';
  const data={...old(),...affiliation,gender,careerId,photoUrls:[photo],mainPhotoUrl:photo};
  prepared.set(s.db.doc('users/'+uid),data);
  prepared.set(s.db.doc('discoveryCards/'+uid),{...affiliation,gender,careerId,age,firstName:data.firstName,description:data.description,
    interestIds:data.interestIds,isActive:true,mainPhotoUrl:photo,updatedAt:data.updatedAt});
  prepared.set(s.db.doc('preferences/'+uid),{minAge:18,maxAge:100,preferredGender:'ambos',careerIds:[],updatedAt:Timestamp.now()});
 }
 await prepared.commit();
 const viewer=user('viewer');
 const prefs=doc(viewer,'preferences/viewer');
 const filter=(universityMode,extra={})=>({universityMode,minAge:18,maxAge:100,preferredGender:'ambos',
   careerIds:[],updatedAt:serverTimestamp(),...extra});
 const card=uid=>getDoc(doc(viewer,'discoveryCards/'+uid));
 await assertSucceeds(setDoc(prefs,filter('all')));
 await assertSucceeds(card('legacy'));
 await assertSucceeds(card('different'));
 await assertSucceeds(setDoc(prefs,filter('mine')));
 await assertSucceeds(card('same'));
 await assertFails(card('different'));
 await assertFails(card('legacy'));
 await assertSucceeds(setDoc(prefs,filter('selected',{universityIds:['umss'],careerIds:['sistemas_general'],
    interestIds:['legacy_interest'],minAge:age,maxAge:age})));
 await assertSucceeds(card('different'));
 await assertFails(card('same'));
 await assertFails(card('legacy'));
 await assertSucceeds(setDoc(prefs,filter('selected',{universityIds:['umss'],maxAge:age-1})));
 await assertFails(card('different'));
 await assertFails(setDoc(prefs,filter('selected',{universityIds:['missing']})));
});
test('Fase 4: administración de universidad, sede y oferta solo para superadmin',async()=>{
 const {AcademicAdmin}=await import('../backend/academic-admin.mjs');
 const directory=new AcademicAdmin(b);
 const data={name:'Universidad ficticia nueva',city:'Oruro',abbreviation:'UFN',countryCode:'BO',isActive:true};
 await assert.rejects(directory.save('admin',{data}),e=>e.code==='permission-denied');
 await assert.rejects(directory.list('legacy',{}),e=>e.code==='permission-denied');
 const university=(await directory.save('root',{data})).id;
 const campus=(await directory.save('root',{university,data:{name:'Campus central',city:'Oruro',isActive:true}})).id;
 const offering={university,campus,target:'career_a',data:{isActive:true,source:'https://universidad.example/oferta',verifiedOn:'2026-01-01'}};
 await directory.save('root',offering);
 assert.equal((await directory.list('root',{university,campus})).items[0].name,'Sistemas');
 await assert.rejects(directory.save('root',offering),e=>e.code==='conflict');
 await directory.save('root',{...offering,revision:1,data:{isActive:false}});
 assert.equal((await directory.list('root',{university,campus})).items[0].isActive,false);
 assert.equal((await s.db.doc('careers/career_a').get()).data().isActive,true);
 assert.equal((await s.db.collection('administrativeAudit').get()).size,4);
});

test('Registro guiado: directorio refleja la desactivación y el alta es atómica',async()=>{
 const {registrationOptions}=await import('../backend/registration-directory.mjs');
 const {createServer}=await import('node:http');
 const {requestHandler}=await import('../backend/http-handler.mjs');
 const root='universities/uni_a';
 const campus=root+'/campuses/central';
 await s.db.doc(root).update({directory:true,createdBy:'fixture-admin',updatedBy:'fixture-admin'});
 await s.db.doc(campus).set({name:'Sede central',isActive:true,createdBy:'fixture-admin'});
 await s.db.doc(campus+'/offerings/career_a').set({name:'Nombre antiguo',isActive:true,secret:'no publicar'});
 await s.db.doc(campus+'/offerings/career_b').set({name:'Otra oferta',isActive:false});
 await s.db.doc('careers/career_a').update({secret:'no publicar'});
 await s.db.doc('platformSettings/academic').update({campusRegistrationEnabled:true});
 const server=createServer(requestHandler(s,{publicRegistrationEnabled:true}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base='http://127.0.0.1:'+server.address().port;
 const directory=async()=>{
   const response=await fetch(base+'/registration/options?kind=careers&university=uni_a&campus=central');
   assert.equal(response.status,200);
   return (await response.json()).items;
 };
 const pending=user('guided_new');
 const profile=doc(pending,'users/guided_new');
 const prefs=doc(pending,'preferences/guided_new');
 const batch=(interest='active_interest')=>{
   const write=writeBatch(pending);
   write.set(profile,{...initial('guided_new','uni_a','career_a'),firstName:'Ana',lastName:'Ficticia',
     campusId:'central',interestIds:[interest]});
   write.set(prefs,{minAge:20,maxAge:28,preferredGender:'ambos',universityMode:'mine',
     careerIds:['career_a'],interestIds:['active_interest'],updatedAt:serverTimestamp()});
   return write.commit();
 };
 try{
   assert.deepEqual(await directory(),[{id:'career_a',name:'Sistemas'}]);
   const universities=await (await fetch(base+'/registration/options?kind=universities')).json();
   assert.deepEqual(universities.items,[{id:'uni_a',name:'Universidad Ficticia A'}]);
   const campuses=await (await fetch(base+'/registration/options?kind=campuses&university=uni_a')).json();
   assert.deepEqual(campuses.items,[{id:'central',name:'Sede central'}]);
   for(const client of [env.unauthenticatedContext().firestore(),user('legacy')]){
     await assertFails(getDoc(doc(client,root)));
     await assertFails(getDoc(doc(client,campus)));
     await assertFails(getDoc(doc(client,campus+'/offerings/career_a')));
   }
   assert.equal((await fetch(base+'/administration/academic')).status,401);
   assert.equal((await fetch(base+'/administration/academic',{headers:{Authorization:'Bearer '+await tokenFor('legacy')}})).status,403);
   const interests=await (await fetch(base+'/registration/options?kind=interests')).json();
   assert.ok(interests.items.every(row=>Object.keys(row).sort().join(',')==='id,name'));
   assert.equal((await fetch(base+'/administration/users')).status,401);
   await s.db.doc('careers/career_a').update({isActive:false});
   assert.deepEqual(await directory(),[]);
   await assertFails(batch());
   assert.equal((await s.db.doc('users/guided_new').get()).exists,false);
   assert.equal((await s.db.doc('preferences/guided_new').get()).exists,false);
   await s.db.doc('careers/career_a').update({isActive:true});
   await assertFails(batch('missing'));
   await assertSucceeds(batch());
   assert.equal((await s.db.doc('users/guided_new').get()).data().firstName,'Ana');
   assert.equal((await s.db.doc('preferences/guided_new').get()).data().universityMode,'mine');
   await s.db.doc(campus).update({isActive:false});
   assert.deepEqual(await registrationOptions(s.db,'careers','uni_a','central'),[]);
   assert.equal((await s.db.doc('users/guided_new').get()).data().campusId,'central');
   await s.db.doc(campus).update({isActive:true});
   await s.db.doc(root).update({isActive:false});
   assert.deepEqual(await directory(),[]);
 }finally{
   await new Promise(resolve=>server.close(resolve));
 }
});

test('Una cuenta histórica inicia sesión y agrega sede una vez sin alterar sus datos',async()=>{
 const uid='legacy',ref=s.db.doc('users/'+uid),profile=doc(user(uid),'users/'+uid);
 const root='universities/uni_a',campus=root+'/campuses/central';
 await s.db.doc(root).update({directory:true});
 await s.db.doc(campus).set({name:'Central',isActive:true});
 await s.db.doc(campus+'/offerings/legacy_career').set({name:'Carrera histórica',isActive:true});
 await s.db.doc(campus+'/offerings/career_a').set({name:'Sistemas',isActive:true});
 await ref.update({universityId:'uni_a'});
 await s.db.doc('platformSettings/academic').update({campusRegistrationEnabled:true});
 const token=await tokenFor(uid);
 assert.equal((await s.auth.verifyIdToken(token)).uid,uid);
 const history=['accountAccess/legacy','profilePhotoManifests/legacy','matches/legacy.other','matches/legacy.other/messages/old','administration/roles'];
 const before=await Promise.all(history.map(path=>s.db.doc(path).get()));
 const oldProfile=(await ref.get()).data();
 const affiliation={universityId:'uni_a',campusId:'central',careerId:'legacy_career',updatedAt:serverTimestamp()};
 await assertFails(updateDoc(profile,{...affiliation,universityId:'uni_b'}));
 await assertFails(updateDoc(profile,{...affiliation,careerId:'career_a'}));
 await assertFails(updateDoc(profile,{...affiliation,role:'admin'}));
 await assertFails(updateDoc(profile,{...affiliation,campusId:'unknown'}));
 await assertSucceeds(updateDoc(profile,affiliation));
 await assertFails(updateDoc(profile,{campusId:'other',updatedAt:serverTimestamp()}));
 const {campusId,updatedAt,...rest}=(await ref.get()).data();
 assert.equal(campusId,'central');
 assert.deepEqual(rest,Object.fromEntries(Object.entries(oldProfile).filter(([k])=>k!=='updatedAt')));
 const after=await Promise.all(history.map(path=>s.db.doc(path).get()));
 for(let i=0;i<history.length;i++)assert.ok(after[i].updateTime.isEqual(before[i].updateTime));
 assert.equal((await s.auth.getUser(uid)).uid,uid);
});
