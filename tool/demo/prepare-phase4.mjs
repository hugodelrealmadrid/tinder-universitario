import sharp from 'sharp';
import {FieldValue} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {writeFile,mkdir} from 'node:fs/promises';
import {emulatorServices} from '../backend/emulator.mjs';
import {VerificationBackend} from '../backend/verification.mjs';
if(process.argv[2]!=='--synthetic-only')throw new Error('Requiere --synthetic-only');
const services=await emulatorServices(),{auth,db}=services,backend=new VerificationBackend(services);
const root='demo_superadmin';
const rootAuth=await auth.getUser(root);
if(rootAuth.email!=='superadmin@demo.test'||(await backend.lookupAccount(root,root)).role!=='superadmin')throw new Error('Bootstrap demo previo requerido; no se recrea.');
const png=await sharp(Buffer.from('<svg width="800" height="420" xmlns="http://www.w3.org/2000/svg"><rect width="800" height="420" fill="#fff0f4"/><g font-family="sans-serif" fill="#7b163e"><text x="40" y="80" font-size="32">DOCUMENTO FICTICIO - SOLO DEMO</text><text x="40" y="155" font-size="28">Univalle Cochabamba - Estudiante Demo</text><text x="40" y="230" font-size="28">Vigencia ficticia: 2026</text><text x="40" y="330" font-size="36">NO VALIDO COMO CARNET REAL</text></g></svg>')).png().toBuffer();
await mkdir(new URL('../../build/phase4-fixtures/',import.meta.url),{recursive:true});
await writeFile(new URL('../../build/phase4-fixtures/carnet-ficticio.png',import.meta.url),png);
for(const [uid,email,name,mode] of [
 ['demo_admin','admin@demo.test','Administradora','admin'],
 ['demo_student','estudiante@demo.test','Estudiante','pending'],
 ['demo_rejected','rechazado@demo.test','Rechazado','rejected'],
 ['demo_suspended','suspendido@demo.test','Suspendido','suspended'],
]) {
 let user;try{user=await auth.getUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;user=await auth.createUser({uid,email,password:'DemoTinder2026!',emailVerified:true});}
 if(user.email!==email||!user.emailVerified||user.disabled)throw new Error('Identidad sintética inconsistente');
 const profile=db.doc('users/'+uid);
 await db.runTransaction(async tx=>{const p=await tx.get(profile);if(!p.exists){const now=FieldValue.serverTimestamp();tx.create(profile,{firstName:name,lastName:'Demo',email,birthDate:new Date('2000-01-01T00:00:00Z'),gender:'',description:'Cuenta sintética de pruebas; sin documento real.',careerId:null,photoUrls:[],mainPhotoUrl:null,interestIds:[],role:'user',isActive:false,datingAllowed:false,createdAt:now,updatedAt:now});}});
 await backend.provision(uid);
 const a=await backend.lookupAccount(root,uid);
 // Solo prepara cuentas nuevas. Reejecutar conserva las decisiones manuales existentes.
 const own=await backend.ownRequest(uid).catch(()=>null);
 if(!own && a.verificationStatus==='pending' && !a.suspended){
  if(mode==='suspended') await backend.suspend(root,uid,true,'safety');
  else { const {requestId}=await backend.begin(uid); await backend.upload(uid,requestId,png);
   if(mode==='admin'){ await backend.decide(root,requestId,'approved','verified'); await backend.changeRole(root,uid,'admin'); }
   if(mode==='rejected')await backend.decide(root,requestId,'rejected','unreadable');
  }
 }
}
const report=db.doc('reports/phase4-synthetic');
if(!(await report.get()).exists)await report.set({reporterId:'manual_bob',reportedId:'demo_suspended',reason:'spam',details:'Reporte FICTICIO para prueba del panel.',status:'pending',createdAt:FieldValue.serverTimestamp()});
await backend.cleanupDue();
console.log('Cuentas sintéticas preparadas mediante operaciones reales del backend; sin modificar Ana/Bob/Carla ni el bootstrap.');
await deleteApp(services.app);
