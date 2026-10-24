// HTTP reads and sign-ins only; no uploads, seeds or administrative decisions.
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const source=resolve(process.argv[2]??'build/respaldo-integracion-20261019-222416/demo-actual');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
const s=await emulatorServices(),sessions=new Map(),hash=b=>createHash('sha256').update(b).digest('hex');
let authenticated=0,authorized=0,denied=0,resolvedCardsDenied=0;
const base='http://127.0.0.1:7357/__demo/api/';
async function get(path,uid){return fetch(base+path,{headers:uid?{Authorization:'Bearer '+sessions.get(uid)}:{},signal:AbortSignal.timeout(30000)});}
async function rejects(path,uid,status){const r=await get(path,uid);assert.equal(r.status,status);await r.body?.cancel();denied++;}
try{
 const old=await json(resolve(source,'auth_export/accounts.json'));
 for(const u of old.users){
  const response=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-local-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:u.email,password:'DemoTinder2026!',returnSecureToken:true}),signal:AbortSignal.timeout(15000)});
  assert.equal(response.status,200,'Demo sign-in failed; credentials were not changed');const session=await response.json();assert.equal(session.localId,u.localId);sessions.set(session.localId,session.idToken);authenticated++;
 }
 for(const name of await readdir(resolve(source,'storage_export/metadata'))){
  const m=await json(resolve(source,'storage_export/metadata',name)),parts=m.name.split('/');
  const expected=await readFile(resolve(source,'storage_export/blobs',name.replace(/\.json$/,'')));
  const path=(parts[0]==='profile_photos'?'profile/media/':'chat/media/')+encodeURIComponent(m.name);
  const members=parts[0]==='profile_photos'?[parts[1]]:(await s.db.doc('matches/'+parts[1]).get()).data().users;
  for(const uid of members){const r=await get(path,uid);assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(r.headers.get('content-type'),m.contentType);assert.equal(hash(Buffer.from(await r.arrayBuffer())),hash(expected));authorized++;}
  await rejects(path,null,401);await rejects(path,'demo_suspended',403);await rejects(path,'demo_rejected',403);
  if(parts[0]==='chat_media')await rejects(path,'manual_carla',403);
  const sdk=await fetch('http://127.0.0.1:9198/v0/b/'+m.bucket+'/o/'+encodeURIComponent(m.name)+'?alt=media',{signal:AbortSignal.timeout(15000)});assert.notEqual(sdk.status,200);await sdk.body?.cancel();denied++;
 }
 for(const d of (await s.db.collection('verificationRequests').get()).docs){
  const r=d.data();assert.notEqual(r.status,'pending','Unexpected pending card: review before testing');
  const path='verification/document/'+d.id;
  await rejects(path,'demo_admin',403);await rejects(path,null,401);resolvedCardsDenied++;
 }
 for(const uid of ['manual_ana','demo_suspended','demo_rejected'])await rejects('verification/requests',uid,403);
 const admin=await get('verification/requests','demo_admin');assert.equal(admin.status,200);await admin.body?.cancel();
 const root=await get('administration/audit','demo_superadmin');assert.equal(root.status,200);await root.body?.cancel();
 await rejects('administration/audit','demo_admin',403);
 console.log(JSON.stringify({authenticatedAccounts:authenticated,authorizedMediaDownloads:authorized,unauthorizedRequestsDenied:denied,resolvedCardsDenied,cardsInRestoredStorage:0,positiveCardAccess:'Covered using fictitious documents in secondary tests, without adding cards to restored demo'},null,2));
}finally{await deleteApp(s.app);}
