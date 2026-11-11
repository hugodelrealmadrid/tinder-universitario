import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {Timestamp} from 'firebase-admin/firestore';
import sharp from 'sharp';
import {emulatorServices} from '../backend/emulator.mjs';
import {VerificationBackend} from '../backend/verification.mjs';

const mode = process.argv[2];
if (!['--seed', '--remove'].includes(mode) ||
    execFileSync('git', ['branch', '--show-current'], {encoding:'utf8'}).trim() !== 'codex/ligo') {
  throw Error('Uso en codex/ligo: node tool/ligo/seed-dossier.mjs --seed | --remove');
}
const project = 'demo-ligo-staging';
const services = await emulatorServices(project, {auth:9399, firestore:8288, storage:9498, hub:4420});
const {db, auth, bucket} = services;
const backend = new VerificationBackend(services);
const password = 'Ligo-staging-2026!';
const moderator = 'ligo_admin';
const marker = db.doc('_stagingFixtures/dossier-v1');
const base = 'http://127.0.0.1:8288/v1/projects/'+project+'/databases/(default)/documents';
const rows = [
  ['ligo_dossier_alma','Alma','Ríos','femenino','2003-04-19','a','Me gusta la fotografía urbana y leer ciencia ficción.',true],
  ['ligo_dossier_bruno','Bruno','Vega','masculino','2002-07-22','b','Dibujo, disfruto el cine y busco buenas conversaciones.',true],
  ['ligo_dossier_celia','Celia','Luna','femenino','2004-02-10','b','Leo novelas y siempre tengo un proyecto creativo.',true],
  ['ligo_dossier_dario','Darío','Mora','masculino','2003-11-02','a','Me gustan la programación y los paseos en bici.',false],
].map(([uid,firstName,lastName,gender,birth,catalog,description,approved])=>({
  uid,firstName,lastName,gender,birth,catalog,description,approved,email:uid.split('_').at(-1)+'.'+lastName.normalize('NFD').replace(/\p{Diacritic}/gu,'').toLowerCase()+'@ligo.test',
  photo:'profile_photos/'+uid+'/dossier_portrait',
}));
const [alma,bruno,celia] = rows;
const idFor = (a,b) => a.uid+'.'+b.uid;
const pairs = [[alma,bruno,['¿Vamos a la feria de libros el sábado?','¡Sí! Nos vemos en la entrada.','Perfecto, llevo mi cámara.']],
  [bruno,celia,['¿Viste la exposición de ilustración?','Sí, me encantó la sala de grabados.']]];
const reportId = idFor(celia,alma);
const refs = rows.flatMap(row=>[
  ...['users','accountAccess','discoveryCards','discoveryIndex','matchProfiles','preferences','profilePhotoManifests'].map(col=>col+'/'+row.uid),
  'profilePhotoAssets/'+row.uid+'.dossier_portrait',
]);
for (const [a,b,messages] of pairs) {
  const pair = idFor(a,b);
  refs.push('swipes/'+pair,'swipes/'+idFor(b,a),'matches/'+pair,
    ...messages.map((_,i)=>'matches/'+pair+'/messages/dossier_'+i));
}
refs.push('reports/'+reportId);

