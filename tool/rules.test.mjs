import { readFile } from 'node:fs/promises';
// HU-15 se prueba al final de esta suite, sin operaciones sobre Firebase remoto.
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, getDocs, collection, Timestamp, serverTimestamp, query, where, limit, orderBy, documentId, writeBatch, deleteDoc } from 'firebase/firestore';
import { ref, uploadBytes, deleteObject, getMetadata } from 'firebase/storage';
import { runTransaction, onSnapshot } from 'firebase/firestore';
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
const ageAt = (birth, now = new Date()) => {
  const date = birth.toDate();
  return now.getUTCFullYear() - date.getUTCFullYear() -
    ((now.getUTCMonth() < date.getUTCMonth() || (now.getUTCMonth() === date.getUTCMonth() && now.getUTCDate() < date.getUTCDate())) ? 1 : 0);
};
const projection = data => ({
  ...Object.fromEntries(['firstName','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'].map(key=>[key,data[key]])),
  age: data.birthDate instanceof Timestamp ? ageAt(data.birthDate) : null,
});
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
  if (['birthDate','email','role','preferredGender','minAge','maxAge','lastName','photoUrls'].some(key => key in card.data())) throw new Error('Ficha expone campos privados');
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



test('Privacidad: Discovery entrega edad entera y solo campos públicos permitidos', async () => {
  await seedDiscovery();
  const card = (await assertSucceeds(getDoc(cardForBob()))).data();
  assert.equal(card.age, 21);
  assert.deepEqual(Object.keys(card).sort(), ['firstName','age','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'].sort());
  const index = await getDocs(query(collection(db(),'discoveryIndex'),where('isActive','==',true),limit(25)));
  for (const row of index.docs) assert.deepEqual(Object.keys(row.data()).sort(), ['isActive','updatedAt'].sort());
  assert.ok((await getDoc(doc(context('bob').firestore(),'users/bob'))).data().birthDate instanceof Timestamp);
});

test('Privacidad: fichas legadas con birthDate son ilegibles incluso para un match', async () => {
  await seedDiscovery();
  await decideWithMatch('ana','bob'); await decideWithMatch('bob','ana');
  await env.withSecurityRulesDisabled(async admin => {
    const store = admin.firestore();
    const user = (await getDoc(doc(store,'users/bob'))).data();
    const legacy = projection(user); delete legacy.age; legacy.birthDate = user.birthDate;
    await setDoc(doc(store,'discoveryCards/bob'), legacy);
  });
  await assertFails(getDoc(cardForBob()));
  await assertSucceeds(getDoc(doc(db(),'matches/ana.bob')));
  await assertSucceeds(getDoc(doc(context('bob').firestore(),'users/bob')));
});

test('Privacidad: edad falsificada, fecha exacta y preferencias extra rechazadas al publicar', async () => {
  await seedDiscovery();
  const user = (await getDoc(profileRef())).data();
  for (const change of [{age:18},{age:22.5},{age:null},{birthDate:user.birthDate},{email:user.email},
    {minAge:18},{preferredGender:'ambos'},{internalFlag:true}]) {
    await assertFails(setDoc(doc(db(),'discoveryCards/ana'), {...projection(user), ...change}));
  }
});

