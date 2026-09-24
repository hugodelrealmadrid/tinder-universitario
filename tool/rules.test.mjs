import { readFile } from 'node:fs/promises';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, getDocs, collection, Timestamp, serverTimestamp, query, where, limit, orderBy, documentId, writeBatch, deleteDoc } from 'firebase/firestore';
import { ref, uploadBytes, deleteObject, getMetadata } from 'firebase/storage';
import { runTransaction } from 'firebase/firestore';
import assert from 'node:assert/strict';

let env;
const baseUrl = uid => `https://firebasestorage.googleapis.com/v0/b/tinder-universitario.firebasestorage.app/o/profile_photos%2F${uid}%2Fphoto1?alt=media&token=abc-123`;
const initial = () => ({firstName:'',lastName:'',email:'ana@example.com',birthDate:Timestamp.fromDate(new Date('2000-01-01T00:00:00Z')),gender:'',description:'',careerId:null,photoUrls:[],mainPhotoUrl:null,interestIds:[],role:'user',isActive:false,createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
const context = uid => env.authenticatedContext(uid, {email:`${uid}@example.com`});
const db = () => context('ana').firestore();
const profileRef = () => doc(db(), 'users/ana');
const update = data => updateDoc(profileRef(), {...data, updatedAt:serverTimestamp()});
const complete = () => ({firstName:'Ana',lastName:'Pérez',gender:'femenino',careerId:'sistemas',photoUrls:[baseUrl('ana')],mainPhotoUrl:baseUrl('ana'),isActive:true});

before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-tinder-universitario',
    firestore:{host:'127.0.0.1',port:8088,rules:(await readFile(new URL('../firestore.rules',import.meta.url),'utf8')).replace(/^\uFEFF/,'')},
    storage:{host:'127.0.0.1',port:9198,rules:(await readFile(new URL('../storage.rules',import.meta.url),'utf8')).replace(/^\uFEFF/,'')},
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async admin => {
    const store = admin.firestore();
    await setDoc(doc(store,'users/ana'), initial());
    await setDoc(doc(store,'careers/sistemas'), {name:'Sistemas',isActive:true});
    await setDoc(doc(store,'careers/inactiva'), {name:'Inactiva',isActive:false});
    for (let i=0;i<5;i++) await setDoc(doc(store,`interests/i${i}`), {name:`Interés ${i}`,isActive:true});
    await setDoc(doc(store,'interests/inactivo'), {name:'Anterior',isActive:false});
  });
});

