import {ligoTestTarget} from './ligo/test-target.mjs';
import {test,before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,serverTimestamp,updateDoc} from 'firebase/firestore';
import {ref,getDownloadURL,getMetadata,uploadBytes,deleteObject} from 'firebase/storage';
import {Timestamp} from 'firebase-admin/firestore';
import {emulatorServices} from './backend/emulator.mjs';
import {VerificationBackend} from './backend/verification.mjs';
import {uploadChat,deleteChat,assetRef} from './backend/chat-upload.mjs';
import {readChat} from './backend/chat-read.mjs';
import {uploadPhoto,readPhoto,deletePhoto,photoAsset} from './backend/profile-media.mjs';
import {cleanupMedia} from './backend/media-cleanup.mjs';
import {validateMedia} from './backend/media-validation.mjs';
import {sealPrivateObject} from './backend/private-object.mjs';
import {imageFixture,audioFixture} from './test-media.mjs';
const stage=process.env.LIGO_STAGING_TESTS==='1';const ports=stage?ligoTestTarget().ports:{auth:9199,firestore:8188,storage:9298,hub:4410};const project=stage?ligoTestTarget().project:'demo-tinder-phase3-tests';let env,s,b,png,tokens={};
const ctx=uid=>env.authenticatedContext(uid,{email:uid+'@demo.test',email_verified:true});
const message=(id='m')=>({senderId:'ana',text:'',type:'image',mediaPath:'chat_media/ana.bob/ana/'+id,createdAt:serverTimestamp()});
before(async()=>{
 s=await emulatorServices(project,ports);b=new VerificationBackend(s);png=await imageFixture();
 env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:ports.firestore,rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')},storage:{host:'127.0.0.1',port:ports.storage,rules:await readFile(new URL('../storage.rules',import.meta.url),'utf8')}});
 for(const uid of ['ana','bob','third','pending','admin','root']){try{await s.auth.getUser(uid);await s.auth.updateUser(uid,{email:uid+'@demo.test',disabled:false,emailVerified:true,password:'DemoTinder2026!'});}catch{await s.auth.createUser({uid,email:uid+'@demo.test',emailVerified:true,password:'DemoTinder2026!'});}
 const response=await fetch('http://127.0.0.1:'+ports.auth+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:uid+'@demo.test',password:'DemoTinder2026!',returnSecureToken:true})});tokens[uid]=(await response.json()).idToken;assert.ok(tokens[uid]);}
});
after(async()=>env?.cleanup());
beforeEach(async()=>{
 await env.clearFirestore();await env.clearStorage();
 await s.db.doc('careers/sistemas').set({isActive:true,name:'Sistemas'});
 for(const uid of ['ana','bob','third','pending','admin','root']){
  await s.db.doc('accountAccess/'+uid).set({role:uid==='admin'?'admin':uid==='root'?'superadmin':'user',verificationStatus:uid==='pending'?'pending':'approved',suspended:false,latestRequestId:null});
  await s.db.doc('users/'+uid).set({firstName:uid,lastName:'Demo',birthDate:Timestamp.fromDate(new Date('2000-01-01')),email:uid+'@demo.test',gender:uid==='ana'?'femenino':'masculino',description:'Ficticio',careerId:'sistemas',photoUrls:[],mainPhotoUrl:null,interestIds:[],role:'user',datingAllowed:uid!=='pending',isActive:true,createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
  await s.db.doc('preferences/'+uid).set({minAge:18,maxAge:100,preferredGender:'ambos',careerIds:[],updatedAt:Timestamp.now()});
 }
 await s.db.doc('matches/ana.bob').set({users:['ana','bob'],isActive:true,createdAt:Timestamp.now()});await s.db.doc('administration/roles').set({superadminIds:['root']});
});
async function picture(uid='bob'){
 const path=`profile_photos/${uid}/pic`;await uploadPhoto(b,uid,path,png,'image/png');
 const user=(await s.db.doc('users/'+uid).get()).data();user.photoUrls=[path];user.mainPhotoUrl=path;await s.db.doc('users/'+uid).set(user);
 const {firstName,gender,description,careerId,interestIds,isActive,updatedAt}=user,age=new Date().getUTCFullYear()-2000;
 const card={firstName,age,gender,description,careerId,interestIds,isActive,updatedAt,mainPhotoUrl:path};
 await s.db.doc('discoveryCards/'+uid).set(card);await s.db.doc('matchProfiles/'+uid).set({...card,photoUrls:[path]});return path;
}
async function publish(id='m'){const path=message(id).mediaPath;await uploadChat(b,'ana',path,png,'image/png');await assertSucceeds(setDoc(doc(ctx('ana').firestore(),'matches/ana.bob/messages/'+id),message(id)));return path;}
test('Fotos: propietario y match autorizado; anónimo, pendiente y tercero sin perfil completo denegados',async()=>{
 const p=await picture();assert.deepEqual((await readPhoto(b,'bob',p,tokens.bob)).bytes,png);assert.deepEqual((await readPhoto(b,'ana',p,tokens.ana)).bytes,png);
 for(const uid of ['pending','third'])await assert.rejects(readPhoto(b,uid,p,tokens[uid]));await assert.rejects(readPhoto(b,'ana',p,tokens.bob));
});
test('Fotos: filtros de Descubrir y galería de match usan reglas existentes',async()=>{
 const p=await picture('bob');await picture('third');
 await assertSucceeds(getDoc(doc(ctx('third').firestore(),'discoveryCards/bob')));await readPhoto(b,'third',p,tokens.third);
 await s.db.doc('preferences/third').update({minAge:50});await assert.rejects(readPhoto(b,'third',p,tokens.third));
 await readPhoto(b,'ana',p,tokens.ana);
});
test('Fotos: suspensión de lector o propietario, retiro de aprobación, ocultación y bloqueo revocan bytes',async()=>{
 const p=await picture();
 await b.suspend('admin','ana',true,'safety');await assert.rejects(readPhoto(b,'ana',p,tokens.ana));await b.suspend('admin','ana',false,'safety');
 await b.suspend('admin','bob',true,'safety');await assert.rejects(readPhoto(b,'ana',p,tokens.ana));await b.suspend('admin','bob',false,'safety');
 await s.db.doc('accountAccess/ana').update({verificationStatus:'pending'});await assert.rejects(readPhoto(b,'ana',p,tokens.ana));await s.db.doc('accountAccess/ana').update({verificationStatus:'approved'});
 await s.db.doc('users/bob').update({isActive:false});await assert.rejects(readPhoto(b,'ana',p,tokens.ana));await s.db.doc('users/bob').update({isActive:true});
 await s.db.doc('blocks/bob.ana').set({blockerId:'bob',blockedId:'ana'});await assert.rejects(readPhoto(b,'ana',p,tokens.ana));
});
test('Fotos: SDK no permite tokens, subida directa, modificación ni borrado',async()=>{
 const p=await picture();for(const uid of ['bob','ana','root']){const file=ref(ctx(uid).storage(project+'.appspot.com'),p);await assertFails(getMetadata(file));await assertFails(getDownloadURL(file));await assertFails(deleteObject(file));await assertFails(uploadBytes(file,png,{contentType:'image/png'}));}
});
test('Fotos: token heredado funciona antes y deja de funcionar al revocarse sin alterar bytes',async()=>{
 const p=await picture(),file=s.bucket.file(p);await file.setMetadata({metadata:{firebaseStorageDownloadTokens:'old-phase5-token'}});
 const url=`http://127.0.0.1:${ports.storage}/v0/b/${project}.appspot.com/o/${encodeURIComponent(p)}?alt=media&token=old-phase5-token`;
 const before=await fetch(url);assert.equal(before.status,200);await before.body.cancel();await sealPrivateObject(file);const after=await fetch(url);assert.equal(after.status,403);assert.deepEqual((await file.download())[0],png);
});
test('Fotos: rutas ambiguas, URL externa, foto ajena e inexistente no se aceptan',async()=>{
 for(const p of ['https://example.test/photo','profile_photos/bob/../pic','profile_photos/bob/pic/extra','profile_photos/bob/%2fpic','profile_photos/bob/missing'])await assert.rejects(readPhoto(b,'ana',p,tokens.ana));
 await assert.rejects(uploadPhoto(b,'ana','profile_photos/bob/x',png,'image/png'));
});
test('Fotos: eliminar referenciada está prohibido; tras quitar referencia limpia manifiesto y objeto',async()=>{
 const p=await picture();await assert.rejects(deletePhoto(b,'bob',p));await s.db.doc('users/bob').update({photoUrls:[],mainPhotoUrl:null});await deletePhoto(b,'bob',p);assert.equal((await s.bucket.file(p).exists())[0],false);assert.deepEqual((await s.db.doc('profilePhotoManifests/bob').get()).data().paths,[]);
});
test('Cliente no puede falsificar manifiestos ni pruebas de subida',async()=>{
 for(const uid of ['ana','admin','root'])for(const path of ['profilePhotoManifests/ana','profilePhotoAssets/ana.pic','chatUploads/ana.bob.m'])await assertFails(setDoc(doc(ctx(uid).firestore(),path),{state:'ready',paths:['profile_photos/ana/pic'],uid:'ana'}));
 await assertFails(updateDoc(doc(ctx('ana').firestore(),'users/ana'),{photoUrls:['profile_photos/ana/missing'],mainPhotoUrl:'profile_photos/ana/missing',updatedAt:serverTimestamp()}));
});
test('Chat: prueba de archivo obligatorio; remitente, ruta y tipo vinculados e inmutables',async()=>{
 const r=doc(ctx('ana').firestore(),'matches/ana.bob/messages/m');await assertFails(setDoc(r,message()));await uploadChat(b,'ana',message().mediaPath,png,'image/png');
 for(const changes of [{type:'audio'},{mediaPath:'chat_media/ana.bob/bob/m'},{mediaPath:'chat_media/ana.bob/ana/other'},{senderId:'bob'}])await assertFails(setDoc(r,{...message(),...changes}));
 await assertSucceeds(setDoc(r,message()));await assertFails(updateDoc(r,{type:'audio'}));await assertSucceeds(updateDoc(doc(ctx('bob').firestore(),'matches/ana.bob/messages/m'),{readAt:serverTimestamp()}));
});
test('Chat: participantes reciben bytes idénticos, tercero/pendiente y pareja ajena denegados',async()=>{
 const p=await publish();assert.deepEqual((await readChat(b,'bob',p,true)).bytes,png);for(const uid of ['third','pending'])await assert.rejects(readChat(b,uid,p,true));await assert.rejects(readChat(b,'bob',p.replace('ana.bob','ana.third'),true));await assert.rejects(deleteChat(b,'ana',p));
});
test('Chat: nota WAV publicada conserva MIME, duración y bytes privados', async () => {
 const note = await audioFixture('audio/wav');
 const payload = {...message('voice'), type: 'audio', durationMs: 1000};
 await uploadChat(b, 'ana', payload.mediaPath, note, 'audio/wav');
 await assertSucceeds(setDoc(doc(ctx('ana').firestore(), 'matches/ana.bob/messages/voice'), payload));
 const metadata = await readChat(b, 'bob', payload.mediaPath);
 assert.equal(metadata.durationMs, 1000);
 assert.equal(metadata.contentType, 'audio/wav');
 const received = await readChat(b, 'bob', payload.mediaPath, true);
 assert.equal(received.contentType, 'audio/wav');
 assert.deepEqual(received.bytes, note);
 await assert.rejects(readChat(b, 'third', payload.mediaPath, true));
});
test('Chat: suspensión de cualquiera de los participantes revoca acceso y publicación pendiente',async()=>{
 const p=await publish();await uploadChat(b,'ana',message('later').mediaPath,png,'image/png');await b.suspend('admin','bob',true,'safety');
 for(const uid of ['ana','bob'])await assert.rejects(readChat(b,uid,p,true));await assertFails(setDoc(doc(ctx('ana').firestore(),'matches/ana.bob/messages/later'),message('later')));
});
test('Chat: cierre y bloqueo incluso inconsistente revocan lectura multimedia',async()=>{
 const p=await publish();await s.db.doc('matches/ana.bob').update({isActive:false});await assert.rejects(readChat(b,'ana',p,true));await s.db.doc('matches/ana.bob').update({isActive:true});await s.db.doc('blocks/ana.bob').set({});await assert.rejects(readChat(b,'bob',p,true));
});
test('Chat: objeto sustituido o metadatos manipulados no se entregan',async()=>{
 const p=await publish();await s.bucket.file(p).setMetadata({contentType:'audio/wav'});await assert.rejects(readChat(b,'bob',p,true));
});
for(const mime of ['image/png','image/jpeg','image/webp','audio/wav','audio/mpeg','audio/mp4','audio/ogg'])test('Decodificación real compatible: '+mime,async()=>{
 const bytes=mime.startsWith('image/')?await imageFixture(mime):await audioFixture(mime),v=await validateMedia(bytes,mime);assert.equal(v.type,mime.startsWith('image/')?'image':'audio');if(v.type==='audio')assert.ok(v.durationMs>500&&v.durationMs<1500);
});
test('MIME falso, cabecera truncada, HTML, playlist y exceso de tamaño se rechazan en servidor',async()=>{
 for(const [bytes,mime]of [[Buffer.from('<html/>'),'image/png'],[png,'image/jpeg'],[Buffer.from('RIFF0000WAVE'),'audio/wav'],[Buffer.from('#EXTM3U\nhttp://example.invalid/leak'),'audio/mpeg'],[Buffer.alloc(15*1024*1024+1),'audio/mpeg']])await assert.rejects(validateMedia(bytes,mime));
});
test('Limpieza durable: huérfanos chat/foto vencen; archivos publicados sobreviven y no pueden resucitarse',async()=>{
 const p=message('orphan').mediaPath;await uploadChat(b,'ana',p,png,'image/png');await uploadPhoto(b,'ana','profile_photos/ana/orphan',png,'image/png');const published=await publish('saved');
 for(const ref of [assetRef(b,p),photoAsset(b,'profile_photos/ana/orphan'),assetRef(b,published)])await ref.update({expiresAt:Timestamp.fromMillis(Date.now()-1)});
 await cleanupMedia(b);assert.equal((await s.bucket.file(p).exists())[0],false);assert.equal((await s.bucket.file('profile_photos/ana/orphan').exists())[0],false);assert.equal((await s.bucket.file(published).exists())[0],true);
 await assertFails(setDoc(doc(ctx('ana').firestore(),'matches/ana.bob/messages/orphan'),message('orphan')));
});
test('Limpieza reintenta fallo de Storage sin habilitar publicación ni perder tarea',async()=>{
 const p=message('retry').mediaPath;await uploadChat(b,'ana',p,png,'image/png');await assetRef(b,p).update({expiresAt:Timestamp.fromMillis(Date.now()-1)});
 const fake={...b,db:b.db,bucket:{file:()=>({delete:async()=>{throw Error('offline');}})}};await cleanupMedia(fake);
 assert.equal((await assetRef(b,p).get()).data().state,'deleting');await assetRef(b,p).update({expiresAt:Timestamp.fromMillis(Date.now()-1),leaseUntil:null});await cleanupMedia(b);assert.equal((await assetRef(b,p).get()).data().state,'deleted');
});

test('Reconciliación elimina fotos publicadas que pierden su referencia después del staging',async()=>{
 const p=await picture('bob');await photoAsset(b,p).update({state:'published'});
 await s.db.doc('users/bob').update({photoUrls:[],mainPhotoUrl:null});
 await cleanupMedia(b,Date.now()+1000);
 assert.equal((await s.bucket.file(p).exists())[0],false);
 assert.deepEqual((await s.db.doc('profilePhotoManifests/bob').get()).data().paths,[]);
 await assert.rejects(readPhoto(b,'bob',p,tokens.bob));
});
