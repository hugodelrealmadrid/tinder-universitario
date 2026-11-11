import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const s=await emulatorServices();
try {
 let photos=0,chat=0,revoked=0;
 for(const doc of (await s.db.collection('users').get()).docs){
  const u=doc.data(),m=(await s.db.doc('profilePhotoManifests/'+doc.id).get()).data();
  for(const p of u.photoUrls??[]){assert.ok(p.startsWith('profile_photos/'+doc.id+'/'));assert.ok(m.paths.includes(p));photos++;}
  if(u.mainPhotoUrl)assert.ok(u.photoUrls.includes(u.mainPhotoUrl));
 }
 for(const [file] of (await s.bucket.getFiles())[0].map(f=>[f])) {
  if(!/^(profile_photos|chat_media)\//.test(file.name))continue;
  const [meta]=await file.getMetadata();assert.ok(!meta.metadata?.firebaseStorageDownloadTokens);
  const parts=file.name.split('/'),collection=parts[0]==='profile_photos'?'profilePhotoAssets':'chatUploads';
  const id=parts[0]==='profile_photos'?parts[1]+'.'+parts[2]:parts[1]+'.'+parts[3];
  const a=(await s.db.doc(collection+'/'+id).get()).data();assert.ok(['ready','published'].includes(a.state));
  assert.equal(a.generation,meta.generation);
  const [bytes]=await file.download();assert.equal(a.sha256,createHash('sha256').update(bytes).digest('hex'));
  if(parts[0]==='chat_media')chat++;
 }
 const folder=new URL('../../build/phase4-fixtures-final/storage_export/metadata/',import.meta.url);
 for(const name of await readdir(folder)) {
  const m=JSON.parse(await readFile(new URL(name,folder),'utf8'));
  if(m.bucket!=='demo-tinder-universitario.appspot.com'||!/^(profile_photos|chat_media)\//.test(m.name))continue;
  for(const token of m.downloadTokens??[]) {
   const r=await fetch('http://127.0.0.1:9198/v0/b/'+m.bucket+'/o/'+encodeURIComponent(m.name)+'?alt=media&token='+encodeURIComponent(token));
   assert.notEqual(r.status,200);await r.body?.cancel();revoked++;
  }
 }
 console.log(JSON.stringify({project:'demo-tinder-universitario',profileReferences:photos,chatFiles:chat,oldTokensDenied:revoked,integrity:true}));
}finally{await deleteApp(s.app);}