async function call(url, options = {}) {
  const res = await fetch(url, {...options, signal:AbortSignal.timeout(15000)});
  if (!res.ok) throw Error(new URL(url).pathname+' HTTP '+res.status+' '+(await res.text()).slice(0,800));
  return res;
}
const json = {'Content-Type':'application/json'};
async function login(email) {
  const res = await call('http://127.0.0.1:9399/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo', {
    method:'POST',headers:json,body:JSON.stringify({email,password,returnSecureToken:true}),
  });
  return (await res.json()).idToken;
}
const authenticated = (token, extra={}) => ({Authorization:'Bearer '+token,...extra});
function field(value) {
  if (typeof value==='string') return {stringValue:value};
  if (typeof value==='boolean') return {booleanValue:value};
  if (Array.isArray(value)) return {arrayValue:{values:value.map(field)}};
  throw Error('Tipo de fixture no válido');
}
async function write(token, records) {
  await call(base+':commit',{method:'POST',headers:authenticated(token,json),body:JSON.stringify({
    writes:records.map(([path,data,stamp,create=true])=>({
      update:{name:base.split('/v1/')[1]+'/'+path,fields:Object.fromEntries(Object.entries(data).map(([key,val])=>[key,field(val)]))},
      currentDocument:{exists:!create}, ...(create?{}:{updateMask:{fieldPaths:[]}}),
      updateTransforms:[{fieldPath:stamp,setToServerValue:'REQUEST_TIME'}],
    })),
  })});
}
async function existingUser(uid) {
  return auth.getUser(uid).catch(error=>{if(error.code==='auth/user-not-found')return null;throw error;});
}
const owned = new Set(rows.map(r=>r.uid));
async function related(collection, fields) {
  const docs = new Map();
  for (const uid of owned) for (const [key,op] of fields) {
    const snapshot = await db.collection(collection).where(key,op,uid).get();
    for (const doc of snapshot.docs) docs.set(doc.ref.path,doc);
  }
  return [...docs.values()];
}

async function reserve() {
  const state = (await marker.get()).data();
  if (state) {
    if (state.version!==1) throw Error('Marcador desconocido.');
    return state;
  }
  const snapshots = await db.getAll(...refs.map(path=>db.doc(path)));
  if (snapshots.some(s=>s.exists) || (await Promise.all(rows.map(r=>existingUser(r.uid)))).some(Boolean)) {
    throw Error('Colisión con datos existentes. No se modificó ningún registro.');
  }
  for (const row of rows) {
    const [photos] = await bucket.getFiles({prefix:'profile_photos/'+row.uid+'/'});
    const [cards] = await bucket.getFiles({prefix:'university_cards/'+row.uid+'/'});
    if (photos.length || cards.length) throw Error('Colisión en Storage.');
  }
  await marker.create({version:1, startedAt:Timestamp.now()});
  return {};
}

