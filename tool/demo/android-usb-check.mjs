// Comprobación de solo lectura: conserva los estados actuales del demo.
import assert from 'node:assert/strict';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const s=await emulatorServices();
try {
 const response=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-local-key',{
  method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({email:'ana.manual@demo.test',password:'DemoTinder2026!',returnSecureToken:true}),
 });
 assert.equal(response.status,200);
 const session=await response.json();assert.equal(session.localId,'manual_ana');
 const u=(await s.db.doc('users/manual_ana').get()).data();
 const accounts=[];
 for(const uid of ['manual_ana','manual_bob']) {
  const a=(await s.db.doc('accountAccess/'+uid).get()).data();
  assert.equal(a.verificationStatus,'approved');assert.equal(a.suspended,false);
  accounts.push({uid,role:a.role,verificationStatus:a.verificationStatus,suspended:a.suspended});
 }
 const path='profile/media/'+encodeURIComponent(u.mainPhotoUrl);
 for(const base of ['http://127.0.0.1:7360/','http://127.0.0.1:7357/__demo/api/']) {
  const r=await fetch(base+path,{headers:{Authorization:'Bearer '+session.idToken}});
  assert.equal(r.status,200);assert.match(r.headers.get('content-type'),/^image\//);
  assert.equal(r.headers.get('cache-control'),'no-store');assert.ok((await r.arrayBuffer()).byteLength>0);
  const denied=await fetch(base+path);assert.equal(denied.status,401);await denied.body?.cancel();
 }
 console.log(JSON.stringify({project:'demo-tinder-universitario',auth:true,firestore:true,storage:true,privateBackend:true,proxy:true,anonymousDenied:true,accounts},null,2));
}finally{await deleteApp(s.app);}
