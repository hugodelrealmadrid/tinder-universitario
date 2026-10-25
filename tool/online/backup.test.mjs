import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {captureFirestore,crc32c} from './backup.mjs';
import {canonical,sha,privateDirectory,saveEncrypted,loadEncrypted} from './private-backup.mjs';
test('CRC32C contra vector conocido y serialización canónica',()=>{
 assert.equal(crc32c(Buffer.from('123456789')),'4waSgw==');assert.equal(canonical({b:2,a:1}),canonical({a:1,b:2}));
});
test('Snapshot recursivo incluye subcolecciones bajo padres ausentes',async()=>{
 const root='https://firestore.googleapis.com/v1/projects/tinder-universitario/databases/(default)/documents',time='2026-01-01T00:00:00.000000Z';
 const doc=name=>({name:name.replace('https://firestore.googleapis.com/v1/',''),createTime:time,updateTime:time,fields:{synthetic:{booleanValue:true}}});
 const read=async(url,body)=>{
  if(url.endsWith(':runQuery'))return [{readTime:time}];
  if(body){assert.equal(body.readTime,time);return {collectionIds:url===root+':listCollectionIds'?['users']:url===root+'/users/absent:listCollectionIds'?['history']:[]};}
  const u=new URL(url);assert.equal(u.searchParams.get('readTime'),time);assert.equal(u.searchParams.get('showMissing'),'true');
  if(u.pathname.endsWith('/users'))return {documents:[{name:root.replace('https://firestore.googleapis.com/v1/','')+'/users/absent'},doc(root+'/users/synthetic')]};
  if(u.pathname.endsWith('/history'))return {documents:[doc(root+'/users/absent/history/synthetic')]};
  throw Error('unexpected-path');
 };
 const snapshot=await captureFirestore(read);assert.equal(snapshot.documents.length,2);assert.equal(snapshot.missing.length,1);assert.equal(snapshot.readTime,time);
});
test('DPAPI: lectura recupera contenido y alteración es rechazada',{skip:process.platform!=='win32'},()=>{
 const dir=mkdtempSync(fileURLToPath(new URL('../../build/backup-unit-',import.meta.url)));privateDirectory(dir);
 const file=join(dir,'synthetic.dpapi'),value={synthetic:true,secret:'SYNTHETIC-NOT-A-CREDENTIAL'};
 const check=saveEncrypted(file,value);assert.equal(sha(readFileSync(file)),check.cipherSha256);assert.deepEqual(loadEncrypted(file),value);assert.equal(readFileSync(file).includes(Buffer.from(value.secret)),false);
 const bad=readFileSync(file);bad[bad.length-8]^=1;writeFileSync(join(dir,'tampered.dpapi'),bad);assert.throws(()=>loadEncrypted(join(dir,'tampered.dpapi')));
});
