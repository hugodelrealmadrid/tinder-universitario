import assert from 'node:assert/strict';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const services=await emulatorServices(),{auth,db,bucket}=services;
const status=await fetch('http://127.0.0.1:7357/__demo/status').then(r=>r.json());
const allowed=new Set(['http://127.0.0.1:7357','http://127.0.0.1:9099','http://127.0.0.1:8088','http://127.0.0.1:9198']);
const resources=status.events.filter(e=>e.kind==='resource'||e.kind==='local');
assert.ok(resources.length>0);assert.ok(resources.every(e=>allowed.has(e.origin)));
const ready=status.events.filter(e=>e.kind==='ready');assert.ok(ready.length>0);
for(const e of ready){const a=e.actual;assert.deepEqual(a.apps,['demo-tinder-universitario']);assert.equal(a.auth.host,'127.0.0.1');assert.equal(a.auth.port,9099);assert.equal(a.firestore.host,'127.0.0.1:8088');assert.equal(a.firestore.ssl,false);assert.equal(a.storage.host,'127.0.0.1:9198');}
assert.match(status.policy,/connect-src 'self' blob: http:\/\/127\.0\.0\.1:9099 http:\/\/127\.0\.0\.1:8088 http:\/\/127\.0\.0\.1:9198;/);
const accounts=[];
for(const [uid,email,role,verification,suspended]of [
 ['demo_pending','pendiente@demo.test','user','pending',false],
 ['manual_ana','ana.manual@demo.test','user','approved',false],
 ['manual_bob','bob.manual@demo.test','user','approved',false],
 ['demo_student','estudiante@demo.test','user','approved',false],
 ['demo_admin','admin@demo.test','admin','approved',false],
 ['demo_superadmin','superadmin@demo.test','superadmin','approved',false],
 ['demo_rejected','rechazado@demo.test','user','rejected',false],
 ['demo_suspended','suspendido@demo.test','user','pending',true],
]){
 const u=await auth.getUser(uid),a=(await db.doc('accountAccess/'+uid).get()).data();
 assert.equal(u.email,email);assert.equal(u.disabled,false);assert.equal(u.emailVerified,true);
 assert.equal(a.role,role);assert.equal(a.verificationStatus,verification);assert.equal(a.suspended,suspended);
 accounts.push({uid,role,verification,suspended});
}
const requests=await db.collection('verificationRequests').get();
const resolved=requests.docs.filter(d=>d.data().status!=='pending');
assert.ok(resolved.every(d=>!d.data().documentPath&&!d.data().generation));
const jobs=await db.collection('verificationCleanup').where('state','==','pending').get();assert.equal(jobs.size,0);
const [cards]=await bucket.getFiles({prefix:'university_cards/'});
for(const file of cards){const [m]=await file.getMetadata();assert.ok(!m.metadata?.firebaseStorageDownloadTokens);assert.equal(m.cacheControl,'private, no-store');}
console.log(JSON.stringify({project:services.app.options.projectId,accounts,networkResourcesChecked:resources.length,readyConfigurations:ready.length,externalResources:0,privateCards:cards.length,resolvedRequestsWithoutPrivatePaths:resolved.length,pendingCleanupJobs:jobs.size},null,2));
await deleteApp(services.app);
