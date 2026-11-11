import {Firestore} from '@google-cloud/firestore';
import {OAuth2Client} from 'google-auth-library';
import {requireShowcaseProject} from './showcase-guard.mjs';
// Operador de fixtures: exclusivamente el proyecto aislado, nunca producción/emuladores.
import {initializeApp,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore,Timestamp,FieldValue} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {readFileSync,writeFileSync,existsSync,mkdirSync} from 'node:fs';
import {randomBytes,createHash} from 'node:crypto';
import sharp from 'sharp';
import {sessionToken} from './read-client.mjs';
import {saveEncrypted,loadEncrypted,privateDirectory} from './private-backup.mjs';
import {sealPrivateObject} from '../backend/private-object.mjs';
import {project,bucket,root,state,call} from './showcase-infrastructure.mjs';
requireShowcaseProject(project,bucket);
if(!process.argv.includes('--authorized-isolated-demo')||project!=='tinder-universitario-showcase'||state().project!==project||Object.keys(process.env).some(k=>k.endsWith('_EMULATOR_HOST')&&process.env[k]))throw Error('isolated-project-required');
const app=initializeApp({projectId:project,storageBucket:bucket,credential:{getAccessToken:async()=>({access_token:await sessionToken(),expires_in:3500})}},'isolated-demo-seed');
const oauth=new OAuth2Client();oauth.setCredentials({access_token:await sessionToken()});
const auth=getAuth(app),db=new Firestore({projectId:project,preferRest:true,authClient:oauth}),storage=fixtureStorage();

function fixtureStorage(){return {file:path=>{
 const url='https://storage.googleapis.com/storage/v1/b/'+bucket+'/o/'+encodeURIComponent(path);
 return {exists:async()=>[(await call(url,'GET',null,{missing:true})).status!==404],getMetadata:async()=>[(await call(url)).data],setMetadata:async data=>(await call(url,'PATCH',data)).data,save:async bytes=>{
 const boundary='showcase_fixture_upload';const metadata={name:path,contentType:'image/png',cacheControl:'private, no-store',metadata:{}};
 const body=Buffer.concat([Buffer.from('--'+boundary+'\r\nContent-Type: application/json\r\n\r\n'+JSON.stringify(metadata)+'\r\n--'+boundary+'\r\nContent-Type: image/png\r\n\r\n'),bytes,Buffer.from('\r\n--'+boundary+'--')]);
 const response=await fetch('https://storage.googleapis.com/upload/storage/v1/b/'+bucket+'/o?uploadType=multipart&ifGenerationMatch=0',{method:'POST',headers:{Authorization:'Bearer '+await sessionToken(),'Content-Type':'multipart/related; boundary='+boundary},body});if(!response.ok)throw Error('private-fixture-upload-'+response.status);
 }};
 }};}