test('Privacidad: edad vencida tras cumpleaños no se muestra hasta republicar', async () => {
  await seedDiscovery();
  await decideWithMatch('ana','bob'); await decideWithMatch('bob','ana');
  // Simula una ficha publicada antes del cumpleaños: mismo perfil y timestamp, edad anterior.
  await env.withSecurityRulesDisabled(admin => updateDoc(doc(admin.firestore(),'discoveryCards/bob'), {age:20}));
  await assertFails(getDoc(cardForBob()));
  const store = context('bob').firestore();
  const before = (await getDoc(doc(store,'users/bob'))).data();
  const changes = {updatedAt:serverTimestamp()};
  const batch = writeBatch(store);
  batch.update(doc(store,'users/bob'), changes);
  batch.set(doc(store,'discoveryCards/bob'), projection({...before,...changes}));
  batch.set(doc(store,'discoveryIndex/bob'), {isActive:true,updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  const card = (await assertSucceeds(getDoc(cardForBob()))).data();
  assert.equal(card.age,21); assert.equal('birthDate' in card,false);
  assert.ok((await getDoc(doc(store,'users/bob'))).data().birthDate.isEqual(before.birthDate));
});

test('Privacidad: republicar elimina birthDate legado sin borrar documentos ni el match', async () => {
  await seedDiscovery();
  const store = context('bob').firestore();
  const user = (await getDoc(doc(store,'users/bob'))).data();
  await env.withSecurityRulesDisabled(admin => setDoc(doc(admin.firestore(),'discoveryCards/bob'),
    {...projection(user),birthDate:user.birthDate,email:user.email}));
  await assertFails(getDoc(cardForBob()));
  await assertSucceeds(setDoc(doc(store,'discoveryCards/bob'),projection(user)));
  const safe = (await assertSucceeds(getDoc(cardForBob()))).data();
  assert.equal('birthDate' in safe,false); assert.equal('email' in safe,false);
});

test('Match: LIKE seguido de PASS no genera coincidencia', async () => {
  await seedDiscovery();
  assert.equal(await decideWithMatch('ana','bob','like'),false);
  assert.equal(await decideWithMatch('bob','ana','pass'),false);
  assert.equal((await getDoc(doc(db(),'matches/ana.bob'))).exists(),false);
});

test('Sin permisos globales ni colección profile_photos en Firestore', async () => {
  for (const path of ['private/secret','profile_photos/ana','chat/example']) {
    await assertFails(setDoc(doc(db(),path),{value:'forbidden'}));
    await assertFails(getDoc(doc(db(),path)));
  }
  await assertFails(setDoc(doc(db(),'interests/new'),{name:'No autorizado',isActive:true}));
  await assertFails(deleteDoc(profileRef()));
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),'interests')));
});

test('Storage valida vacío, subcarpetas y anónimos; PNG/WebP propios permitidos', async () => {
  const store = context('ana').storage();
  await assertFails(uploadBytes(ref(store,'profile_photos/ana/empty'),new Uint8Array(),{contentType:'image/png'}));
  await assertFails(uploadBytes(ref(store,'profile_photos/ana/nested/photo'),new Uint8Array([1]),{contentType:'image/png'}));
  await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(),'profile_photos/ana/anon'),new Uint8Array([1]),{contentType:'image/png'}));
  for (const type of ['png','webp']) {
    const item = ref(store,`profile_photos/ana/qa-${type}`);
    await assertSucceeds(uploadBytes(item,new Uint8Array([1]),{contentType:`image/${type}`}));
    await assertSucceeds(deleteObject(item));
  }
});

// Bloque 5: fixtures exclusivamente en demo-tinder-universitario (emulador).
async function chatMatch() {
  await seedDiscovery();
  await decideWithMatch('ana','bob');
  await decideWithMatch('bob','ana');
}
const chatMessage = (senderId='ana', text='Hola') =>
  ({senderId,text,createdAt:serverTimestamp()});
const messageRef = (store, id='m1', pair='ana.bob') =>
  doc(store,'matches/' + pair + '/messages/' + id);
const chatQuery = store =>
  query(collection(store,'matches/ana.bob/messages'),orderBy('createdAt','desc'),limit(50));

function waitForChat(target, predicate=()=>true) {
  let stop;
  const promise = new Promise((resolve,reject) => {
    const timer = setTimeout(() => {stop();reject(new Error('Listener timeout'));},15000);
    stop = onSnapshot(target, snapshot => {
      if (predicate(snapshot)) {clearTimeout(timer);stop();resolve(snapshot);}
    }, error => {clearTimeout(timer);stop();reject(error);});
  });
  return promise;
}

for (const uid of ['ana','bob']) {
  test('Chat: participante ' + uid + ' puede enviar campos mínimos', async()=>{
    await chatMatch();
    const store=context(uid).firestore();
    await assertSucceeds(setDoc(messageRef(store),chatMessage(uid)));
    const saved=(await getDoc(messageRef(store))).data();
    assert.deepEqual(Object.keys(saved).sort(),['createdAt','senderId','text']);
    assert.equal(saved.senderId,uid);
    assert.ok(saved.createdAt instanceof Timestamp);
  });
}