async function seed() {
  await reserve();
  const tokens = new Map();
  for (const row of rows) {
    const previous = await existingUser(row.uid);
    if (previous && previous.email!==row.email) throw Error('La cuenta reservada cambió.');
    if (!previous) await auth.createUser({uid:row.uid,email:row.email,emailVerified:true,password});
    tokens.set(row.uid,await login(row.email));
    const profileRef = db.doc('users/'+row.uid);
    const stamp = Timestamp.now();
    const profile = {
      firstName:row.firstName,lastName:row.lastName,email:row.email,
      birthDate:Timestamp.fromDate(new Date(row.birth)),gender:row.gender,description:row.description,
      careerId:'career_'+row.catalog,universityId:'uni_'+row.catalog,interestIds:['fixture_interest'],
      photoUrls:[],mainPhotoUrl:null,role:'user',isActive:false,datingAllowed:false,createdAt:stamp,updatedAt:stamp,
    };
    if (!(await profileRef.get()).exists) await profileRef.create(profile);
    await backend.provision(row.uid);
    let account = (await backend.account(row.uid).get()).data();
    if (!account.latestRequestId || account.verificationStatus==='pending') {
      const {requestId} = await backend.begin(row.uid);
      const request = (await backend.request(requestId).get()).data();
      if (request.documentStage==='awaiting_upload') {
        const card = await sharp(Buffer.from(`<svg width="480" height="250" xmlns="http://www.w3.org/2000/svg"><rect width="480" height="250" fill="#30234a"/><text x="30" y="80" fill="white" font-size="28">CARNET FICTICIO · STAGING</text><text x="30" y="145" fill="white" font-size="25">${row.firstName} ${row.lastName}</text></svg>`)).png().toBuffer();
        await backend.upload(row.uid,requestId,card);
      }
      if (row.approved) await backend.decide(moderator,requestId,'approved','verified');
      account = (await backend.account(row.uid).get()).data();
    }
    if (account.verificationStatus!==(row.approved?'approved':'pending')) throw Error('La acreditación del fixture cambió.');
    if (!row.approved) continue;
    const assetRef = db.doc('profilePhotoAssets/'+row.uid+'.dossier_portrait');
    if (!(await assetRef.get()).exists) {
      const file = row===bruno?'bob-ficticio.png':'ana-ficticia.png';
      const source = await readFile(new URL('../../staging/fixtures/'+file,import.meta.url));
      const bytes = row===celia ? await sharp(source).flop().modulate({saturation:0.75}).png().toBuffer() : source;
      await call('http://127.0.0.1:7466/profile/upload',{
        method:'POST',headers:authenticated(tokens.get(row.uid),{'Content-Type':'image/png','X-Chat-Path':row.photo}),body:bytes,
      });
    }
    const [meta] = await bucket.file(row.photo).getMetadata();
    if (meta.metadata?.firebaseStorageDownloadTokens) throw Error('La foto no es privada.');
    const years = Math.floor((Date.now()-Date.parse(row.birth))/(365.2425*86400000));
    const card = {firstName:row.firstName,age:years,gender:row.gender,description:row.description,
      careerId:profile.careerId,universityId:profile.universityId,interestIds:profile.interestIds,
      mainPhotoUrl:row.photo,isActive:true,updatedAt:stamp};
    const projection = {
      ['discoveryIndex/'+row.uid]:{isActive:true,updatedAt:stamp},
      ['discoveryCards/'+row.uid]:card,
      ['matchProfiles/'+row.uid]:{...card,photoUrls:[row.photo]},
      ['preferences/'+row.uid]:{minAge:18,maxAge:100,preferredGender:'ambos',careerIds:[],updatedAt:stamp},
    };
    if (!(await db.doc('discoveryCards/'+row.uid).get()).exists) {
      const batch = db.batch().update(profileRef,{photoUrls:[row.photo],mainPhotoUrl:row.photo,isActive:true});
      for (const [path,data] of Object.entries(projection)) batch.create(db.doc(path),data);
      await batch.commit();
    }
    await call('http://127.0.0.1:7466/profile/media/'+encodeURIComponent(row.photo),{headers:authenticated(tokens.get(row.uid))});
  }
  for (const [a,b,messages] of pairs) {
    const match = 'matches/'+idFor(a,b);
    const like = (from,to)=>['swipes/'+idFor(from,to),{fromUserId:from.uid,toUserId:to.uid,type:'like'},'createdAt'];
    if (!(await db.doc('swipes/'+idFor(a,b)).get()).exists) await write(tokens.get(a.uid),[like(a,b)]);
    if (!(await db.doc(match).get()).exists) {
      await write(tokens.get(b.uid),[like(b,a),[match,{users:[a.uid,b.uid],isActive:true},'createdAt']]);
    }
    for (const [i,text] of messages.entries()) {
      const [sender,reader] = i%2===0?[a,b]:[b,a];
      const path = match+'/messages/dossier_'+i;
      let message = await db.doc(path).get();
      if (!message.exists) {
        await write(tokens.get(sender.uid),[[path,{senderId:sender.uid,text,type:'text'},'createdAt']]);
        message = await db.doc(path).get();
      }
      if (!message.data().readAt) await write(tokens.get(reader.uid),[[path,{},'readAt',false]]);
    }
  }
  const report = db.doc('reports/'+reportId);
  if (!(await report.get()).exists) await write(tokens.get(celia.uid),[[report.path,{
    reporterId:celia.uid,reportedId:alma.uid,reason:'other',details:'Ejercicio ficticio de moderación del staging.',status:'pending',
  },'createdAt']]);
  if ((await report.get()).data().status==='pending') await backend.reviewReport(moderator,reportId,'dismissed');
  await marker.update({ready:true});
}

