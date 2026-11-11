import assert from 'node:assert/strict';
import {after,before,test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {Timestamp} from 'firebase-admin/firestore';
import {emulatorServices} from '../backend/emulator.mjs';
import {VerificationBackend} from '../backend/verification.mjs';
import {Notifications} from '../backend/notifications.mjs';
import {Stories} from '../backend/stories.mjs';
import {requestHandler} from '../backend/http-handler.mjs';
import {ligoTestTarget} from './test-target.mjs';

const {project,ports,offset}=ligoTestTarget();
assert.equal(offset,200,'Los tests requieren emuladores secundarios.');
const owner='story_alma',viewer='story_bruno',outsider='story_celia',pending='story_dario';
const match=owner+'.'+viewer;
const moderator='story_moderator';
const password='Test-story-local-2026!';
let services,stories,image,server,origin,now=Date.now();
const denied=error=>error.code==='permission-denied';
const invalid=error=>error.code==='invalid-media';

before(async()=>{
 services=await emulatorServices(project,ports);
 stories=new Stories(new VerificationBackend(services),{clock:()=>now});
 image=await readFile(new URL('../../staging/fixtures/ana-ficticia.png',import.meta.url));
 for(const [uid,name] of [[owner,'Alma'],[viewer,'Bruno'],[outsider,'Celia'],[pending,'Darío'],[moderator,'Moderación']]){
  await services.auth.createUser({uid,email:uid+'@ligo.test',password,emailVerified:true});
  await services.db.doc('accountAccess/'+uid).set({role:uid===moderator?'admin':'user',verificationStatus:uid===pending?'pending':'approved',suspended:false});
  await services.db.doc('users/'+uid).set({firstName:name});
 }
 await services.db.doc('matches/'+match).set({users:[owner,viewer],isActive:true,createdAt:Timestamp.now()});
 server=createServer(requestHandler(services,{storiesEnabled:true,notificationsEnabled:true}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 origin='http://127.0.0.1:'+server.address().port;
});
after(async()=>{
 if(server)await new Promise(resolve=>server.close(resolve));
 await services?.db.terminate();
});

test('Acceso autenticado, contenido privado y expiración exacta del servidor',async()=>{
 assert.equal((await fetch(origin+'/stories/feed')).status,401);
 await assert.rejects(stories.publish(pending,image,'image/png','Pendiente'),denied);
 await assert.rejects(stories.publish(owner,image,'image/jpeg','MIME falso'),invalid);
 const {id}=await stories.publish(owner,image,'image/png','Foto ficticia');
 const ref=stories.ref(id), data=(await ref.get()).data();
 assert.equal(data.expiresAt.toMillis()-data.publishedAt.toMillis(),86400000);
 assert.equal((await stories.feed(viewer)).groups[0].stories[0].seen,false);
 assert.equal((await stories.feed(outsider)).groups.length,0);
 const media=await stories.media(viewer,id);
 assert.equal(media.mime,'image/jpeg');
 assert.equal(media.bytes[0],0xff);
 const file=services.bucket.file(data.path);
 const [metadata]=await file.getMetadata();
 assert.equal(metadata.metadata?.firebaseStorageDownloadTokens,undefined);
 const session=await fetch('http://127.0.0.1:'+ports.auth+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:viewer+'@ligo.test',password,returnSecureToken:true}),
 });
 assert.equal(session.status,200);
 const headers={Authorization:'Bearer '+(await session.json()).idToken};
 assert.equal((await fetch(origin+'/stories/media?id='+id,{headers})).status,200);
 const direct=await fetch('http://127.0.0.1:'+ports.firestore+'/v1/projects/'+project+'/databases/(default)/documents/storyAssets/'+id,{headers});
 assert.equal(direct.status,403);
 const directStorage=await fetch('http://127.0.0.1:'+ports.storage+'/v0/b/'+services.bucket.name+'/o/'+encodeURIComponent(data.path)+'?alt=media',{headers});
 assert.ok([401,403].includes(directStorage.status),String(directStorage.status));
 await assert.rejects(stories.media(outsider,id),denied);
 const block=services.db.doc('blocks/'+viewer+'.'+owner);
 await block.set({blockerId:viewer,blockedId:owner});
 await assert.rejects(stories.media(viewer,id),denied);
 assert.equal((await stories.feed(viewer)).groups.length,0);
 await block.delete();
 const access=services.db.doc('accountAccess/'+viewer);
 await access.update({suspended:true});
 await assert.rejects(stories.media(viewer,id),denied);
 await access.update({suspended:false});
 await Promise.all([stories.view(viewer,id),stories.view(viewer,id)]);
 assert.deepEqual((await stories.viewers(owner,id)).items.map(x=>x.name),['Bruno']);
 await assert.rejects(stories.viewers(viewer,id),denied);
 assert.equal((await stories.feed(viewer)).groups[0].stories[0].seen,true);
 now=data.expiresAt.toMillis()-1;
 await stories.media(viewer,id);
 now++;
 await assert.rejects(stories.media(viewer,id),denied);
 assert.equal((await stories.feed(viewer)).groups.length,0);
 const runs=await Promise.all([stories.cleanup(),stories.cleanup()]);
 assert.equal(runs.reduce((sum,run)=>sum+run.deleted,0),1);
 assert.equal(runs.reduce((sum,run)=>sum+run.failed,0),0);
 assert.equal((await ref.get()).exists,false);
 assert.equal((await ref.collection('views').doc(viewer).get()).exists,false);
 assert.deepEqual(await file.exists(),[false]);
});