const rows=[['root','superadmin','Superadmin Demo','masculino','sistemas','#5533aa'],['admin','admin','Admin Demo','femenino','derecho','#994499'],['ana','user','Ana Demo','femenino','sistemas','#df6887'],['bob','user','Bob Demo','masculino','sistemas','#4477cc'],['carla','user','Carla Demo','femenino','medicina','#449977'],['diego','user','Diego Demo','masculino','medicina','#cc8833'],['pendiente','user','Estudiante Pendiente','femenino','sistemas','#8877bb'],['rechazo','user','Estudiante Rechazado','masculino','derecho','#aa6655'],['revision','user','Revisión Automática Demo','femenino','sistemas','#558899']].map(([id,role,name,gender,career,color])=>({uid:'showcase_'+id,email:id+'@demo.test',role,name,gender,career,color,status:['pendiente','rechazo','revision'].includes(id)?'pending':'approved'}));
try{
 const marker=db.doc('demoOperations/seedV1');if((await marker.get()).exists){console.log(JSON.stringify({seedAlreadyComplete:true}));process.exitCode=0;}else{
 const existingProfiles=await db.collection('users').get();if(existingProfiles.docs.some(d=>!rows.some(r=>r.uid===d.id)))throw Error('unexpected-demo-account');
 privateDirectory(root+'/private');const credsFile=root+'/private/accounts.dpapi';let credentials;if(existsSync(credsFile))credentials=loadEncrypted(credsFile);else{credentials={project,password:'TUdemo-'+randomBytes(10).toString('hex'),accounts:rows.map(r=>({uid:r.uid,email:r.email,role:r.role}))};saveEncrypted(credsFile,credentials);}
 mkdirSync(root+'/fixtures',{recursive:true});
 const card=await sharp(Buffer.from('<svg width="900" height="560" xmlns="http://www.w3.org/2000/svg"><rect width="900" height="560" fill="#f2edf9"/><text x="45" y="90" font-family="sans-serif" font-size="54" fill="#6232a1">CARNET FICTICIO — DEMO</text><text x="45" y="180" font-family="sans-serif" font-size="38">Univalle · Sede Cochabamba</text><text x="45" y="260" font-family="sans-serif" font-size="38">Estudiante Demo · Gestión 2026</text><text x="45" y="370" font-family="sans-serif" font-size="52" fill="#b12840">SIN VALIDEZ · NO ES UN CARNET REAL</text><text x="45" y="470" font-family="sans-serif" font-size="30">Solo pruebas ficticias de flujo y permisos</text></svg>')).png().toBuffer();writeFileSync(root+'/fixtures/carnet-ficticio.png',card);
 for(const r of rows){if((await db.doc('users/'+r.uid).get()).exists){if(!(await db.doc('profilePhotoAssets/'+r.uid+'.main').get()).exists)throw Error('incomplete-existing-fixture');continue;}try{const existing=await auth.getUser(r.uid);if(existing.email!==r.email)throw Error('fixture-identity-conflict');}catch(e){if(e.code!=='auth/user-not-found')throw e;await auth.createUser({uid:r.uid,email:r.email,password:credentials.password,emailVerified:true,displayName:r.name});}
 const bytes=await sharp(Buffer.from(`<svg width="480" height="640" xmlns="http://www.w3.org/2000/svg"><rect width="480" height="640" fill="${r.color}"/><circle cx="240" cy="205" r="98" fill="#fafafa"/><ellipse cx="240" cy="490" rx="175" ry="165" fill="#fafafa"/><text x="30" y="610" font-family="sans-serif" font-size="34" fill="#242424">${r.name}</text></svg>`)).png().toBuffer();
 const path='profile_photos/'+r.uid+'/main',f=storage.file(path);const [exists]=await f.exists();if(!exists)await f.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:'image/png',cacheControl:'private, no-store'}});else{const [m]=await f.getMetadata();if(m.md5Hash!==createHash('md5').update(bytes).digest('base64'))throw Error('fixture-object-content-conflict');}await sealPrivateObject(f);const [meta]=await f.getMetadata();if(meta.metadata?.firebaseStorageDownloadTokens)throw Error('fixture-photo-not-private');
 const now=Timestamp.now(),birth=Timestamp.fromDate(new Date('2001-05-10T00:00:00Z')),age=new Date().getUTCFullYear()-2001-(new Date().getUTCMonth()<4||(new Date().getUTCMonth()===4&&new Date().getUTCDate()<10)?1:0),visible=r.role==='user';
 const profile={firstName:r.name,lastName:'Ficticio',email:r.email,birthDate:birth,gender:r.gender,description:'Perfil ficticio del entorno DEMO ONLINE. Sin datos personales reales.',careerId:r.career,photoUrls:[path],mainPhotoUrl:path,interestIds:['musica','tecnologia'],role:'user',isActive:visible,datingAllowed:r.status==='approved',createdAt:now,updatedAt:now};
 const cardData={age};for(const k of ['firstName','gender','description','careerId','mainPhotoUrl','interestIds','isActive','updatedAt'])cardData[k]=profile[k];
 const batch=db.batch();batch.create(db.doc('users/'+r.uid),profile);batch.create(db.doc('accountAccess/'+r.uid),{role:r.role,verificationStatus:r.status,suspended:false,latestRequestId:null,createdAt:now,updatedAt:now});batch.create(db.doc('preferences/'+r.uid),{minAge:18,maxAge:40,preferredGender:'ambos',careerIds:[],updatedAt:now});batch.create(db.doc('discoveryCards/'+r.uid),cardData);batch.create(db.doc('matchProfiles/'+r.uid),{...cardData,photoUrls:[path]});batch.create(db.doc('discoveryIndex/'+r.uid),{isActive:visible,updatedAt:now});batch.create(db.doc('profilePhotoManifests/'+r.uid),{paths:[path]});batch.create(db.doc('profilePhotoAssets/'+r.uid+'.main'),{uid:r.uid,path,mime:'image/png',size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),generation:meta.generation,state:'published'});await batch.commit();writeFileSync(root+'/fixtures/'+r.uid+'.png',bytes);
 }
 const catalogs=JSON.parse(readFileSync('tool/catalogs.seed.json','utf8').replace(/^\uFEFF/,'')),batch=db.batch();for(const [collection,items]of Object.entries(catalogs))for(const [id,v]of Object.entries(items))batch.create(db.doc(collection+'/'+id),v);batch.create(db.doc('administration/roles'),{superadminIds:['showcase_root'],updatedAt:FieldValue.serverTimestamp()});batch.create(db.doc('administrativeAudit/fictional_fixture_bootstrap'),{actorId:'authorized_demo_operator',targetId:'showcase_root',action:'fictional_fixture_bootstrap',reasonCode:'isolated_synthetic_demo_only',at:FieldValue.serverTimestamp(),independentUniversityReview:false});batch.create(marker,{project,syntheticOnly:true,accounts:rows.length,at:FieldValue.serverTimestamp()});await batch.commit();console.log(JSON.stringify({project,fictionalAccounts:rows.length,privatePhotos:rows.length,roles:['user','admin','superadmin'],credentialsEncrypted:true}));
 }
}finally{await db.terminate();await deleteApp(app);}
