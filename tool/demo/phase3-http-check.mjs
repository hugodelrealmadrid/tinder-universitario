// End-to-end con tokens reales del emulador. Conserva los datos anteriores.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,getDoc,setDoc,serverTimestamp} from 'firebase/firestore';
const project='demo-tinder-universitario',base='http://127.0.0.1:7357/__demo/api/';
const env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});
const tokens={};
async function login(name,email){const r=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-tinder-universitario-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password:'DemoTinder2026!',returnSecureToken:true})});assert.equal(r.status,200);tokens[name]=(await r.json()).idToken;}
async function api(name,path,data,extra={}){return fetch(base+path,{method:data===undefined?'GET':'POST',headers:{...(name?{Authorization:'Bearer '+tokens[name]}:{}),'Content-Type':'application/json',...extra},...(data===undefined?{}:{body:Buffer.isBuffer(data)?data:JSON.stringify(data)})});}
let suspended=false;
try{
 await login('ana','ana.manual@demo.test');await login('bob','bob.manual@demo.test');await login('pending','pendiente@demo.test');await login('root','superadmin@demo.test');
 assert.equal((await api(null,'verification/requests')).status,401);
 assert.equal((await api('ana','administration/role',{uid:'manual_ana',role:'superadmin'})).status,403);
 assert.equal((await api('pending','account/provision',{role:'superadmin'})).status,400);
 assert.equal((await api('pending','account/provision',{})).status,200);
 assert.equal((await api('pending','verification/begin',{})).status,200);
 assert.equal((await api('pending','verification/requests')).status,403);
 assert.equal((await api('root','verification/requests')).status,200);
 const path='chat_media/manual_ana.manual_bob/manual_ana/phase3-'+randomUUID(),messageId=path.split('/').at(-1);
 const bytes=await readFile(new URL('../../build/demo-manual_carla.png',import.meta.url));
 assert.equal((await api('ana','chat/upload',bytes,{'Content-Type':'image/png','X-Chat-Path':path})).status,200);
 const metaPath='chat/metadata/'+encodeURIComponent(path),dataPath='chat/media/'+encodeURIComponent(path);
 assert.equal((await api('ana',metaPath)).status,200);assert.equal((await api('bob',metaPath)).status,403);
 try{
  const r=await api('root','administration/suspend',{uid:'manual_ana',suspended:true,reasonCode:'safety'});assert.equal(r.status,200);suspended=true;
  assert.equal((await api('ana',metaPath)).status,403);
  const ctx=env.authenticatedContext('manual_ana',{email:'ana.manual@demo.test',email_verified:true});
  await assert.rejects(getDoc(doc(ctx.firestore(),'matches/manual_ana.manual_bob')));
 }finally{
  if(suspended){assert.equal((await api('root','administration/suspend',{uid:'manual_ana',suspended:false,reasonCode:'safety'})).status,200);suspended=false;}
 }
 const ctx=env.authenticatedContext('manual_ana',{email:'ana.manual@demo.test',email_verified:true});
 await setDoc(doc(ctx.firestore(),'matches/manual_ana.manual_bob/messages/'+messageId),{senderId:'manual_ana',text:'',type:'image',mediaPath:path,createdAt:serverTimestamp()});
 assert.equal((await api('bob',metaPath)).status,200);
 const received=await api('bob',dataPath);assert.equal(received.status,200);assert.deepEqual(Buffer.from(await received.arrayBuffer()),bytes);
 assert.equal((await api('pending',dataPath)).status,403);
 const profile=(await getDoc(doc(ctx.firestore(),'users/manual_ana'))).data();assert.equal(profile.isActive,true);assert.equal(profile.datingAllowed,true);
 console.log('HTTP demo: 4 sesiones Auth locales; sin sesión y escalada denegadas; solicitud pendiente; subida/lectura privada de chat; suspensión y restauración sin alterar isActive; contenido receptor idéntico.');
}finally{
 if(suspended)await api('root','administration/suspend',{uid:'manual_ana',suspended:false,reasonCode:'safety'});
 await env.cleanup();
}
