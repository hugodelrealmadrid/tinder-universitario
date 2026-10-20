import {FieldValue} from 'firebase-admin/firestore';
import {deleteApp} from 'firebase-admin/app';
import {emulatorServices} from '../backend/emulator.mjs';
import {VerificationBackend} from '../backend/verification.mjs';
const services=await emulatorServices(),{db,auth}=services;
const uid='demo_pending',email='pendiente@demo.test';
let user;try{user=await auth.getUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;user=await auth.createUser({uid,email,password:'DemoTinder2026!',emailVerified:true});}
if(user.email!==email)throw new Error('UID reservado no coincide.');
const ref=db.doc('users/'+uid);
await db.runTransaction(async tx=>{const p=await tx.get(ref);if(!p.exists){const now=FieldValue.serverTimestamp();tx.create(ref,{firstName:'Pendiente',lastName:'Demo',email,birthDate:new Date('2000-01-01T00:00:00Z'),gender:'',description:'Fixture pendiente; sin documentos reales.',careerId:null,photoUrls:[],mainPhotoUrl:null,interestIds:[],role:'user',isActive:false,datingAllowed:false,createdAt:now,updatedAt:now});}});
await new VerificationBackend(services).provision(uid);await deleteApp(services.app);console.log('Fixture pendiente creada sin aprobación.');