test('Registro crea solo user e inactivo', async () => {
  const bob = doc(context('bob').firestore(),'users/bob');
  await assertFails(setDoc(bob,{...initial(),email:'bob@example.com',role:'admin'}));
  await assertFails(setDoc(bob,{...initial(),email:'bob@example.com',isActive:true}));
  await assertSucceeds(setDoc(bob,{...initial(),email:'bob@example.com'}));
});
test('Solo propietario lee su perfil; no listado ni acceso anónimo', async () => {
  await assertSucceeds(getDoc(profileRef()));
  await assertFails(getDoc(doc(context('bob').firestore(),'users/ana')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'users/ana')));
  await assertFails(getDocs(collection(db(),'users')));
});
test('Guardado parcial permitido sin activación', async () => {
  await assertSucceeds(update({firstName:'Ana', birthDate:null}));
  await assertFails(update({isActive:true}));
});
test('Campos protegidos, perfiles ajenos y campos extra rechazados', async () => {
  for (const change of [{role:'admin'},{role:'superadmin'},{email:'otro@example.com'},{createdAt:Timestamp.now()},{semester:2},{careerIds:['sistemas']}]) {
    await assertFails(update(change));
  }
  await assertFails(updateDoc(doc(context('bob').firestore(),'users/ana'),{firstName:'Intruso',updatedAt:serverTimestamp()}));
});
test('Perfil completo activa; principal debe existir y última foto desactiva', async () => {
  await assertFails(update({...complete(),mainPhotoUrl:baseUrl('bob')}));
  await assertSucceeds(update(complete()));
  await assertFails(update({photoUrls:[],mainPhotoUrl:null}));
  await assertSucceeds(update({photoUrls:[],mainPhotoUrl:null,isActive:false}));
});
test('Edad, nombres vacíos y descripción larga se validan', async () => {
  await assertFails(update({birthDate:Timestamp.now()}));
  await assertFails(update({...complete(),firstName:'   '}));
  await assertFails(update({...complete(),gender:''}));
  await assertFails(update({description:'x'.repeat(501)}));
});
test('Carrera única activa e intereses del catálogo', async () => {
  await assertFails(update({careerId:['sistemas']}));
  await assertFails(update({careerId:'inactiva'}));
  await assertFails(update({careerId:'inventada'}));
  await assertFails(update({interestIds:['inactivo']}));
  await assertFails(update({interestIds:['inventado']}));
  await assertFails(update({interestIds:['i0','i0']}));
  await assertSucceeds(update({...complete(),interestIds:['i0','i1','i2','i3','i4']}));
  await assertSucceeds(update({interestIds:[],isActive:false}));
});
test('Catálogos legibles solo con sesión y sin escritura cliente', async () => {
  await assertSucceeds(getDocs(collection(db(),'careers')));
  await assertSucceeds(getDocs(collection(db(),'interests')));
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),'careers')));
  await assertFails(setDoc(doc(db(),'careers/nueva'),{name:'Nueva',isActive:true}));
});
test('Solo URLs propias, máximo 6 fotos y sin duplicados', async () => {
  await assertFails(update({photoUrls:[baseUrl('bob')],mainPhotoUrl:baseUrl('bob')}));
  await assertFails(update({photoUrls:['https://example.com/foto.jpg'],mainPhotoUrl:'https://example.com/foto.jpg'}));
  await assertFails(update({photoUrls:[baseUrl('ana'),baseUrl('ana')],mainPhotoUrl:baseUrl('ana')}));
  const urls = Array.from({length:7},(_,i)=>baseUrl('ana').replace('photo1',`photo${i}`));
  await assertFails(update({photoUrls:urls,mainPhotoUrl:urls[0]}));
});
test('Storage propietario sube/lee/elimina; terceros y anónimos no', async () => {
  const path='profile_photos/ana/securityPhoto';
  const own=ref(context('ana').storage(),path);
  await assertSucceeds(uploadBytes(own,new Uint8Array([255,216,255]),{contentType:'image/jpeg'}));
  await assertSucceeds(getMetadata(own));
  await assertFails(getMetadata(ref(context('bob').storage(),path)));
  await assertFails(deleteObject(ref(context('bob').storage(),path)));
  await assertFails(uploadBytes(ref(context('bob').storage(),'profile_photos/ana/intruder'),new Uint8Array([1]),{contentType:'image/png'}));
  await assertFails(getMetadata(ref(env.unauthenticatedContext().storage(),path)));
  await assertFails(uploadBytes(own,new Uint8Array([1]),{contentType:'image/png'}));
  await assertSucceeds(deleteObject(own));
});
test('Storage rechaza formato, tamaño y carpetas fuera de alcance', async () => {
  const store=context('ana').storage();
  await assertFails(uploadBytes(ref(store,'profile_photos/ana/text'),new Uint8Array([1]),{contentType:'text/plain'}));
  await assertFails(uploadBytes(ref(store,'profile_photos/ana/huge'),new Uint8Array(5*1024*1024+1),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(store,'public/file'),new Uint8Array([1]),{contentType:'image/png'}));
});


test('Géneros exactos masculino/femenino permiten guardar y activar', async () => {
  for (const gender of ['masculino','femenino']) {
    await assertSucceeds(update({...complete(),gender}));
  }
});
test('No se pueden introducir géneros libres ni vaciar un género válido', async () => {
  for (const gender of ['masculno','Masculino','Femenino ','hombre','otro']) {
    await assertFails(update({gender,isActive:false}));
    await assertFails(update({...complete(),gender}));
  }
  await assertSucceeds(update({gender:'masculino'}));
  await assertFails(update({gender:''}));
});
test('Legado no se migra al leer; permite conservarlo inactivo y corregirlo explícitamente', async () => {
  await env.withSecurityRulesDisabled(async admin => {
    await updateDoc(doc(admin.firestore(),'users/ana'),{...complete(),gender:'Masculino'});
  });
  const before = (await getDoc(profileRef())).data();
  const after = (await getDoc(profileRef())).data();
  if (before.gender !== after.gender || after.gender !== 'Masculino' || !after.isActive) throw new Error('Lectura alteró datos');
  await assertFails(update({isActive:true}));
  await assertSucceeds(update({isActive:false}));
  await assertSucceeds(update({description:'Borrador conservado'}));
  await assertFails(update({gender:'Mujer'}));
  await assertSucceeds(update({gender:'femenino',isActive:true}));
});


