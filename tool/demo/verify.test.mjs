import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment,assertFails} from '@firebase/rules-unit-testing';
import {doc,getDoc,updateDoc,serverTimestamp} from 'firebase/firestore';
import {ref,getMetadata} from 'firebase/storage';
const project='demo-tinder-universitario',bucket=project+'.appspot.com';
let env;
before(async()=>{env=await initializeTestEnvironment({projectId:project,
  firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});});
after(async()=>{await env?.cleanup();});
test('SDK, opciones demo y reglas: no se importan ni habilitan configuraciones reales',async()=>{
  const entry=await readFile(new URL('../../lib/main_demo.dart',import.meta.url),'utf8');
  assert.equal(/import\s+['"].*(?:firebase_options|\/main\.dart|['"]main\.dart)/.test(entry),false);
  assert.ok(entry.includes("projectId: 'demo-tinder-universitario'"));
  const source=(await readFile(new URL('../../firestore.rules',import.meta.url),'utf8')).replace(/\r\n/g,'\n');
  const demo=await readFile(new URL('./firestore.demo.rules',import.meta.url),'utf8');
  const mask=text=>text.replace(/    function ownPhoto\(url, uid\) \{[\s\S]*?\n    \}\n/,'PHOTO_RULE\n');
  assert.equal(source,demo.replace(/\r\n/g,'\n'));
  assert.equal(demo.includes('https://firebasestorage'),false);
});
test('Servidor restringe conexiones y listeners a loopback',async()=>{
  const response=await fetch('http://127.0.0.1:7357/');
  assert.equal(response.status,200);
  const csp=response.headers.get('content-security-policy');
  assert.ok(csp.includes("connect-src 'self' blob: http://127.0.0.1:9099 http://127.0.0.1:8088 http://127.0.0.1:9198;"));
  assert.ok(!csp.includes('connect-src *'));
  const hub=await fetch('http://127.0.0.1:4400/emulators').then(r=>r.json());
  for(const [name,port] of [['auth',9099],['firestore',8088],['storage',9198]]) {
    assert.equal(hub[name].host,'127.0.0.1');assert.equal(hub[name].port,port);
    assert.ok(hub[name].listen.every(l=>l.address==='127.0.0.1'));
  }
});
for(const [uid,email,other] of [['manual_ana','ana.manual@demo.test','manual_bob'],['manual_bob','bob.manual@demo.test','manual_ana']]) {
  test(`Cuenta, perfil, match y foto de ${uid} verificados sin alterar fixtures`,async()=>{
    const loginResponse=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-tinder-universitario-key',{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password:'DemoTinder2026!',returnSecureToken:true})});
    assert.equal(loginResponse.status,200);const login=await loginResponse.json();assert.equal(login.localId,uid);
    const context=env.authenticatedContext(uid,{email,email_verified:true});const db=context.firestore();
    const profile=(await getDoc(doc(db,'users',uid))).data();
    assert.equal(profile.isActive,true);assert.equal(profile.gender,uid==='manual_ana'?'femenino':'masculino');
    assert.ok(profile.firstName&&profile.lastName&&profile.birthDate&&profile.careerId);
    // Las pruebas manuales pueden cambiar la principal y la galería. Validar el
    // contrato privado actual, sin exigir que permanezcan las fotos del seed.
    assert.ok(Array.isArray(profile.photoUrls));
    assert.ok(profile.photoUrls.length>=1&&profile.photoUrls.length<=6);
    assert.equal(new Set(profile.photoUrls).size,profile.photoUrls.length);
    assert.ok(profile.photoUrls.includes(profile.mainPhotoUrl));
    for(const path of profile.photoUrls) {
      assert.match(path,new RegExp(`^profile_photos/${uid}/[A-Za-z0-9_-]{1,128}$`));
      await assertFails(getMetadata(ref(context.storage(bucket),path)));
      const image=await fetch('http://127.0.0.1:7357/__demo/api/profile/media/'+encodeURIComponent(path),{headers:{Authorization:'Bearer '+login.idToken}});
      assert.equal(image.status,200);assert.match(image.headers.get('content-type'),/^image\//);
      assert.equal(image.headers.get('cache-control'),'no-store');
      assert.ok((await image.arrayBuffer()).byteLength>0);
    }
    assert.equal((await getDoc(doc(db,'matches/manual_ana.manual_bob'))).data().isActive,true);
    assert.equal((await getDoc(doc(db,'discoveryCards',other))).exists(),true);
    await assertFails(getMetadata(ref(context.storage(bucket),profile.mainPhotoUrl)));
    const photo=await fetch('http://127.0.0.1:7357/__demo/api/profile/media/'+encodeURIComponent(profile.mainPhotoUrl),{headers:{Authorization:'Bearer '+login.idToken}});assert.equal(photo.status,200);assert.equal(photo.headers.get('cache-control'),'no-store');await photo.body.cancel();
    const real=`https://firebasestorage.googleapis.com/v0/b/tinder-universitario.firebasestorage.app/o/profile_photos%2F${uid}%2Fmain?alt=media&token=abc-123`;
    await assertFails(updateDoc(doc(db,'users',uid),{photoUrls:[real],mainPhotoUrl:real,updatedAt:serverTimestamp()}));
  });
}
test('Tercero y anónimo no acceden al perfil ni al match de prueba',async()=>{
  for(const context of [env.authenticatedContext('manual_mallory'),env.unauthenticatedContext()]) {
    await assertFails(getDoc(doc(context.firestore(),'users/manual_ana')));
    await assertFails(getDoc(doc(context.firestore(),'matches/manual_ana.manual_bob')));
    await assertFails(getMetadata(ref(context.storage(bucket),'profile_photos/manual_ana/main')));
  }
});
