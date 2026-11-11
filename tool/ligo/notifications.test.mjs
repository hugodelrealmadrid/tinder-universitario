import assert from 'node:assert/strict';
import {before,after,test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {Timestamp} from 'firebase-admin/firestore';
import {doc,collection,query,limit,getDoc,getDocs,setDoc,serverTimestamp} from 'firebase/firestore';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {ligoTestTarget} from './test-target.mjs';
import {emulatorServices} from '../backend/emulator.mjs';
import {Notifications} from '../backend/notifications.mjs';
import {requestHandler} from '../backend/http-handler.mjs';

const {project,ports,offset}=ligoTestTarget();
if(offset!==200)throw Error('Este test requiere emuladores secundarios, no staging activo.');
const alice='notice_test_alice',bob='notice_test_bob',outsider='notice_test_outsider';
const match=alice+'.'+bob;
const invalid='invalid_fictional_fcm_device_00000000';
const valid='valid_fictional_fcm_device_0000000000';
const old='expired_fictional_fcm_device_00000000';
let services,worker,env,server,origin;
const sends=[];
const readInbox=async user=>(await worker.inbox(user).get()).docs;
const totals=async user=>(await worker.totals(user).get()).data();
const event=async(id,sender=alice,extra={})=>{
 const path='matches/'+match+'/messages/'+id;
 await services.db.doc(path).set({senderId:sender,text:'SECRET MESSAGE',createdAt:Timestamp.now(),...extra});
 return path;
};
before(async()=>{
 services=await emulatorServices(project,ports);
 worker=new Notifications({...services,webOrigin:'https://staging.example.org',messaging:{async send(payload){
   sends.push(payload);
   if(payload.token===invalid)throw Object.assign(Error('secret token'),{code:'messaging/registration-token-not-registered'});
 }}});
 env=await initializeTestEnvironment({projectId:project,firestore:{
  host:'127.0.0.1',port:ports.firestore,rules:await readFile(new URL('../../firestore.rules',import.meta.url),'utf8'),
 }});
 for(const user of [alice,bob,outsider]){
   await services.auth.createUser({uid:user,email:user+'@ligo.test',emailVerified:true});
   await worker.account(user).set({role:'user',verificationStatus:'approved',suspended:false});
 }
 await services.db.doc('matches/'+match).set({users:[alice,bob],isActive:true,createdAt:Timestamp.now()});
 server=createServer(requestHandler(services,{notificationsEnabled:true}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 origin='http://127.0.0.1:'+server.address().port;
});
after(async()=>{
 await env?.cleanup();
 if(server)await new Promise(resolve=>server.close(resolve));
 await services?.db.terminate();
});
test('Inbox exacto: match y mensajes idempotentes, sin autoavisos ni datos privados',async()=>{
 await Promise.all([worker.event('matches/'+match),worker.event('matches/'+match)]);
 const path=await event('notice_message');
 const [delivery]=await worker.event(path);
 await worker.event(path);
 assert.equal(delivery.recipient,bob);
 assert.equal((await readInbox(alice)).length,1);
 const rows=await readInbox(bob);
 assert.equal(rows.length,2);
 assert.equal(rows.find(row=>row.id===delivery.id).get('kind'),'message');
 assert.deepEqual(await totals(bob),{unread:2,messages:1});
 assert.ok(!JSON.stringify(rows.map(doc=>doc.data())).includes('SECRET'));
 await worker.event(await event('notice_foreign',outsider));
 assert.equal((await readInbox(outsider)).length,0);
 await assert.rejects(worker.mark(alice,delivery.id),e=>e.code==='not-found');
 await services.db.doc(path).update({readAt:Timestamp.now()});
 await worker.event(path);
 await worker.mark(bob,delivery.id);
 assert.deepEqual(await totals(bob),{unread:1,messages:0});
 const own=env.authenticatedContext(bob).firestore();
 const foreign=env.authenticatedContext(alice).firestore();
 const ref='notificationInboxes/'+bob+'/items';
 await assertSucceeds(getDoc(doc(own,ref+'/'+delivery.id)));
 await assertSucceeds(getDocs(query(collection(own,ref),limit(25))));
 await assertFails(getDocs(collection(own,ref)));
 await assertFails(getDoc(doc(foreign,ref+'/'+delivery.id)));
 await assertFails(setDoc(doc(own,ref+'/'+delivery.id),{kind:'forged'}));
 const forged=doc(own,'matches/'+match+'/messages/forged_story_reply');
 await assertFails(setDoc(forged,{senderId:bob,text:'Texto',type:'text',createdAt:serverTimestamp(),storyReply:true}));
});
test('Varios dispositivos, push genérico, token inválido y caducidad',async()=>{
 for(const [token,platform] of [[valid,'android'],[invalid,'web'],[old,'web']])await worker.device(bob,token,platform);
 const devices=await services.db.collection('notificationDevices').where('uid','==',bob).get();
 const expired=devices.docs.find(doc=>doc.data().token===old);
 await expired.ref.update({expiresAt:Timestamp.fromMillis(Date.now()-1000)});
 const path=await event('notice_push_off');
 await worker.event(path);
 assert.equal(sends.length,0);
 await worker.preferences(bob,true);
 const next=await event('notice_push_on',alice,{storyReply:true});
 await Promise.all([worker.event(next),worker.event(next)]);
 assert.deepEqual(sends.map(x=>x.token).sort(),[valid,invalid].sort());
 for(const payload of sends){
   assert.equal(payload.notification.body,'Tienes una nueva notificación.');
   assert.deepEqual(Object.keys(payload.data),['notice']);
   assert.ok(!JSON.stringify(payload).includes('SECRET'));
 }
 const remaining=await services.db.collection('notificationDevices').where('uid','==',bob).get();
 assert.equal(remaining.size,1);
 const own=env.authenticatedContext(bob).firestore();
 await assertFails(getDoc(doc(own,remaining.docs[0].ref.path)));
 await worker.device(outsider,valid,null,true);
 assert.equal((await remaining.docs[0].ref.get()).exists,true);
 await worker.device(bob,valid,null,true);
 assert.equal((await remaining.docs[0].ref.get()).exists,false);
});
test('Suspensión, bloqueo, acreditación y operaciones HTTP sin sesión',async()=>{
 const before=await totals(bob);
 await services.db.doc('blocks/'+alice+'.'+bob).set({blockerId:alice,blockedId:bob});
 await worker.event(await event('blocked'));
 assert.deepEqual(await totals(bob),before);
 await services.db.doc('blocks/'+alice+'.'+bob).delete();
 await worker.account(bob).update({suspended:true});
 await worker.event(await event('suspended'));
 assert.deepEqual(await totals(bob),before);
 const own=env.authenticatedContext(bob).firestore();
 await assertFails(getDoc(doc(own,'notificationInboxes/'+bob)));
 const pendingPath='verificationRequests/notice_test_request';
 await worker.account(outsider).update({latestRequestId:'notice_test_request',verificationStatus:'rejected'});
 await services.db.doc(pendingPath).set({uid:outsider,status:'rejected',resolvedAt:Timestamp.now(),documentPath:'SECRET CARD'});
 await worker.event(pendingPath);
 await worker.event(pendingPath);
 const rows=await readInbox(outsider);
 assert.equal(rows.length,1);
 assert.equal(rows[0].data().status,'rejected');
 assert.ok(!JSON.stringify(rows[0].data()).includes('SECRET'));
 const pending=env.authenticatedContext(outsider).firestore();
 await assertSucceeds(getDoc(doc(pending,rows[0].ref.path)));
 const response=await fetch(origin+'/notifications/preferences',{method:'POST',headers:{'content-type':'application/json'},body:'{"push":true}'});
 assert.equal(response.status,401);
});

test('El endpoint administrativo confirma la acreditación y guarda el aviso en la misma transacción',async()=>{
 const admin='notice_direct_admin',student='notice_direct_student',requestId='notice_direct_request';
 const password='Fictional-test-pass-2026!';
 await services.auth.createUser({uid:admin,email:admin+'@ligo.test',password,emailVerified:true});
 await worker.account(admin).set({role:'admin',verificationStatus:'approved',suspended:false});
 await worker.account(student).set({role:'user',verificationStatus:'pending',suspended:false,latestRequestId:requestId});
 const ref=services.db.doc('verificationRequests/'+requestId);
 await ref.set({uid:student,status:'pending',documentStage:'ready',expiresAt:Timestamp.fromMillis(Date.now()+60000),documentPath:'university_cards/'+student+'/'+requestId+'/document'});
 const session=await fetch('http://127.0.0.1:'+ports.auth+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:admin+'@ligo.test',password,returnSecureToken:true}),
 });
 assert.equal(session.status,200);
 const headers={Authorization:'Bearer '+(await session.json()).idToken,'Content-Type':'application/json'};
 const decide=()=>fetch(origin+'/verification/decide',{method:'POST',headers,body:JSON.stringify({requestId,status:'approved',reasonCode:'verified'})});
 assert.equal((await decide()).status,200);
 assert.equal((await ref.get()).get('status'),'approved');
 const notices=await readInbox(student);
 assert.equal(notices.length,1);
 assert.equal(notices[0].get('status'),'approved');
 assert.equal((await decide()).status,409);
 await new Notifications(services).event(ref.path);
 assert.equal((await readInbox(student)).length,1);
 assert.deepEqual(await totals(student),{unread:1});
});