test('Chat: tercero no puede enviar aunque falsifique senderId',async()=>{
  await chatMatch();
  const store=context('carol').firestore();
  await assertFails(setDoc(messageRef(store),chatMessage('carol')));
  await assertFails(setDoc(messageRef(store),chatMessage('ana')));
});

test('Chat: tercero no puede leer un mensaje',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  await assertFails(getDoc(messageRef(context('carol').firestore())));
});

test('Chat: tercero no puede listar mensajes',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  await assertFails(getDocs(chatQuery(context('carol').firestore())));
});

test('Chat: tercero no puede escuchar mensajes',async()=>{
  await chatMatch();
  await assertFails(waitForChat(chatQuery(context('carol').firestore())));
});

test('Chat: anónimos no pueden enviar, leer ni listar',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  const store=env.unauthenticatedContext().firestore();
  await assertFails(setDoc(messageRef(store,'anon'),chatMessage()));
  await assertFails(getDoc(messageRef(store)));
  await assertFails(getDocs(chatQuery(store)));
});

test('Chat: ambos participantes pueden leer y listar el historial',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  for (const uid of ['ana','bob']) {
    const store=context(uid).firestore();
    await assertSucceeds(getDoc(messageRef(store)));
    assert.equal((await assertSucceeds(getDocs(chatQuery(store)))).size,1);
  }
});

test('Chat: senderId distinto de auth.uid rechazado',async()=>{
  await chatMatch();
  await assertFails(setDoc(messageRef(db()),chatMessage('bob')));
});

test('Chat: texto vacío rechazado',async()=>{
  await chatMatch();
  await assertFails(setDoc(messageRef(db()),chatMessage('ana','')));
});

test('Chat: espacios, saltos de línea vacíos y texto sin trim rechazados',async()=>{
  await chatMatch();
  for (const text of ['   ','\t\n','\u00a0','\u0085','\u1680','\u2000','\u2028','\u2029','\u202f','\u205f','\u3000','\ufeff',' Hola','Hola ','\nHola\n','\u00a0Hola','Hola\u00a0']) {
    await assertFails(setDoc(messageRef(db()),chatMessage('ana',text)));
  }
  await assertSucceeds(setDoc(messageRef(db()),chatMessage('ana','Hola\n¿Cómo estás?')));
});

test('Chat: más de 1000 caracteres rechazado, incluidos Unicode',async()=>{
  await chatMatch();
  for (const text of ['x'.repeat(1001),'😀'.repeat(501)]) {
    await assertFails(setDoc(messageRef(db()),chatMessage('ana',text)));
  }
});

test('Chat: límite exacto de 1000 unidades UTF-16 ASCII y Unicode permitido',async()=>{
  await chatMatch();
  for (const [id,text] of [['ascii','x'.repeat(1000)],['unicode','😀'.repeat(500)],['acentos','á'.repeat(1000)]]) {
    await assertSucceeds(setDoc(messageRef(db(),id),chatMessage('ana',text)));
  }
});

test('Chat: campos extra y datos de perfil rechazados',async()=>{
  await chatMatch();
  for (const extra of [{receiverId:'bob'},{email:'ana@example.com'},{name:'Ana'},
    {photo:'https://example.test/p.jpg'},{extra:true}]) {
    await assertFails(setDoc(messageRef(db()),{...chatMessage(),...extra}));
  }
});

test('Chat: timestamp cliente, nulo o de tipo inválido rechazado',async()=>{
  await chatMatch();
  for (const createdAt of [Timestamp.fromMillis(0),null,'ahora',1]) {
    await assertFails(setDoc(messageRef(db()),{...chatMessage(),createdAt}));
  }
});

test('Chat: todos los campos son obligatorios y text debe ser string',async()=>{
  await chatMatch();
  for (const field of ['senderId','text','createdAt']) {
    const value=chatMessage(); delete value[field];
    await assertFails(setDoc(messageRef(db()),value));
  }
  for (const text of [null,0,true,['hola'],{body:'hola'}]) {
    await assertFails(setDoc(messageRef(db()),chatMessage('ana',text)));
  }
});