test('Respuesta en chat e inbox, reporte idempotente y eliminación por propietario',async()=>{
 const {id}=await stories.publish(owner,image,'image/png','Historia');
 const session=await fetch('http://127.0.0.1:'+ports.auth+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo',{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:viewer+'@ligo.test',password,returnSecureToken:true}),
 });
 assert.equal(session.status,200);
 const headers={Authorization:'Bearer '+(await session.json()).idToken};
 const reply=await fetch(origin+'/stories/reply?id='+id,{method:'POST',headers,body:'Respuesta ficticia'});
 assert.equal(reply.status,200);
 const {message}=await reply.json();
 const path='matches/'+match+'/messages/'+message;
 const row=(await services.db.doc(path).get()).data();
 assert.equal(row.text,'Respuesta ficticia');
 assert.equal(row.senderId,viewer);
 assert.equal(row.storyReply,true);
 const notifications=new Notifications(services);
 assert.equal((await notifications.inbox(owner).get()).size,1,'El endpoint guarda el aviso sin un receptor externo.');
 const [events]=await Promise.all([notifications.event(path),notifications.event(path)]);
 assert.equal(events[0].recipient,owner);
 const inbox=await notifications.inbox(owner).get();
 assert.equal(inbox.size,1);
 const notice=inbox.docs[0].data();
 assert.equal(notice.kind,'story_reply');
 assert.equal(notice.matchId,match);
 assert.equal(notice.sender,viewer);
 assert.deepEqual(Object.keys(notice).sort(),['createdAt','kind','matchId','readAt','sender']);
 assert.equal((await notifications.totals(owner).get()).get('messages'),1);
 await assert.rejects(notifications.mark(outsider,inbox.docs[0].id),e=>e.code==='not-found');
 await services.db.doc(path).update({readAt:Timestamp.now()});
 await notifications.event(path);
 assert.equal((await notifications.totals(owner).get()).get('messages'),0);
 assert.ok((await inbox.docs[0].ref.get()).get('readAt'));
 assert.equal((await notifications.inbox(owner).get()).size,1);
 await stories.report(viewer,id);
 await stories.report(viewer,id);
 const reports=await services.db.collection('reports').where('storyId','==',id).get();
 assert.equal(reports.size,1);
 assert.equal(reports.docs[0].get('reportedId'),owner);
 const backend=new VerificationBackend(services);
 const report=reports.docs[0].ref;
 await assert.rejects(backend.reviewReport(viewer,report.id,'reviewed'),denied);
 await backend.reviewReport(moderator,report.id,'reviewed');
 assert.equal((await report.get()).get('status'),'reviewed');
 assert.equal((await report.get()).get('reviewedBy'),moderator);
 await assert.rejects(backend.reviewReport(moderator,report.id,'dismissed'),e=>e.code==='conflict');
 const audit=await services.db.collection('administrativeAudit').where('actorId','==',moderator).get();
 assert.ok(audit.docs.some(d=>d.get('action')==='report_reviewed'));

 const file=services.bucket.file((await stories.ref(id).get()).get('path'));
 await assert.rejects(stories.remove(viewer,id),denied);
 await stories.remove(owner,id);
 assert.deepEqual(await file.exists(),[false]);
 assert.equal((await stories.ref(id).get()).exists,false);
 assert.equal((await services.db.doc(path).get()).exists,true);
});

test('MP4 H.264 real, reproducción preparada y rechazo de bytes falsos',async()=>{
 const ffmpeg=process.platform==='win32'?fileURLToPath(new URL('../ffmpeg/release/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe',import.meta.url)):'ffmpeg';
 const clip=execFileSync(ffmpeg,['-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=160x120:rate=15','-t','1','-c:v','libx264','-pix_fmt','yuv420p','-movflags','frag_keyframe+empty_moov','-f','mp4','pipe:1']);
 await assert.rejects(stories.publish(owner,image,'video/mp4','No es MP4'),invalid);
 const {id}=await stories.publish(owner,clip,'video/mp4','Clip ficticio');
 const media=await stories.media(viewer,id);
 assert.equal(media.mime,'video/mp4');
 assert.equal(media.bytes.subarray(4,8).toString(),'ftyp');
 assert.ok((await stories.ref(id).get()).get('durationMs')>0);
 await stories.remove(owner,id);
});


test('La limpieza conserva una generación ajena y reintenta después del bloqueo',async()=>{
 const {id}=await stories.publish(owner,image,'image/png','Reintento ficticio');
 const ref=stories.ref(id),data=(await ref.get()).data();
 const file=services.bucket.file(data.path);
 now=data.expiresAt.toMillis();
 await ref.update({generation:'0'});
 assert.equal((await stories.cleanup()).failed,1);
 assert.deepEqual(await file.exists(),[true]);
 assert.equal((await ref.get()).exists,true);
 assert.equal((await stories.cleanup()).skipped,1);
 await ref.update({generation:data.generation});
 now+=300001;
 assert.equal((await stories.cleanup()).deleted,1);
 assert.deepEqual(await file.exists(),[false]);
});
