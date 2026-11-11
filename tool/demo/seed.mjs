import {readFile,writeFile} from 'node:fs/promises';
import {deflateSync} from 'node:zlib';
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,setDoc,Timestamp,getDoc,updateDoc,serverTimestamp} from 'firebase/firestore';
import {ref,getMetadata} from 'firebase/storage';
import {getStorage} from 'firebase-admin/storage';
import {getFirestore} from 'firebase-admin/firestore';
import {createHash} from 'node:crypto';
import {sealPrivateObject} from '../backend/private-object.mjs';
if(process.argv[2]!=='--new-empty-demo')throw new Error('Solo --new-empty-demo; para conservar datos, restaurar exportación Fase 5.');
const project='demo-tinder-universitario',bucket=project+'.appspot.com';
// Solo endpoints fijos de loopback. No ADC, login CLI ni llamadas al proyecto real.
process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8088';
process.env.GCLOUD_PROJECT=project;
process.env.GOOGLE_CLOUD_PROJECT=project;
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
const hub=await fetch('http://127.0.0.1:4400/emulators').then(r=>r.json());
for(const [service,port] of [['auth',9099],['firestore',8088],['storage',9198]]) {
  if(hub[service]?.port!==port || hub[service]?.host!=='127.0.0.1') throw new Error(`Emulador ${service} no verificado.`);
}
const app=initializeApp({projectId:project,storageBucket:bucket});
const auth=getAuth(app);
if(!(await getFirestore(app).collection('users').limit(1).get()).empty)throw new Error('El demo contiene datos: seed prohibido.');
process.env.FIREBASE_STORAGE_EMULATOR_HOST='127.0.0.1:9198';
const users=[{uid:'manual_ana',email:'ana.manual@demo.test',firstName:'Ana Demo',gender:'femenino',color:[238,111,125],birth:'2001-01-10'},
  {uid:'manual_bob',email:'bob.manual@demo.test',firstName:'Bob Demo',gender:'masculino',color:[88,138,208],birth:'2000-02-15'},
  {uid:'manual_carla',email:'carla.manual@demo.test',firstName:'Carla Demo',gender:'femenino',color:[82,170,118],birth:'2002-03-20'}];