const preference = (gender='ambos', min=18, max=100) => ({minAge:min,maxAge:max,preferredGender:gender,updatedAt:serverTimestamp()});
const projection = data => Object.fromEntries(['firstName','birthDate','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'].map(key=>[key,data[key]]));
const birthday = age => { const now = new Date(); return Timestamp.fromDate(new Date(Date.UTC(now.getUTCFullYear()-age,now.getUTCMonth(),now.getUTCDate()))); };
async function seedDiscovery(options={}) {
  await env.withSecurityRulesDisabled(async admin => {
    const store=admin.firestore();
    const entries=[
      ['ana',options.aGender??'masculino',options.aAge??22,options.aActive??true,options.aPreferred??'femenino',options.aMin??20,options.aMax??25],
      ['bob',options.bGender??'femenino',options.bAge??21,options.bActive??true,options.bPreferred??'masculino',options.bMin??20,options.bMax??24],
    ];
    for (const [uid,gender,age,active,preferred,min,max] of entries) {
      const refUser=doc(store,`users/${uid}`);
      await setDoc(refUser,{...initial(),email:`${uid}@example.com`,firstName:uid==='bob'&&options.incomplete?'':'Estudiante',lastName:'Prueba',gender,birthDate:birthday(age),careerId:'sistemas',photoUrls:[baseUrl(uid)],mainPhotoUrl:baseUrl(uid),isActive:active});
      const data=(await getDoc(refUser)).data();
      await setDoc(doc(store,`discoveryCards/${uid}`),projection(data));
      await setDoc(doc(store,`discoveryIndex/${uid}`),{isActive:active,updatedAt:data.updatedAt});
      if (!(uid==='bob'&&options.noPreferences)) await setDoc(doc(store,`preferences/${uid}`),preference(preferred,min,max));
      else await deleteDoc(doc(store,`preferences/${uid}`));
    }
  });
}
const cardForBob = () => doc(db(),'discoveryCards/bob');
const swipe = (from='ana',to='bob',type='like') => ({fromUserId:from,toUserId:to,type,createdAt:serverTimestamp()});