async function remove() {
  const state = (await marker.get()).data();
  if (!state) return;
  if (state.version!==1) throw Error('Marcador desconocido.');
  const allowed = new Set(refs);
  const snapshots = await Promise.all([
    related('matches',[['users','array-contains']]),
    related('swipes',[['fromUserId','=='],['toUserId','==']]),
    related('reports',[['reporterId','=='],['reportedId','==']]),
    related('blocks',[['blockerId','=='],['blockedId','==']]),
    related('verificationRequests',[['uid','==']]),
    related('administrativeAudit',[['targetId','=='],['actorId','==']]),
  ]);
  const [matches,swipes,reports,blocks,requests,audit] = snapshots;
  const objects = new Map();
  for (const row of rows) {
    const user = await existingUser(row.uid);
    if (user && user.email!==row.email) throw Error('Cuenta reservada modificada; eliminación cancelada.');
    const [photos] = await bucket.getFiles({prefix:'profile_photos/'+row.uid+'/'});
    for (const file of photos) {
      if (file.name!==row.photo) throw Error('Foto ajena al conjunto; eliminación cancelada.');
      objects.set(file.name,file);
    }
  }
  for (const match of matches) {
    if (!allowed.has(match.ref.path)) throw Error('Match ajeno al conjunto; eliminación cancelada.');
    for (const sub of await match.ref.listCollections()) {
      for (const doc of (await sub.get()).docs) {
        if (!allowed.has(doc.ref.path)) throw Error('Conversación modificada; eliminación cancelada.');
      }
    }
  }
  if ([...swipes,...reports,...blocks].some(doc=>!allowed.has(doc.ref.path))) throw Error('Relación ajena al conjunto; eliminación cancelada.');
  for (const request of requests) {
    const {uid,documentPath} = request.data();
    const account = (await backend.account(uid).get()).data();
    if (account?.latestRequestId!==request.id) throw Error('Solicitud adicional; eliminación cancelada.');
    const path = 'university_cards/'+uid+'/'+request.id+'/document';
    if (documentPath && documentPath!==path) throw Error('Ruta no esperada; eliminación cancelada.');
    const [files] = await bucket.getFiles({prefix:'university_cards/'+uid+'/'});
    for (const file of files) {
      if (file.name!==path) throw Error('Carnet ajeno al conjunto; eliminación cancelada.');
      objects.set(file.name,file);
    }
    allowed.add(request.ref.path);
    allowed.add('verificationCleanup/'+request.id);
  }
  const requestIds = new Set(requests.map(doc=>doc.id));
  for (const doc of audit) {
    const event = doc.data();
    const seedApproval = event.action==='verification_approved'&&requestIds.has(event.requestId);
    const seedReport = event.action==='report_dismissed'&&event.targetId===alma.uid;
    if (event.actorId!==moderator || !(seedApproval||seedReport)) throw Error('Auditoría adicional; eliminación cancelada.');
    allowed.add(doc.ref.path);
  }
  for (const file of objects.values()) {
    const [meta] = await file.getMetadata();
    await file.delete({ifGenerationMatch:meta.generation,ignoreNotFound:true});
  }
  // Conservar el marcador hasta que Auth y Firestore terminen.
  for (const row of rows) if (await existingUser(row.uid)) await auth.deleteUser(row.uid);
  const batch = db.batch();
  for (const path of allowed) batch.delete(db.doc(path));
  batch.delete(marker);
  await batch.commit();
}

try {
  if (mode==='--seed') {
    await seed();
    const root = await login('ligo_root@ligo.test');
    for (const row of rows) {
      const result = await call('http://127.0.0.1:7466/administration/dossier?user='+row.uid,{headers:authenticated(root)});
      const d = await result.json();
      const expected = row===alma?[1,3,1]:row===bruno?[2,5,0]:row===celia?[1,2,0]:[0,0,0];
      if (d.profile.name!==row.firstName+' '+row.lastName || !d.profile.career || !d.profile.university ||
          d.verifications[0]?.status!==(row.approved?'approved':'pending') ||
          [d.activity.matches,d.activity.messages,d.activity.reportsReceived].some((v,i)=>v!==expected[i]) ||
          d.activity.contacts.some(c=>!c.name || c.name.startsWith('ligo_')) ||
          (row===alma && !d.audit.some(event=>event.action==='report_dismissed'&&event.actor))) {
        throw Error('Expediente incompleto: '+row.firstName);
      }
      console.log(d.profile.name+': expediente verificado · '+expected[0]+' matches, '+expected[1]+' mensajes, '+expected[2]+' reportes recibidos');
    }
  } else {
    await remove();
    console.log('Retiro selectivo del conjunto terminado.');
  }
} finally {
  await db.terminate();
}
