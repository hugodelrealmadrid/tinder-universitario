// Read-only verification. Never seeds, publishes, deletes or changes privileges.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const source=resolve(process.argv[2]??'build/respaldo-integracion-20261019-222416/demo-actual');
const expected=JSON.parse((await readFile(resolve(source,'auth_export/accounts.json'),'utf8')).replace(/^\uFEFF/,''));
const s=await emulatorServices();
const risks=[];let photoCount=0,chatCount=0,requestCount=0;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
try{
 const auth=await s.auth.listUsers(1000);assert.equal(auth.users.length,10);assert.equal(expected.users.length,10);
 const ids=new Set(auth.users.map(u=>u.uid));
 for(const old of expected.users){const u=auth.users.find(u=>u.uid===old.localId);assert.ok(u,'Missing Auth UID');assert.equal(u.email,old.email);assert.equal(u.emailVerified,!!old.emailVerified);assert.equal(u.disabled,!!old.disabled);assert.ok(u.email.endsWith('@demo.test'));}
 const [users,access]=await Promise.all([s.db.collection('users').get(),s.db.collection('accountAccess').get()]);
 for(const d of users.docs)assert.ok(ids.has(d.id),'Profile without Auth account');
 for(const d of access.docs){assert.ok(ids.has(d.id),'Access without Auth account');const a=d.data();assert.ok(['user','admin','superadmin'].includes(a.role));assert.ok(['pending','approved','rejected'].includes(a.verificationStatus));const profile=users.docs.find(u=>u.id===d.id)?.data();if(profile)assert.equal(profile.datingAllowed,a.verificationStatus==='approved'&&a.suspended===false,'Authorization mirror mismatch');}
 const [objects]=await s.bucket.getFiles();assert.equal(objects.length,14);
 const paths=new Set(objects.map(f=>f.name));
 for(const file of objects){
  const [m]=await file.getMetadata();assert.equal(m.bucket,'demo-tinder-universitario.appspot.com');assert.ok(!m.metadata?.firebaseStorageDownloadTokens);
  const [bytes]=await file.download();const p=file.name.split('/');let asset,referenced;
  if(p[0]==='profile_photos'){
   photoCount++;const profile=(await s.db.doc('users/'+p[1]).get()).data(),manifest=(await s.db.doc('profilePhotoManifests/'+p[1]).get()).data();
   asset=(await s.db.doc('profilePhotoAssets/'+p[1]+'.'+p[2]).get()).data();referenced=profile?.photoUrls?.includes(file.name);
   assert.ok(manifest?.paths?.includes(file.name));
  }else if(p[0]==='chat_media'){
   chatCount++;const pair=(await s.db.doc('matches/'+p[1]).get()).data(),message=(await s.db.doc('matches/'+p[1]+'/messages/'+p[3]).get()).data();
   asset=(await s.db.doc('chatUploads/'+p[1]+'.'+p[3]).get()).data();referenced=message?.mediaPath===file.name;
   assert.ok(pair?.users?.includes(p[2]));if(message){assert.equal(message.senderId,p[2]);assert.equal(message.type,asset?.type);}
  }else throw Error('Unexpected storage namespace');
  assert.ok(asset);assert.equal(asset.path,file.name);assert.equal(asset.generation,m.generation);assert.equal(asset.size,bytes.length);assert.equal(asset.mime,m.contentType);assert.equal(asset.sha256,sha(bytes));
  assert.ok(['ready','published'].includes(asset.state));
  if(!referenced)risks.push({path:file.name,reason:'unreferenced',state:asset.state});
 }
 for(const d of users.docs){const u=d.data();for(const p of u.photoUrls??[])assert.ok(paths.has(p),'Photo reference without file');if(u.mainPhotoUrl)assert.ok(u.photoUrls.includes(u.mainPhotoUrl));}
 for(const pair of (await s.db.collection('matches').get()).docs){for(const uid of pair.data().users??[])assert.ok(ids.has(uid));for(const msg of (await pair.ref.collection('messages').get()).docs){const m=msg.data();if(m.mediaPath)assert.ok(paths.has(m.mediaPath),'Message without file');}}
 const requests=await s.db.collection('verificationRequests').get();
 for(const d of requests.docs){requestCount++;const r=d.data();assert.ok(ids.has(r.uid));if(r.documentStage==='ready'&&r.documentPath&&!paths.has(r.documentPath))risks.push({request:d.id,reason:'card-marked-ready-without-file',status:r.status});if(r.status==='pending'&&r.expiresAt?.toMillis()<=Date.now())risks.push({request:d.id,reason:'pending-verification-expired'});}
 const pendingCleanup=(await s.db.collection('verificationCleanup').where('state','==','pending').get()).size;
 console.log(JSON.stringify({project:s.db.projectId,authAccounts:auth.users.length,profiles:users.size,accessRecords:access.size,storageObjects:objects.length,profilePhotos:photoCount,chatMedia:chatCount,verificationRequests:requestCount,pendingCleanup,hashesAndReferencesValid:true,risks},null,2));
 if(risks.length)process.exitCode=2;
}finally{await deleteApp(s.app);}