test('Preferencias: tipos, rango 18..100, orden y géneros exactos', async () => {
  const pref=doc(db(),'preferences/ana');
  for (const gender of ['masculino','femenino','ambos']) await assertSucceeds(setDoc(pref,preference(gender)));
  for (const value of [preference('otro'),preference('Femenino'),preference('ambos',17,30),preference('ambos',30,20),preference('ambos',18,101),preference('ambos',18.5,30),{...preference(),extra:true}]) await assertFails(setDoc(pref,value));
});
test('Preferencias permanecen privadas y solo el dueño puede escribir', async () => {
  await assertSucceeds(setDoc(doc(db(),'preferences/ana'),preference()));
  await assertSucceeds(getDoc(doc(db(),'preferences/ana')));
  await assertFails(getDoc(doc(context('bob').firestore(),'preferences/ana')));
  await assertFails(setDoc(doc(context('bob').firestore(),'preferences/ana'),preference()));
  await assertFails(getDocs(collection(db(),'preferences')));
  await assertFails(deleteDoc(doc(db(),'preferences/ana')));
});
test('Compatibilidad recíproca autoriza ambas fichas sin abrir users ni preferences', async () => {
  await seedDiscovery();
  const card=await assertSucceeds(getDoc(cardForBob()));
  if ('email' in card.data() || 'role' in card.data() || 'preferredGender' in card.data()) throw new Error('Ficha expone campos privados');
  await assertSucceeds(getDoc(doc(context('bob').firestore(),'discoveryCards/ana')));
  await assertFails(getDoc(doc(db(),'users/bob')));
  await assertFails(getDoc(doc(db(),'preferences/bob')));
  await assertFails(getDocs(collection(db(),'discoveryCards')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'discoveryCards/bob')));
});
test('Género debe ser compatible en ambos sentidos; ambos acepta los dos', async () => {
  await seedDiscovery({bPreferred:'femenino'});
  await assertFails(getDoc(cardForBob())); // A acepta B, pero B no acepta A.
  await seedDiscovery({aPreferred:'masculino'});
  await assertFails(getDoc(cardForBob())); // B acepta A, pero A no acepta B.
  for (const bGender of ['masculino','femenino']) {
    await seedDiscovery({aPreferred:'ambos',bPreferred:'ambos',bGender});
    await assertSucceeds(getDoc(cardForBob()));
  }
});
test('Rango de edad recíproco inclusivo, sin preferencia no descubre', async () => {
  await seedDiscovery({aMin:21,aMax:21,bMin:22,bMax:22});
  await assertSucceeds(getDoc(cardForBob()));
  await seedDiscovery({bMin:23,bMax:30});
  await assertFails(getDoc(cardForBob()));
  await seedDiscovery({aMin:22,aMax:25});
  await assertFails(getDoc(cardForBob()));
  await seedDiscovery({noPreferences:true});
  await assertFails(getDoc(cardForBob()));
});
test('Inactivos, incompletos y fichas desactualizadas no se leen', async () => {
  for (const options of [{bActive:false},{aActive:false},{incomplete:true}]) {
    await seedDiscovery(options); await assertFails(getDoc(cardForBob()));
  }
  await seedDiscovery();
  await env.withSecurityRulesDisabled(admin=>updateDoc(doc(admin.firestore(),'users/bob'),{description:'Cambio posterior',updatedAt:serverTimestamp()}));
  await assertFails(getDoc(cardForBob()));
});
test('Índice limitado a activos y paginado, sin permiso para añadir datos privados', async () => {
  await seedDiscovery();
  await assertSucceeds(getDocs(query(collection(db(),'discoveryIndex'),where('isActive','==',true),orderBy(documentId()),limit(25))));
  await assertFails(getDocs(collection(db(),'discoveryIndex')));
  await assertFails(getDocs(query(collection(db(),'discoveryIndex'),where('isActive','==',true),limit(26))));
  await assertFails(updateDoc(doc(db(),'discoveryIndex/ana'),{email:'ana@example.com'}));
  await assertFails(setDoc(doc(db(),'discoveryIndex/bob'),{isActive:true,updatedAt:serverTimestamp()}));
});
test('Perfil y publicación se guardan atómicamente; no se pueden falsificar fichas', async () => {
  await seedDiscovery();
  const data=(await getDoc(profileRef())).data();
  const changes={description:'Actualizado',updatedAt:serverTimestamp()};
  const store=db();
  const batch=writeBatch(store);
  batch.update(doc(store,'users/ana'),changes);
  batch.set(doc(store,'discoveryCards/ana'),projection({...data,...changes}));
  batch.set(doc(store,'discoveryIndex/ana'),{isActive:true,updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(context('bob').firestore(),'discoveryCards/ana')));
  await assertFails(updateDoc(doc(db(),'discoveryCards/ana'),{email:'ana@example.com'}));
  await assertFails(updateDoc(doc(db(),'discoveryCards/ana'),{firstName:'Falso'}));
  await assertFails(updateDoc(doc(db(),'discoveryCards/bob'),{firstName:'Intruso'}));
});
test('Swipe: dueño, tipo, destino y ID direccional obligatorios', async () => {
  await seedDiscovery();
  await assertFails(setDoc(doc(db(),'swipes/ana.ana'),swipe('ana','ana')));
  await assertFails(setDoc(doc(db(),'swipes/ana.bob'),swipe('ana','bob','match')));
  await assertFails(setDoc(doc(db(),'swipes/bob.ana'),swipe('bob','ana')));
  await assertFails(setDoc(doc(db(),'swipes/aleatorio'),swipe()));
  await assertFails(setDoc(doc(db(),'swipes/ana.inexistente'),swipe('ana','inexistente')));
  await assertFails(setDoc(doc(db(),'swipes/ana.bob'),{...swipe(),extra:true}));
  await seedDiscovery({bActive:false});
  await assertFails(setDoc(doc(db(),'swipes/ana.bob'),swipe()));
  await seedDiscovery({bPreferred:'femenino'});
  await assertFails(setDoc(doc(db(),'swipes/ana.bob'),swipe()));
});
test('LIKE/PASS inmutables: no segundo swipe, actualización ni borrado; candidato desaparece', async () => {
  await seedDiscovery();
  const refSwipe=doc(db(),'swipes/ana.bob');
  await assertSucceeds(getDoc(refSwipe)); // Inexistencia legible para la transacción.
  await assertSucceeds(setDoc(refSwipe,swipe()));
  await assertFails(setDoc(refSwipe,swipe('ana','bob','pass')));
  await assertFails(updateDoc(refSwipe,{type:'pass'}));
  await assertFails(updateDoc(refSwipe,{toUserId:'ana'}));
  await assertFails(deleteDoc(refSwipe));
  await assertFails(getDoc(cardForBob()));
  await assertSucceeds(getDocs(query(collection(db(),'swipes'),where('fromUserId','==','ana'))));
  await assertFails(getDocs(query(collection(context('bob').firestore(),'swipes'),where('fromUserId','==','ana'))));
  await assertSucceeds(getDoc(doc(context('bob').firestore(),'swipes/ana.bob'))); // Lectura puntual inversa para matches.
  await assertFails(getDoc(doc(context('carol').firestore(),'swipes/ana.bob')));
  await assertSucceeds(setDoc(doc(context('bob').firestore(),'swipes/bob.ana'),swipe('bob','ana','pass')));
});

