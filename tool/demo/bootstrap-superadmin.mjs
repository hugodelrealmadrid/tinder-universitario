// Único bootstrap, CLI local, sin endpoint HTTP ni credenciales de producción.
import {FieldValue} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
const {db,auth,app}=await emulatorServices();
const uid='demo_superadmin',email='superadmin@demo.test';
if(process.argv[2]!=='--create-demo-superadmin')throw new Error('Usa --create-demo-superadmin explícitamente.');
let user;try{user=await auth.getUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;user=await auth.createUser({uid,email,password:'DemoTinder2026!',emailVerified:true});}
if(user.email!==email||!user.emailVerified||user.disabled)throw new Error('Identidad demo reservada no coincide.');
await db.runTransaction(async tx=>{
 const registry=db.doc('administration/roles'),access=db.doc('accountAccess/'+uid);
 const r=await tx.get(registry),a=await tx.get(access);
 const profile=db.doc('users/'+uid),p=await tx.get(profile);
 if(r.exists||a.exists)throw new Error('Bootstrap ya consumido; usar gestión de roles.');
 const now=FieldValue.serverTimestamp();
 tx.create(registry,{superadminIds:[uid],updatedAt:now});
 tx.create(access,{role:'superadmin',verificationStatus:'approved',suspended:false,latestRequestId:null,createdAt:now,updatedAt:now});
 if(!p.exists)tx.create(profile,{firstName:'Administración',lastName:'Demo',email,birthDate:new Date('2000-01-01T00:00:00Z'),gender:'',description:'Cuenta administrativa sintética local.',careerId:null,photoUrls:[],mainPhotoUrl:null,interestIds:[],role:'user',isActive:false,datingAllowed:true,createdAt:now,updatedAt:now});
 else tx.update(profile,{datingAllowed:true});
 tx.create(db.collection('administrativeAudit').doc(),{actorId:'demo_bootstrap',targetId:uid,action:'bootstrap',reasonCode:'synthetic_demo_only',requestId:null,at:now});
});
console.log('Superadministrador sintético demo creado una sola vez. No se aprobaron cuentas reales.');
await deleteApp(app);
