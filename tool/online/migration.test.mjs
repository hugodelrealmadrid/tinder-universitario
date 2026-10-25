import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {buildPlan,firestoreWrites,bootstrapWrites,encode,value,PROJECT} from './migration-plan.mjs';
import {assertExecution,migrate,revoke} from './operator.mjs';
import {sha,canonical} from './private-backup.mjs';
const prefix=`projects/${PROJECT}/databases/(default)/documents/`,time='2026-01-01T00:00:00.000Z';
const raw=(path,values)=>({name:prefix+path,fields:encode(values).mapValue.fields,createTime:time,updateTime:time});
function fixture(){
 const uid='synthetic_student',bucket='tinder-universitario.firebasestorage.app',path='profile_photos/'+uid+'/old.jpg',bytes=Buffer.from('synthetic-unit-bytes');
 const url=`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media&token=SYNTHETIC_TOKEN`;
 return {project:PROJECT,format:'tinder-private-backup-v1',completedAt:time,auth:{users:[{localId:uid,disabled:false}]},storage:{buckets:[{name:bucket}],files:[{metadata:{bucket,name:path,generation:'1',metageneration:'1',size:String(bytes.length),contentType:'image/jpeg',metadata:{firebaseStorageDownloadTokens:'SYNTHETIC_TOKEN'}},bytesBase64:bytes.toString('base64'),sha256:sha(bytes)}]},firestore:{documents:[raw('users/'+uid,{firstName:'Ficticio',birthDate:new Date('2000-01-01T00:00:00Z'),photoUrls:[url],mainPhotoUrl:url,isActive:true,role:'user',gender:'hombre',description:'Ficticio',interestIds:['musica'],careerId:'sistemas',updatedAt:new Date(time)}),raw('matches/synthetic_pair',{isActive:true}),raw('matches/synthetic_pair/messages/legacy',{senderId:uid,text:'Mensaje ficticio',createdAt:new Date(time)}),raw('preferences/'+uid,{minAge:18,maxAge:30})]}};
}
test('Plan conserva datos y crea exclusivamente usuarios pendientes, sin grants',()=>{
 const b=fixture(),before=canonical(b),p=buildPlan(b);assert.equal(canonical(b),before);assert.deepEqual(p.preserved,{auth:1,matches:1,messages:1,preferences:1});
 const writes=firestoreWrites(p,{[p.photos[0].target]:'2'});
 const access=writes.find(w=>w.update.name.includes('/accountAccess/'));assert.equal(value(access.update.fields.role),'user');assert.equal(value(access.update.fields.verificationStatus),'pending');assert.equal(value(access.update.fields.suspended),false);
 const profile=writes.find(w=>w.update.name.includes('/users/'));assert.equal(value(profile.update.fields.datingAllowed),false);assert.equal(profile.currentDocument.updateTime,time);assert.ok(profile.updateMask.fieldPaths.includes('photoUrls'));
 assert.equal(writes.some(w=>/\/(matches|preferences)\//.test(w.update.name)),false);assert.equal(writes.some(w=>JSON.stringify(w.update.fields).includes('superadmin"')),false);
 assert.match(p.photos[0].target,/^profile_photos\/synthetic_student\/migrated_[a-f0-9]{24}$/);assert.equal(p.photos[0].legacyTokens.length,1);assert.deepEqual(buildPlan(b),p);
});
test('No publica referencias sin copia comprobada y rechaza rutas/bytes manipulados',()=>{
 const p=buildPlan(fixture());assert.throws(()=>firestoreWrites(p,{}),/copy-not-verified/);
 for(const change of ['url','bytes','auth','existingRole']){const b=fixture();if(change==='url')b.firestore.documents[0].fields.photoUrls=encode(['https://attacker.test/image']);if(change==='bytes')b.storage.files[0].bytesBase64=Buffer.from('tampered').toString('base64');if(change==='auth')b.auth.users=[];if(change==='existingRole')b.firestore.documents.push(raw('accountAccess/synthetic_student',{role:'admin'}));assert.throws(()=>buildPlan(b));}
});
test('Autorización explícita y mantenimiento obligatorios antes de cualquier I/O',async()=>{
 for(const options of [{apply:false,maintenance:true,kind:'migrate'},{apply:true,maintenance:false,kind:'migrate'},{apply:true,maintenance:false,kind:'revoke'},{apply:false,kind:'bootstrap'}])assert.throws(()=>assertExecution(options));
 let contacted=false;await assert.rejects(()=>migrate({plan:buildPlan(fixture()),backup:fixture(),apply:false,clientFactory:async()=>{contacted=true;}}));assert.equal(contacted,false);
});
test('Reejecución posterior a commit no cambia roles ni datos',async()=>{
 const backup=fixture(),plan=buildPlan(backup);let commits=0;
 const client={read:async url=>{
  if(url.includes('/releases'))return {releases:[{name:'projects/tinder-universitario/releases/cloud.firestore',rulesetName:'projects/tinder-universitario/rulesets/maintenance'},{name:'projects/tinder-universitario/releases/firebase.storage/tinder-universitario.firebasestorage.app',rulesetName:'projects/tinder-universitario/rulesets/storage'}]};
  if(url.endsWith('/maintenance'))return {source:{files:[{content:readFileSync(new URL('../../deploy/firestore.maintenance.rules',import.meta.url),'utf8')}]}};
  if(url.endsWith('/storage'))return {source:{files:[{content:readFileSync(new URL('../../storage.rules',import.meta.url),'utf8')}]}};
  if(url.endsWith('/iam'))return {bindings:[]};throw Error('unexpected-network');
 },get:async()=>({fields:encode({state:'committed',sourceSha256:plan.sourceSha256}).mapValue.fields}),commit:async()=>commits++};
 assert.deepEqual(await migrate({plan,backup,apply:true,maintenance:true,clientFactory:async()=>client}),{idempotent:true});assert.equal(commits,0);
});
function bootstrapInput(){const uid='synthetic_operator';return {uid,email:'operator@unit-fixture.edu',authUser:{localId:uid,email:'operator@unit-fixture.edu',emailVerified:true},reviewConfirmed:true,access:raw('accountAccess/'+uid,{role:'user',verificationStatus:'pending',suspended:false}),registry:raw('administration/roles',{superadminIds:[]}),profile:raw('users/'+uid,{datingAllowed:false})};}
test('Bootstrap exige identidad confirmada, correo verificado y revisión humana',()=>{
 for(const change of ['review','email','disabled','verified','demo']){const p=bootstrapInput();if(change==='review')p.reviewConfirmed=false;if(change==='email')p.email='wrong@unit-fixture.edu';if(change==='disabled')p.authUser.disabled=true;if(change==='verified')p.authUser.emailVerified=false;if(change==='demo')p.authUser.email=p.email='superadmin@demo.test';assert.throws(()=>bootstrapWrites(p));}
 const writes=bootstrapWrites(bootstrapInput());assert.equal(writes.length,4);assert.equal(value(writes[0].update.fields.role),'superadmin');assert.equal(value(writes[0].update.fields.verificationStatus),'approved');assert.equal(writes.every(w=>!!w.currentDocument),true);
});
test('Bootstrap consumido no reemplaza superadmin y repetición no vuelve a conceder',()=>{
 const p=bootstrapInput();p.registry=raw('administration/roles',{superadminIds:['someone_else']});assert.throws(()=>bootstrapWrites(p));
 p.registry=raw('administration/roles',{superadminIds:[p.uid]});p.access=raw('accountAccess/'+p.uid,{role:'superadmin',verificationStatus:'approved',suspended:false});assert.deepEqual(bootstrapWrites(p),[]);
});

test('Migración completa con adaptador local: copia, commit atómico, reanudación y rol posterior',async()=>{
 const backup=fixture(),plan=buildPlan(backup),rows=new Map(backup.firestore.documents.map(d=>[d.name,structuredClone(d)]));
 const target=plan.photos[0].target,bytes=Buffer.from(backup.storage.files[0].bytesBase64,'base64'),objects=new Map([[plan.photos[0].source,{...backup.storage.files[0].metadata,acl:[]}]]);let uploads=0,commits=0;
 const markerName=prefix+'migrationState/five-phases-v1';
 const read=async(url,body,options)=>{
  if(url.includes('firebaserules.googleapis.com')){if(url.includes('/releases'))return {releases:[{name:'projects/tinder-universitario/releases/cloud.firestore',rulesetName:'projects/tinder-universitario/rulesets/maintenance'},{name:'projects/tinder-universitario/releases/firebase.storage/tinder-universitario.firebasestorage.app',rulesetName:'projects/tinder-universitario/rulesets/storage'}]};return {source:{files:[{content:readFileSync(new URL(url.endsWith('/maintenance')?'../../deploy/firestore.maintenance.rules':'../../storage.rules',import.meta.url),'utf8')}]}};}
  if(url.endsWith('/iam'))return {bindings:[]};
  if(url.includes('identitytoolkit.googleapis.com'))return {users:backup.auth.users};
  if(new URL(url).pathname.endsWith('/o'))return {items:[...objects.values()]};
  if(url.includes('storage.googleapis.com')){const name=decodeURIComponent(new URL(url).pathname.split('/o/')[1]);return options?.binary?bytes:objects.get(name);}
  const u=new URL(url),name=u.pathname.replace('/v1/','');
  if(url.endsWith(':runQuery'))return [{readTime:time}];
  if(url.endsWith(':listCollectionIds')){const parent=name.slice(0,-':listCollectionIds'.length)+'/';return {collectionIds:[...new Set([...rows.keys()].filter(k=>k.startsWith(parent)).map(k=>k.slice(parent.length).split('/')[0]))]};}
  if(u.searchParams.has('showMissing'))return {documents:[...rows.values()].filter(d=>d.name.startsWith(name+'/')&&d.name.slice(name.length+1).split('/').length===1)};
  return rows.get(name);
 };
 const client={read,get:async url=>{if(url.includes('storage.googleapis.com'))return objects.get(decodeURIComponent(new URL(url).pathname.split('/o/')[1]))??null;return rows.get(new URL(url).pathname.replace('/v1/',''))??null;},write:async(url,method,data,mime)=>{assert.equal(method,'POST');assert.equal(new URL(url).searchParams.get('ifGenerationMatch'),'0');assert.equal(new URL(url).searchParams.get('predefinedAcl'),'private');assert.deepEqual(data,bytes);uploads++;const m={name:target,size:String(bytes.length),contentType:mime,generation:'2'};objects.set(target,m);return m;},commit:async writes=>{
  for(const w of writes){const old=rows.get(w.update.name);if(w.currentDocument.exists===false)assert.equal(old,undefined);else assert.equal(old?.updateTime,w.currentDocument.updateTime);}
  for(const w of writes){const old=rows.get(w.update.name);rows.set(w.update.name,{...old,...w.update,fields:w.updateMask?{...old.fields,...w.update.fields}:w.update.fields,createTime:old?.createTime??time,updateTime:'2026-01-02T00:00:00Z'});}commits++;
 }};
 const result=await migrate({plan,backup,apply:true,maintenance:true,clientFactory:async()=>client});assert.equal(result.grants,0);assert.equal(uploads,1);assert.equal(commits,2);assert.equal(value(rows.get(markerName).fields.state),'committed');assert.equal(value(rows.get(prefix+'accountAccess/synthetic_student').fields.verificationStatus),'pending');
 assert.deepEqual(rows.get(prefix+'matches/synthetic_pair'),backup.firestore.documents[1]);assert.deepEqual(rows.get(prefix+'matches/synthetic_pair/messages/legacy'),backup.firestore.documents[2]);assert.deepEqual(rows.get(prefix+'preferences/synthetic_student'),backup.firestore.documents[3]);assert.equal(objects.has(plan.photos[0].source),true);
 const access=rows.get(prefix+'accountAccess/synthetic_student');access.fields.role=encode('admin');access.fields.verificationStatus=encode('approved');
 assert.deepEqual(await migrate({plan,backup,apply:true,maintenance:true,clientFactory:async()=>client}),{idempotent:true});assert.equal(uploads,1);assert.equal(commits,2);assert.equal(value(access.fields.role),'admin');
});

test('Revocación verifica tokens del respaldo aunque un intento anterior ya borró metadata',async t=>{
 const plan=buildPlan(fixture()),photo=plan.photos[0],bytes=Buffer.from('synthetic-unit-bytes');let heads=0,commits=0;
 const client={read:async(url,body,options)=>{
  if(url.includes('/releases'))return {releases:[{name:'projects/tinder-universitario/releases/cloud.firestore',rulesetName:'projects/tinder-universitario/rulesets/firestore'},{name:'projects/tinder-universitario/releases/firebase.storage/tinder-universitario.firebasestorage.app',rulesetName:'projects/tinder-universitario/rulesets/storage'}]};
  if(url.includes('/rulesets/'))return {source:{files:[{content:readFileSync(new URL(url.endsWith('/storage')?'../../storage.rules':'../../firestore.rules',import.meta.url),'utf8')}]}};
  if(url.includes('/migrationState/'))return raw('migrationState/five-phases-v1',{state:'committed',sourceSha256:plan.sourceSha256});
  if(url.includes('/users/'))return {fields:plan.profiles[0].patch};
  if(url.includes('/profilePhotoAssets/'))return {fields:encode({sha256:photo.sha256,generation:'2'}).mapValue.fields};
  if(url.includes('storage.googleapis.com'))return options?.binary?bytes:{generation:url.includes(encodeURIComponent(photo.target))?'2':'1',metageneration:'2',metadata:{},cacheControl:'private, no-store'};
  throw Error('unexpected-read');
 },write:async()=>{throw Error('unnecessary-metadata-write');},commit:async()=>commits++};
 t.mock.method(globalThis,'fetch',async(url,options)=>{assert.equal(options.method,'HEAD');assert.equal(options.headers,undefined);assert.ok(url.includes('SYNTHETIC_TOKEN'));heads++;return new Response(null,{status:403});});
 assert.deepEqual(await revoke({plan,apply:true,maintenance:true,clientFactory:async()=>client}),{revoked:true,deleted:0});assert.equal(heads,1);assert.equal(commits,1);
 t.mock.restoreAll();t.mock.method(globalThis,'fetch',async()=>new Response(null,{status:200}));await assert.rejects(()=>revoke({plan,apply:true,maintenance:true,clientFactory:async()=>client}),/old-token-still-usable/);assert.equal(commits,1);
});