const matchData = (a='ana', b='bob') => ({users:[a,b].sort(),createdAt:serverTimestamp(),isActive:true});
const matchId = (a,b) => [a,b].sort().join('.');
// Misma secuencia de lecturas/escrituras que DiscoveryService.decide; aquí se
// ejecuta contra el emulador real para probar reglas y reintentos concurrentes.
async function decideWithMatch(from,to,type='like',barrier) {
  const store=context(from).firestore();
  let firstAttempt=true;
  const commit=()=>runTransaction(store,async tx=>{
    const own=doc(store,`swipes/${from}.${to}`);
    if ((await tx.get(own)).exists()) throw new Error('Ya evaluado');
    const card=await tx.get(doc(store,`discoveryCards/${to}`));
    assert.equal(card.data().isActive,true);
    const target=doc(store,`matches/${matchId(from,to)}`);
    let create=false;
    if (type==='like') {
      const inverse=await tx.get(doc(store,`swipes/${to}.${from}`));
      const existing=await tx.get(target);
      create=inverse.data()?.type==='like'&&!existing.exists();
    }
    if (firstAttempt&&barrier) {firstAttempt=false;await barrier();}
    tx.set(own,swipe(from,to,type));
    if (create) tx.set(target,matchData(from,to));
    return create;
  });
  try { return await commit(); }
  catch (error) {
    if (error.code!=='permission-denied'||type!=='like') throw error;
    return commit();
  }
}

test('Match: LIKE unilateral no crea; recíproco crea exactamente uno activo', async()=>{
  await seedDiscovery();
  assert.equal(await decideWithMatch('ana','bob'),false);
  assert.equal((await getDoc(doc(db(),'matches/ana.bob'))).exists(),false);
  assert.equal(await decideWithMatch('bob','ana'),true);
  const result=await getDoc(doc(db(),'matches/ana.bob'));
  assert.deepEqual(result.data().users,['ana','bob']);
  assert.equal(result.data().isActive,true);
  assert.ok(result.data().createdAt instanceof Timestamp);
  assert.equal((await getDoc(doc(db(),'matches/bob.ana'))).exists(),false);
});

test('Match: PASS y LIKE en ambos órdenes nunca crean match', async()=>{
  await seedDiscovery();
  assert.equal(await decideWithMatch('ana','bob','pass'),false);
  assert.equal(await decideWithMatch('bob','ana','like'),false);
  assert.equal((await getDoc(doc(db(),'matches/ana.bob'))).exists(),false);
});

test('Match: segundo LIKE debe crear el match atómicamente', async()=>{
  await seedDiscovery();
  await decideWithMatch('ana','bob');
  await assertFails(setDoc(doc(context('bob').firestore(),'swipes/bob.ana'),swipe('bob','ana')));
  assert.equal((await getDoc(doc(context('bob').firestore(),'swipes/bob.ana'))).exists(),false);
  await assertSucceeds(decideWithMatch('bob','ana'));
});

test('Match: creación sin dos LIKE y con PASS rechazada', async()=>{
  await seedDiscovery();
  await assertFails(setDoc(doc(db(),'matches/ana.bob'),matchData()));
  await decideWithMatch('ana','bob');
  await assertFails(setDoc(doc(db(),'matches/ana.bob'),matchData()));
  await decideWithMatch('bob','ana','pass');
  await assertFails(setDoc(doc(db(),'matches/ana.bob'),matchData()));
});