test('Chat: UPDATE rechazado incluso para el autor',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  await assertFails(updateDoc(messageRef(db()),{text:'editado'}));
  await assertFails(setDoc(messageRef(db()),chatMessage('ana','sobrescrito')));
});

test('Chat: DELETE rechazado incluso para el autor',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  await assertFails(deleteDoc(messageRef(db())));
});

test('Chat: sin match padre no se puede enviar ni leer mensajes huérfanos',async()=>{
  await assertFails(setDoc(messageRef(db()),chatMessage()));
  await env.withSecurityRulesDisabled(admin=>setDoc(messageRef(admin.firestore()),chatMessage()));
  await assertFails(getDoc(messageRef(db())));
  await assertFails(getDocs(chatQuery(db())));
});

test('Chat: match inactivo bloquea mensajes nuevos y conserva historial privado',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  // Fixture local de estado inactivo legado; HU-15 prueba el cierre completo al final.
  await env.withSecurityRulesDisabled(admin=>
    updateDoc(doc(admin.firestore(),'matches/ana.bob'),{isActive:false}));
  for (const uid of ['ana','bob']) {
    const store=context(uid).firestore();
    await assertFails(setDoc(messageRef(store,'nuevo'),chatMessage(uid)));
    await assertSucceeds(getDoc(messageRef(store)));
    await assertSucceeds(getDocs(chatQuery(store)));
  }
  await assertFails(getDocs(chatQuery(context('carol').firestore())));
});

test('Chat: padre inválido no habilita acceso por contener un UID',async()=>{
  for (const users of [['ana'],['ana','bob','carol'],['bob','ana'],['ana','ana']]) {
    await env.withSecurityRulesDisabled(admin=>
      setDoc(doc(admin.firestore(),'matches/ana.bob'),{...matchData(),users}));
    await assertFails(setDoc(messageRef(db()),chatMessage()));
    await assertFails(getDocs(chatQuery(db())));
  }
});

test('Chat: consulta exige límite de hasta 50 y recupera solo los últimos',async()=>{
  await chatMatch();
  await env.withSecurityRulesDisabled(async admin=>{
    const batch=writeBatch(admin.firestore());
    for (let i=1;i<=55;i++) {
      batch.set(messageRef(admin.firestore(),'m'+i),
        {...chatMessage(),text:'Mensaje '+i,createdAt:Timestamp.fromMillis(i)});
    }
    await batch.commit();
  });
  const store=db();
  await assertFails(getDocs(collection(store,'matches/ana.bob/messages')));
  await assertFails(getDocs(query(collection(store,'matches/ana.bob/messages'),limit(51))));
  const rows=(await assertSucceeds(getDocs(chatQuery(store)))).docs;
  assert.equal(rows.length,50);
  assert.equal(rows[0].data().text,'Mensaje 55');
  assert.equal(rows[49].data().text,'Mensaje 6');
});

test('Chat: listener recibe respuesta de B y una nueva sesión recupera historial',async()=>{
  await chatMatch();
  await assertSucceeds(waitForChat(chatQuery(db()),snapshot=>snapshot.empty));
  const response=waitForChat(chatQuery(db()),snapshot=>
    snapshot.docs.some(row=>row.data().text==='Respuesta en vivo'));
  await setDoc(messageRef(context('bob').firestore()),chatMessage('bob','Respuesta en vivo'));
  await assertSucceeds(response);
  const reopened=env.authenticatedContext('ana',{email:'ana@example.com'}).firestore();
  const rows=await assertSucceeds(getDocs(chatQuery(reopened)));
  assert.equal(rows.docs[0].data().text,'Respuesta en vivo');
});

test('Chat: el listener conserva lectura al desactivar y rechaza nuevas escrituras',async()=>{
  await chatMatch();
  await setDoc(messageRef(db()),chatMessage());
  await env.withSecurityRulesDisabled(admin=>
    updateDoc(doc(admin.firestore(),'matches/ana.bob'),{isActive:false}));
  await assertSucceeds(waitForChat(chatQuery(db()),snapshot=>snapshot.size===1));
  await assertFails(setDoc(messageRef(db(),'posterior'),chatMessage()));
});