const password='DemoTinder2026!';
function crc32(b){let c=0xffffffff;for(const v of b){c^=v;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type);const out=Buffer.alloc(data.length+12);out.writeUInt32BE(data.length);t.copy(out,4);data.copy(out,8);out.writeUInt32BE(crc32(Buffer.concat([t,data])),8+data.length);return out;}
function avatar(color){const size=160,raw=Buffer.alloc(size*(size*3+1));for(let y=0;y<size;y++){for(let x=0;x<size;x++){
  const silhouette=(x-80)**2+(y-52)**2<25**2 || (y>=92 && ((x-80)/52)**2+((y-145)/55)**2<1);
  const pixel=silhouette?[248,248,248]:color; const p=y*(size*3+1)+1+x*3; for(let i=0;i<3;i++)raw[p+i]=pixel[i];
}}const header=Buffer.alloc(13);header.writeUInt32BE(size,0);header.writeUInt32BE(size,4);header[8]=8;header[9]=2;
return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
const env=await initializeTestEnvironment({projectId:project,
  firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});
try {
  for(const u of users) {
    try {const existing=await auth.getUser(u.uid);if(existing.email!==u.email)throw new Error('UID reservado tiene otra cuenta.');}
    catch(error){if(error.code!=='auth/user-not-found')throw error;await auth.createUser({uid:u.uid,email:u.email,password,emailVerified:true,displayName:u.firstName});}
  }
  await env.withSecurityRulesDisabled(async admin=>{
    const db=admin.firestore();
    const storage=admin.storage(bucket);
    const catalogs=JSON.parse((await readFile(new URL('../catalogs.seed.json',import.meta.url),'utf8')).replace(/^\uFEFF/,''));
    for(const [collection,items] of Object.entries(catalogs))for(const [id,value]of Object.entries(items))await setDoc(doc(db,collection,id),value);
    const now=Timestamp.now(),today=new Date();
    for(const u of users){
      const bytes=avatar(u.color),photo=`profile_photos/${u.uid}/main`,file=getStorage(app).bucket(bucket).file(photo);
      await file.save(bytes,{resumable:false,metadata:{contentType:'image/png',cacheControl:'private, no-store'}});await sealPrivateObject(file);const [meta]=await file.getMetadata();
      await setDoc(doc(db,'profilePhotoManifests',u.uid),{paths:[photo]});
      await setDoc(doc(db,'profilePhotoAssets',u.uid+'.main'),{uid:u.uid,path:photo,mime:'image/png',size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),generation:meta.generation,state:'published'});
      const birth=Timestamp.fromDate(new Date(u.birth+'T00:00:00Z'));
      const data={firstName:u.firstName,lastName:'Pruebas',email:u.email,birthDate:birth,gender:u.gender,
        description:'Perfil sintético exclusivo para pruebas locales.',careerId:'sistemas',photoUrls:[photo],mainPhotoUrl:photo,
        interestIds:['musica','tecnologia'],role:'user',isActive:true,createdAt:now,updatedAt:now};
      await setDoc(doc(db,'users',u.uid),{...data,datingAllowed:true});
      await setDoc(doc(db,'accountAccess',u.uid),{role:'user',verificationStatus:'approved',suspended:false,latestRequestId:null,createdAt:now,updatedAt:now});
      const date=birth.toDate();const age=today.getUTCFullYear()-date.getUTCFullYear()-
        (today.getUTCMonth()<date.getUTCMonth()||(today.getUTCMonth()===date.getUTCMonth()&&today.getUTCDate()<date.getUTCDate())?1:0);
      const card={age};for(const field of ['firstName','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'])card[field]=data[field];
      await setDoc(doc(db,'discoveryCards',u.uid),card);
      await setDoc(doc(db,'matchProfiles',u.uid),{...card,photoUrls:data.photoUrls});
      await setDoc(doc(db,'discoveryIndex',u.uid),{isActive:true,updatedAt:now});
      await setDoc(doc(db,'preferences',u.uid),{minAge:18,maxAge:40,preferredGender:'ambos',updatedAt:now});
      await writeFile(new URL(`../../build/demo-${u.uid}.png`,import.meta.url),bytes);
    }
    for(const [from,to] of [['manual_ana','manual_bob'],['manual_bob','manual_ana']])await setDoc(doc(db,`swipes/${from}.${to}`),{fromUserId:from,toUserId:to,type:'like',createdAt:now});
    await setDoc(doc(db,'matches/manual_ana.manual_bob'),{users:['manual_ana','manual_bob'],isActive:true,createdAt:now});
  });
  // Verificar credenciales reales del emulador y acceso con las reglas activas.
  const verified=[];
  for(const u of users){
    const response=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-tinder-universitario-key',{
      method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:u.email,password,returnSecureToken:true})});
    if(!response.ok)throw new Error(`Login local falló para ${u.uid}`);
    const login=await response.json();if(login.localId!==u.uid)throw new Error('UID incorrecto.');
    const ctx=env.authenticatedContext(u.uid,{email:u.email,email_verified:true});const db=ctx.firestore();
    const own=await getDoc(doc(db,'users',u.uid));
    if(own.data()?.isActive!==true||own.data()?.photoUrls?.length!==1)throw new Error('Perfil incompleto.');
    if(u.uid!=='manual_carla') {
      const match=await getDoc(doc(db,'matches/manual_ana.manual_bob'));if(match.data()?.isActive!==true)throw new Error('Match inactivo.');
    }
    const other=users.find(other=>other.uid!==u.uid);
    if(!(await getDoc(doc(db,'discoveryCards',other.uid))).exists())throw new Error('Ficha del match inaccesible.');
    await updateDoc(doc(db,'users',u.uid),{description:own.data().description,updatedAt:serverTimestamp()});
    // Actualizar proyección con el nuevo timestamp para conservar lectura de tarjetas.
    const fresh=(await getDoc(doc(db,'users',u.uid))).data();
    await env.withSecurityRulesDisabled(async admin=>{
      await updateDoc(doc(admin.firestore(),'discoveryCards',u.uid),{updatedAt:fresh.updatedAt});
      await updateDoc(doc(admin.firestore(),'discoveryIndex',u.uid),{updatedAt:fresh.updatedAt});
    });
    const photo=ref(ctx.storage(bucket),`profile_photos/${u.uid}/main`);
    if((await getStorage(app).bucket(bucket).file(`profile_photos/${u.uid}/main`).getMetadata())[0].contentType!=='image/png')throw new Error('Foto incorrecta.');
    verified.push({uid:u.uid,email:u.email,verifiedEmail:true,completeProfile:true,activeMatch:u.uid!=='manual_carla'});
  }
  await writeFile(new URL('../../audit-demo-seed.json',import.meta.url),JSON.stringify({project,bucket,users:verified,matchId:'manual_ana.manual_bob'},null,2));
  console.log(JSON.stringify({project,bucket,users:verified,matchId:'manual_ana.manual_bob'},null,2));
} finally {await env.cleanup();await deleteApp(app);}