async function seedMutualLikes() {
  await seedDiscovery();
  await env.withSecurityRulesDisabled(async admin=>{
    await setDoc(doc(admin.firestore(),'swipes/ana.bob'),swipe());
    await setDoc(doc(admin.firestore(),'swipes/bob.ana'),swipe('bob','ana'));
  });
}

test('Match: orden, ID, dos UID diferentes, remitentes y esquema estrictos', async()=>{
  await seedMutualLikes();
  for (const [id,data] of [
    ['bob.ana',{...matchData(),users:['bob','ana']}],
    ['aleatorio',matchData()], ['ana.ana',matchData('ana','ana')],
    ['ana.bob',{...matchData(),users:['ana']}],
    ['ana.bob',{...matchData(),users:['ana','bob','carol']}],
    ['ana.bob',{...matchData(),isActive:false}],
    ['ana.bob',{...matchData(),email:'privado@example.com'}],
    ['ana.bob',{...matchData(),createdAt:Timestamp.fromMillis(0)}],
  ]) await assertFails(setDoc(doc(db(),`matches/${id}`),data));
  await assertFails(setDoc(doc(context('carol').firestore(),'matches/ana.bob'),matchData()));
  await env.withSecurityRulesDisabled(admin=>updateDoc(doc(admin.firestore(),'swipes/bob.ana'),{fromUserId:'carol'}));
  await assertFails(setDoc(doc(db(),'matches/ana.bob'),matchData()));
});

test('Match: participantes leen/listan, terceros y anónimos no; update/delete denegados', async()=>{
  await seedDiscovery();
  await decideWithMatch('ana','bob'); await decideWithMatch('bob','ana');
  for (const uid of ['ana','bob']) {
    const store=context(uid).firestore();
    await assertSucceeds(getDoc(doc(store,'matches/ana.bob')));
    const list=await assertSucceeds(getDocs(query(collection(store,'matches'),where('users','array-contains',uid))));
    assert.equal(list.size,1);
    await assertFails(updateDoc(doc(store,'matches/ana.bob'),{isActive:false}));
    await assertFails(setDoc(doc(store,'matches/ana.bob'),matchData()));
    await assertFails(deleteDoc(doc(store,'matches/ana.bob')));
  }
  const third=context('carol').firestore();
  await assertFails(getDoc(doc(third,'matches/ana.bob')));
  assert.equal((await getDocs(query(collection(third,'matches'),where('users','array-contains','carol')))).size,0);
  await assertFails(getDocs(query(collection(third,'matches'),where('users','array-contains','ana'))));
  await assertFails(getDocs(collection(db(),'matches')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'matches/ana.bob')));
});

test('Match autoriza ficha pese a swipe y preferencias cambiadas, sin abrir datos privados', async()=>{
  await seedDiscovery();
  await decideWithMatch('ana','bob'); await decideWithMatch('bob','ana');
  await assertSucceeds(getDoc(cardForBob()));
  await assertSucceeds(setDoc(doc(db(),'preferences/ana'),preference('masculino')));
  await assertSucceeds(getDoc(cardForBob()));
  await assertFails(getDoc(doc(db(),'users/bob')));
  await assertFails(getDoc(doc(db(),'preferences/bob')));
  await assertFails(getDoc(doc(context('carol').firestore(),'discoveryCards/bob')));
  await env.withSecurityRulesDisabled(admin=>updateDoc(doc(admin.firestore(),'users/bob'),{isActive:false}));
  await assertFails(getDoc(cardForBob()));
  await assertSucceeds(getDoc(doc(db(),'matches/ana.bob')));
});

test('Dos LIKE concurrentes con lectura inicial simultánea terminan en dos swipes y un match', async()=>{
  await seedDiscovery();
  let arrivals=0, release;
  const ready=new Promise(resolve=>{release=resolve;});
  const barrier=async()=>{if (++arrivals===2) release(); await ready;};
  const results=await Promise.all([
    decideWithMatch('ana','bob','like',barrier),
    decideWithMatch('bob','ana','like',barrier),
  ]);
  assert.deepEqual(results.sort(),[false,true]);
  await env.withSecurityRulesDisabled(async admin=>{
    assert.equal((await getDocs(collection(admin.firestore(),'swipes'))).size,2);
    assert.equal((await getDocs(collection(admin.firestore(),'matches'))).size,1);
  });
});