const closure = uid => ({isActive:false,closedBy:uid,closedAt:serverTimestamp()});
for (const uid of ['ana','bob']) {
  test('HU15 participante '+uid+' cierra conservando users y createdAt',async()=>{
    await chatMatch();
    const target=doc(context(uid).firestore(),'matches/ana.bob');
    const before=(await getDoc(target)).data();
    await assertSucceeds(updateDoc(target,closure(uid)));
    const saved=(await getDoc(target)).data();
    assert.equal(saved.isActive,false); assert.equal(saved.closedBy,uid);
    assert.ok(saved.closedAt instanceof Timestamp);
    assert.deepEqual(saved.users,before.users); assert.deepEqual(saved.createdAt,before.createdAt);
    assert.deepEqual(Object.keys(saved).sort(),['closedAt','closedBy','createdAt','isActive','users']);
  });
}
for (const uid of ['carol',null]) {
  test('HU15 cierre rechazado para '+uid,async()=>{
    await chatMatch();
    const store=uid ? context(uid).firestore() : env.unauthenticatedContext().firestore();
    await assertFails(updateDoc(doc(store,'matches/ana.bob'),closure(uid??'ana')));
  });
}
for (const [name,changes] of [
  ['true a true',{isActive:true}],
  ['users',{users:['ana','carol']}],
  ['createdAt',{createdAt:Timestamp.fromMillis(0)}],
  ['closedBy ajeno',{closedBy:'bob'}],
  ['closedAt falso',{closedAt:Timestamp.fromMillis(0)}],
  ['campo extra',{extra:true}],
]) {
  test('HU15 rechazo de '+name,async()=>{
    await chatMatch();
    await assertFails(updateDoc(doc(db(),'matches/ana.bob'),{...closure('ana'),...changes}));
    assert.equal((await getDoc(doc(db(),'matches/ana.bob'))).data().isActive,true);
  });
}
for (const [name,changes] of [
  ['reactivar',{isActive:true}],
  ['cerrar nuevamente',closure('bob')],
  ['cambiar autor',{closedBy:'bob'}],
  ['cambiar fecha',{closedAt:serverTimestamp()}],
]) {
  test('HU15 cerrado no permite '+name,async()=>{
    await chatMatch();
    const target=doc(db(),'matches/ana.bob');
    await updateDoc(target,closure('ana'));
    const before=(await getDoc(target)).data();
    await assertFails(updateDoc(target,changes));
    assert.deepEqual((await getDoc(target)).data(),before);
  });
}
test('HU15 DELETE sigue prohibido incluso después de cierre',async()=>{
  await chatMatch(); const target=doc(db(),'matches/ana.bob');
  await updateDoc(target,closure('ana'));
  await assertFails(deleteDoc(target));
});
test('HU15 preserva historial privado y swipes, impide mensajes nuevos de ambos',async()=>{
  await chatMatch(); await setDoc(messageRef(db()),chatMessage());
  const before=(await getDoc(messageRef(db()))).data();
  await updateDoc(doc(db(),'matches/ana.bob'),closure('ana'));
  for (const uid of ['ana','bob']) {
    const store=context(uid).firestore();
    const history=await assertSucceeds(getDocs(chatQuery(store)));
    assert.equal(history.size,1); assert.deepEqual(history.docs[0].data(),before);
    await assertFails(setDoc(messageRef(store,'nuevo'),chatMessage(uid)));
    await assertSucceeds(getDoc(doc(store,'swipes/'+uid+'.'+(uid==='ana'?'bob':'ana'))));
  }
  await assertFails(getDocs(chatQuery(context('carol').firestore())));
});
test('HU15 lote no puede cerrar y enviar mensaje en el mismo commit',async()=>{
  await chatMatch(); const store=db(); const batch=writeBatch(store);
  batch.update(doc(store,'matches/ana.bob'),closure('ana'));
  batch.set(messageRef(store),chatMessage());
  await assertFails(batch.commit());
  assert.equal((await getDoc(doc(store,'matches/ana.bob'))).data().isActive,true);
});
test('HU15 cierre simultáneo produce un único autor y timestamp inmutables',async()=>{
  await chatMatch();
  let arrivals=0,release;
  const ready=new Promise(resolve=>{release=resolve;});
  const close=uid=>{
    const store=context(uid).firestore(); let first=true;
    return runTransaction(store,async tx=>{
      const target=doc(store,'matches/ana.bob');
      const pair=await tx.get(target);
      if(!pair.data().isActive) throw new Error('Ya cerrado');
      if(first){first=false;if(++arrivals===2)release();await ready;}
      tx.update(target,closure(uid));
    });
  };
  const result=await Promise.allSettled([close('ana'),close('bob')]);
  assert.equal(result.filter(value=>value.status==='fulfilled').length,1);
  const saved=(await getDoc(doc(db(),'matches/ana.bob'))).data();
  assert.equal(saved.isActive,false); assert.ok(['ana','bob'].includes(saved.closedBy));
  assert.ok(saved.closedAt instanceof Timestamp); assert.deepEqual(saved.users,['ana','bob']);
  await assertFails(updateDoc(doc(db(),'matches/ana.bob'),closure('ana')));
  assert.deepEqual((await getDoc(doc(db(),'matches/ana.bob'))).data(),saved);
});

