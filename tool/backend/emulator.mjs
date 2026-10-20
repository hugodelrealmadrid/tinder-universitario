import {initializeApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';
import {getStorage} from 'firebase-admin/storage';

// Sin credenciales ADC ni fallback remoto. Exige los tres endpoints explícitos.
export async function emulatorServices(project='demo-tinder-universitario',ports={auth:9099,firestore:8088,storage:9198,hub:4400}) {
 if(!/^demo-[a-z0-9-]+$/.test(project))throw new Error('demo-only');
 const hub=await fetch(`http://127.0.0.1:${ports.hub}/emulators`).then(r=>r.json());
 for(const name of ['auth','firestore','storage']){
  if(hub[name]?.host!=='127.0.0.1'||hub[name]?.port!==ports[name])throw new Error('emulators-required');
 }
 for(const [name,key] of [['auth','FIREBASE_AUTH_EMULATOR_HOST'],['firestore','FIRESTORE_EMULATOR_HOST'],['storage','FIREBASE_STORAGE_EMULATOR_HOST']]){
  const expected=`127.0.0.1:${ports[name]}`;
  if(process.env[key]&&process.env[key]!==expected)throw new Error('emulator-mismatch');
  process.env[key]=expected;
 }
 const app=initializeApp({projectId:project,storageBucket:project+'.appspot.com'},'verification-'+project);
 return {app,db:getFirestore(app),auth:getAuth(app),bucket:getStorage(app).bucket()};
}
