import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {hostedConfig} from './hosted-config.mjs';
import {hostedServices} from './hosted-services.mjs';
import {requestHandler} from './http-handler.mjs';
const valid={APP_ENV:'production',GOOGLE_CLOUD_PROJECT:'tinder-test-hosted',TINDER_PROJECT_ID:'tinder-test-hosted',TINDER_STORAGE_BUCKET:'tinder-test-hosted.firebasestorage.app',TINDER_WEB_ORIGINS:'https://tinder-test-hosted.web.app'};
test('Configuración remota explícita; sin credenciales ni llamadas de red',()=>{
 assert.equal(hostedConfig(valid).port,8080);
 assert.equal(hostedConfig({...valid,APP_ENV:'development',PORT:'9000'}).port,9000);
 for(const changes of [{APP_ENV:'demo'},{TINDER_PROJECT_ID:'demo-tinder-test'},{TINDER_PROJECT_ID:'otro-proyecto'},{TINDER_WEB_ORIGINS:'*'},{TINDER_WEB_ORIGINS:'http://localhost:7357'},{TINDER_WEB_ORIGINS:'https://app.example'},{TINDER_WEB_ORIGINS:'https://user:pass@host.test'},{TINDER_WEB_ORIGINS:'https://app.test/path'},{PORT:'0'},{FIRESTORE_EMULATOR_HOST:'127.0.0.1:8088'},{FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9099'},{FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:9198'},{GOOGLE_APPLICATION_CREDENTIALS:'key.json'},{FIREBASE_CONFIG:'{}'}])assert.throws(()=>hostedConfig({...valid,...changes}));
 assert.throws(()=>hostedServices(valid),/cloud-run-required/);
});
test('CORS restringido, preflight sin acceso a datos y token revocado comprobado',async()=>{
 let checks=0;
 const server=createServer(requestHandler({auth:{async verifyIdToken(token,revoked){checks++;assert.equal(revoked,true);throw Error('invalid');}}},{origins:valid.TINDER_WEB_ORIGINS.split(',')}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url=`http://127.0.0.1:${server.address().port}`;
 try{
  const preflight=await fetch(url,{method:'OPTIONS',headers:{Origin:valid.TINDER_WEB_ORIGINS,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'Authorization, Content-Type, X-Chat-Path'}});
  assert.equal(preflight.status,204);assert.equal(preflight.headers.get('access-control-allow-origin'),valid.TINDER_WEB_ORIGINS);assert.equal(checks,0);
  assert.equal((await fetch(url,{method:'OPTIONS',headers:{Origin:valid.TINDER_WEB_ORIGINS,'Access-Control-Request-Method':'DELETE'}})).status,403);
  const foreign=await fetch(url,{headers:{Origin:'https://attacker.test',Authorization:'Bearer fake'}});assert.equal(foreign.status,403);assert.equal(foreign.headers.get('access-control-allow-origin'),null);assert.equal(checks,0);
  assert.equal((await fetch(url)).status,401);
  assert.equal((await fetch(url,{headers:{Authorization:'Bearer fake'}})).status,401);assert.equal(checks,1);
 }finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});

// No solicita tokens ni accede a Google: fetch se sustituye por respuestas locales.
test('Fotos alojadas delegan visibilidad a reglas con token del lector',async t=>{
 const {permittedCard}=await import('./profile-media.mjs');
 const path='profile_photos/owner/photo',calls=[];
 const b={db:{projectId:valid.TINDER_PROJECT_ID},firestoreOrigin:'https://firestore.googleapis.com',auth:{verifyIdToken:async()=>({uid:'reader'})}};
 t.mock.method(globalThis,'fetch',async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({fields:{mainPhotoUrl:{stringValue:path}}}),{status:200});});
 await permittedCard(b,'reader-token','reader',path);
 assert.equal(calls.length,1);
 assert.equal(calls[0].url,'https://firestore.googleapis.com/v1/projects/tinder-test-hosted/databases/(default)/documents/discoveryCards/owner');
 assert.equal(calls[0].options.headers.Authorization,'Bearer reader-token');
 await assert.rejects(()=>permittedCard(b,'reader-token','attacker',path));
 await assert.rejects(()=>permittedCard({...b,firestoreOrigin:'https://attacker.test'},'reader-token','reader',path));
 t.mock.restoreAll();
 t.mock.method(globalThis,'fetch',async()=>new Response('{}',{status:403}));
 await assert.rejects(()=>permittedCard(b,'reader-token','reader',path));
});
test('El Job recupera y actualiza cursores desde Firestore entre ejecuciones',async()=>{
 const {cleanupMedia}=await import('./media-cleanup.mjs');
 const state=new Map([['maintenanceCursors/profilePhotoAssets',{after:'previous-page'}]]),seen=[];
 const db={doc(path){return {async get(){return {data:()=>state.get(path)};},async set(value){state.set(path,value);}};},collection(name){
  const q={where(){return q;},orderBy(){return q;},startAfter(cursor){seen.push([name,cursor]);return q;},limit(){return q;},async get(){return {docs:[],size:0};}};return q;
 }};
 await cleanupMedia({db});
 assert.deepEqual(seen,[['profilePhotoAssets','previous-page']]);
 assert.equal(state.get('maintenanceCursors/profilePhotoAssets').after,null);
 await cleanupMedia({db});assert.equal(seen.length,1);
});

 test('Antes del corte: incluso un token válido no puede leer ni provisionar datos',async()=>{
 const services={auth:{async verifyIdToken(token,revoked){assert.equal(revoked,true);if(token!=='valid')throw Error('invalid');return {uid:'synthetic'};}}};
 const server=createServer(requestHandler(services,{operationsEnabled:false}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url=`http://127.0.0.1:${server.address().port}`;
 try{assert.equal((await fetch(url+'/administration/audit')).status,401);assert.equal((await fetch(url,{headers:{Authorization:'Bearer invalid'}})).status,401);for(const path of ['/account/provision','/verification/decide','/administration/role','/chat/upload','/profile/upload'])assert.equal((await fetch(url+path,{method:'POST',headers:{Authorization:'Bearer valid'}})).status,503);assert.equal((await fetch(url+'/verification/own',{headers:{Authorization:'Bearer valid'}})).status,503);}finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});

test('Autorización administrativa exige rol aprobado y cuenta no suspendida',async()=>{
 const {VerificationBackend}=await import('./verification.mjs');let account;const b=new VerificationBackend({db:{doc:path=>({path})}});const tx={get:async()=>({data:()=>account})};
 for(const a of [undefined,{role:'user',verificationStatus:'approved',suspended:false},{role:'admin',verificationStatus:'pending',suspended:false},{role:'superadmin',verificationStatus:'approved',suspended:true}]){account=a;await assert.rejects(()=>b.actor(tx,'synthetic',true));}
 for(const role of ['admin','superadmin']){account={role,verificationStatus:'approved',suspended:false};assert.equal((await b.actor(tx,'synthetic',true)).role,role);}
});