// HU-16/HU-17: datos únicamente dentro del emulador demo.
const blockData=(a='ana',b='bob')=>({blockerId:a,blockedId:b,createdAt:serverTimestamp()});
const reportData=(a='ana',b='bob')=>({reporterId:a,reportedId:b,reason:'harassment',details:'',createdAt:serverTimestamp(),status:'pending'});
async function blockPair(a='ana',b='bob') {
  const store=context(a).firestore();
  const commit=()=>runTransaction(store,async tx=>{
    const refBlock=doc(store,`blocks/${a}.${b}`),pair=doc(store,`matches/${matchId(a,b)}`);
    const existing=await tx.get(refBlock),current=await tx.get(pair);
    if(current.exists()&&current.data().isActive) tx.update(pair,closure(a));
    if(!existing.exists()) tx.set(refBlock,blockData(a,b));
    return !existing.exists();
  });
  try{return await commit();}catch(error){if(error.code!=='permission-denied')throw error;return commit();}
}
test('HU16 bloqueo sin match, mínimo direccional y repetición idempotente',async()=>{
  await seedDiscovery(); assert.equal(await blockPair(),true);
  const first=(await getDoc(doc(db(),'blocks/ana.bob'))).data();
  assert.deepEqual(Object.keys(first).sort(),['blockedId','blockerId','createdAt']);
  assert.equal(first.blockerId,'ana');assert.equal(first.blockedId,'bob');
  assert.equal(await blockPair(),false);
  assert.deepEqual((await getDoc(doc(db(),'blocks/ana.bob'))).data(),first);
  assert.equal((await getDoc(doc(context('bob').firestore(),'blocks/bob.ana'))).exists(),false);
});
for(const [name,id,changes] of [
  ['self','ana.ana',{blockedId:'ana'}],['ID incorrecto','otro',{}],
  ['actor falso','bob.ana',{blockerId:'bob',blockedId:'ana'}],
  ['fecha falsa','ana.bob',{createdAt:Timestamp.fromMillis(0)}],
  ['extra','ana.bob',{reason:'privado'}],['destino ausente','ana.nadie',{blockedId:'nadie'}],
]) test('HU16 rechaza '+name,async()=>{
  await seedDiscovery(); await assertFails(setDoc(doc(db(),'blocks/'+id),{...blockData(),...changes}));
});
test('HU16 terceros y anónimos no escriben bloqueo de A',async()=>{
  await seedDiscovery();
  await assertFails(setDoc(doc(context('carol').firestore(),'blocks/ana.bob'),blockData()));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(),'blocks/ana.bob'),blockData()));
});
test('HU16 inmutable y privado: sin update/delete/list ni lectura de destinatario',async()=>{
  await seedDiscovery(); await blockPair();
  const target=doc(db(),'blocks/ana.bob');
  await assertFails(updateDoc(target,{blockedId:'carol'}));
  await assertFails(setDoc(target,blockData()));await assertFails(deleteDoc(target));
  for(const uid of ['ana','bob','carol']) await assertFails(getDocs(collection(context(uid).firestore(),'blocks')));
  for(const uid of ['bob','carol']) await assertFails(getDoc(doc(context(uid).firestore(),'blocks/ana.bob')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'blocks/ana.bob')));
});
test('HU16 lectura de fichas y swipes rechazados en ambas direcciones',async()=>{
  await seedDiscovery(); await blockPair();
  for(const [a,b] of [['ana','bob'],['bob','ana']]) {
    const store=context(a).firestore();
    await assertFails(getDoc(doc(store,'discoveryCards/'+b)));
    for(const type of ['like','pass']) await assertFails(setDoc(doc(store,`swipes/${a}.${b}`),swipe(a,b,type)));
    await assertFails(getDoc(doc(store,'users/'+b)));
  }
});
test('HU16 match nuevo no se crea con dos LIKE antiguos y bloqueo',async()=>{
  await seedMutualLikes(); await blockPair();
  await assertFails(setDoc(doc(db(),'matches/ana.bob'),matchData()));
});
test('HU16 exige cierre atómico, conserva mensajes/swipes y cierre HU15',async()=>{
  await chatMatch();await setDoc(messageRef(db()),chatMessage());
  const original=(await getDoc(doc(db(),'matches/ana.bob'))).data();
  await assertFails(setDoc(doc(db(),'blocks/ana.bob'),blockData()));
  await blockPair();
  const pair=(await getDoc(doc(db(),'matches/ana.bob'))).data();
  assert.equal(pair.isActive,false);assert.equal(pair.closedBy,'ana');assert.ok(pair.closedAt instanceof Timestamp);
  assert.deepEqual(pair.users,original.users);assert.deepEqual(pair.createdAt,original.createdAt);
  for(const [a,b] of [['ana','bob'],['bob','ana']]) {
    const store=context(a).firestore();
    assert.equal((await getDocs(chatQuery(store))).size,1);
    await assertSucceeds(getDoc(doc(store,`swipes/${a}.${b}`)));
    await assertFails(setDoc(messageRef(store,'nuevo'),chatMessage(a)));
  }
});
test('HU16 bloqueo de match ya cerrado conserva el cierre anterior',async()=>{
  await chatMatch();await updateDoc(doc(db(),'matches/ana.bob'),closure('ana'));
  const before=(await getDoc(doc(db(),'matches/ana.bob'))).data();
  await blockPair('bob','ana');assert.deepEqual((await getDoc(doc(db(),'matches/ana.bob'))).data(),before);
});
for(const [a,b] of [['ana','bob'],['bob','ana']]) test('HU16 defensa mensajes con match activo inconsistente y block '+a,async()=>{
  await chatMatch();await setDoc(messageRef(db()),chatMessage());
  await env.withSecurityRulesDisabled(admin=>setDoc(doc(admin.firestore(),`blocks/${a}.${b}`),blockData(a,b)));
  for(const uid of ['ana','bob']) {
    const store=context(uid).firestore();
    await assertFails(setDoc(messageRef(store,'nuevo'),chatMessage(uid)));
    await assertSucceeds(getDocs(chatQuery(store)));
  }
});
test('HU16 lote bloqueo más swipe/match/mensaje no elude validaciones',async()=>{
  await seedDiscovery();let store=db(),batch=writeBatch(store);
  batch.set(doc(store,'blocks/ana.bob'),blockData());batch.set(doc(store,'swipes/ana.bob'),swipe());
  await assertFails(batch.commit());
  await seedMutualLikes();batch=writeBatch(store);
  batch.set(doc(store,'blocks/ana.bob'),blockData());batch.set(doc(store,'matches/ana.bob'),matchData());
  await assertFails(batch.commit());
  await setDoc(doc(store,'matches/ana.bob'),matchData());batch=writeBatch(store);
  batch.set(doc(store,'blocks/ana.bob'),blockData());batch.update(doc(store,'matches/ana.bob'),closure('ana'));
  batch.set(messageRef(store),chatMessage());await assertFails(batch.commit());
});
test('HU16 bloqueos concurrentes conservan un único cierre',async()=>{
  await chatMatch();await Promise.all([blockPair(),blockPair('bob','ana')]);
  const pair=(await getDoc(doc(db(),'matches/ana.bob'))).data();
  assert.equal(pair.isActive,false);assert.ok(['ana','bob'].includes(pair.closedBy));
  assert.ok((await getDoc(doc(db(),'blocks/ana.bob'))).exists());
  assert.ok((await getDoc(doc(context('bob').firestore(),'blocks/bob.ana'))).exists());
});
test('HU17 motivos controlados y detalles opcionales, reporte no bloquea/cierra',async()=>{
  await chatMatch();await setDoc(doc(db(),'reports/ana.bob'),reportData());
  assert.equal((await getDoc(doc(db(),'matches/ana.bob'))).data().isActive,true);
  assert.equal((await getDoc(doc(db(),'blocks/ana.bob'))).exists(),false);
  await env.withSecurityRulesDisabled(async admin=>{
    const data=(await getDoc(doc(admin.firestore(),'reports/ana.bob'))).data();
    assert.deepEqual(Object.keys(data).sort(),['createdAt','details','reason','reportedId','reporterId','status']);
    assert.equal(data.status,'pending');assert.equal(data.details,'');
  });
});
for(const [name,id,changes] of [
  ['self','ana.ana',{reportedId:'ana'}],['reporter falso','bob.ana',{reporterId:'bob',reportedId:'ana'}],
  ['ID aleatorio','aleatorio',{}],['motivo','ana.bob',{reason:'libre'}],
  ['detalles largos','ana.bob',{details:'x'.repeat(501)}],['tipo detalles','ana.bob',{details:null}],
  ['status','ana.bob',{status:'resolved'}],['fecha','ana.bob',{createdAt:Timestamp.fromMillis(0)}],
  ['extra','ana.bob',{email:'privado@example.com'}],['destino ausente','ana.nadie',{reportedId:'nadie'}],
]) test('HU17 rechaza '+name,async()=>{
  await seedDiscovery();await assertFails(setDoc(doc(db(),'reports/'+id),{...reportData(),...changes}));
});
test('HU17 no lectura ni mutación incluso autor; duplicado y anónimo rechazados',async()=>{
  await seedDiscovery();await setDoc(doc(db(),'reports/ana.bob'),reportData());
  for(const uid of ['ana','bob','carol']) {
    const store=context(uid).firestore(),target=doc(store,'reports/ana.bob');
    await assertFails(getDoc(target));await assertFails(getDocs(collection(store,'reports')));
    await assertFails(updateDoc(target,{details:'cambio'}));await assertFails(deleteDoc(target));
  }
  await assertFails(setDoc(doc(db(),'reports/ana.bob'),reportData()));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(),'reports/bob.ana'),reportData('bob','ana')));
});
test('HU17 reportar y bloquear separados, reporte posterior a bloqueo permitido',async()=>{
  await seedDiscovery();await blockPair();
  await env.withSecurityRulesDisabled(async admin=>assert.equal((await getDocs(collection(admin.firestore(),'reports'))).size,0));
  await assertSucceeds(setDoc(doc(db(),'reports/ana.bob'),reportData()));
  await assertSucceeds(setDoc(doc(context('bob').firestore(),'reports/bob.ana'),{...reportData('bob','ana'),reason:'other',details:'x'.repeat(500)}));
});


test('HU17 acepta todos los motivos del catálogo y límite de detalles',async()=>{
  await seedDiscovery();
  for(const reason of ['fake_profile','inappropriate_content','harassment','spam','other']) {
    await assertSucceeds(setDoc(doc(db(),'reports/ana.bob'),{...reportData(),reason,details:'x'.repeat(500)}));
    await env.withSecurityRulesDisabled(admin=>deleteDoc(doc(admin.firestore(),'reports/ana.bob')));
  }
});
test('HU16 controles de bloqueo conservan presupuesto de Rules con carreras distintas',async()=>{
  await seedDiscovery();
  await env.withSecurityRulesDisabled(async admin=>{
    const store=admin.firestore();
    await setDoc(doc(store,'careers/medicina'),{name:'Medicina',isActive:true});
    await updateDoc(doc(store,'users/bob'),{careerId:'medicina'});
    const data=(await getDoc(doc(store,'users/bob'))).data();
    await setDoc(doc(store,'discoveryCards/bob'),projection(data));
  });
  await assertSucceeds(decideWithMatch('ana','bob'));
  await assertSucceeds(decideWithMatch('bob','ana'));
});