test('Los endpoints de LIGO 2.0 escriben match, mensaje, medio y recibo con avisos atómicos',async()=>{
 const a='notice_api_a',b='notice_api_b',id=a+'.'+b,career='notice_api_career';
 const password='Fictional-test-pass-2026!';
 const headers={};
 await services.db.doc('careers/'+career).set({name:'Sistemas',isActive:true});
 for(const uid of [a,b]){
  await services.auth.createUser({uid,email:uid+'@ligo.test',password,emailVerified:true});
  await worker.account(uid).set({role:'user',verificationStatus:'approved',suspended:false});
  await services.db.doc('users/'+uid).set({firstName:'Prueba',lastName:'LIGO',gender:'masculino',isActive:true,datingAllowed:true,birthDate:Timestamp.fromDate(new Date('2000-01-01')),careerId:career,mainPhotoUrl:'ficticia',photoUrls:['ficticia']});
  await services.db.doc('preferences/'+uid).set({minAge:18,maxAge:100,preferredGender:'ambos'});
  await services.db.doc('discoveryCards/'+uid).set({isActive:true});
  const login=await fetch('http://127.0.0.1:'+ports.auth+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',{
   method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:uid+'@ligo.test',password,returnSecureToken:true}),
  });
  assert.equal(login.status,200);
  headers[uid]={Authorization:'Bearer '+(await login.json()).idToken,'Content-Type':'application/json'};
 }
 const post=(uid,route,data)=>fetch(origin+route,{method:'POST',headers:headers[uid],body:JSON.stringify(data)});
 const invalid=await post(a,'/discovery/decide',{target:b,type:'like',senderId:b});
 assert.equal(invalid.status,400);
 await services.db.doc('preferences/'+b).update({preferredGender:'femenino'});
 assert.equal((await post(a,'/discovery/decide',{target:b,type:'like'})).status,403);
 await services.db.doc('preferences/'+b).update({preferredGender:'ambos'});
 const decisions=await Promise.all([post(a,'/discovery/decide',{target:b,type:'like'}),post(b,'/discovery/decide',{target:a,type:'like'})]);
 assert.ok(decisions.every(r=>r.status===200));
 assert.equal((await Promise.all(decisions.map(r=>r.json()))).filter(r=>r.createdMatch).length,1);
 assert.equal((await services.db.doc('matches/'+id).get()).exists,true);
 assert.deepEqual(await totals(a),{unread:1});
 const message={matchId:id,messageId:'api_text',text:'Texto ficticio'};
 assert.equal((await post(a,'/chat/send',message)).status,200);
 assert.equal((await post(a,'/chat/send',message)).status,200);
 assert.equal((await post(a,'/chat/send',{...message,text:'Otro'})).status,409);
 const voice={matchId:id,messageId:'api_voice',type:'audio',text:'',durationMs:3000};
 assert.equal((await post(a,'/chat/send',voice)).status,403);
 await services.db.doc('chatUploads/'+id+'.api_voice').set({state:'ready',expiresAt:Timestamp.fromMillis(Date.now()+60000),path:'chat_media/'+id+'/'+a+'/api_voice',uid:a,matchId:id,type:'audio',durationMs:3000});
 assert.equal((await post(a,'/chat/send',voice)).status,200);
 assert.deepEqual(await totals(b),{unread:3,messages:2});
 const receipt={matchId:id,messageId:'api_text'};
 assert.equal((await post(a,'/chat/receipt',receipt)).status,403);
 const reads=await Promise.all([post(b,'/chat/receipt',receipt),post(b,'/chat/receipt',receipt)]);
 assert.ok(reads.every(r=>r.status===200));
 assert.deepEqual(await totals(b),{unread:2,messages:1});
 assert.ok((await services.db.doc('matches/'+id+'/messages/api_text').get()).get('readAt'));
 const oldClient=env.authenticatedContext(a).firestore();
 await assertSucceeds(setDoc(doc(oldClient,'matches/'+id+'/messages/legacy_text'),{senderId:a,text:'Cliente anterior',createdAt:serverTimestamp()}));
 assert.equal((await post(b,'/chat/receipt',{matchId:id,messageId:'legacy_text'})).status,200);
 assert.deepEqual(await totals(b),{unread:2,messages:1});
 await worker.account(b).update({suspended:true});
 assert.equal((await post(a,'/chat/send',{...message,messageId:'blocked_by_suspension'})).status,403);
});
