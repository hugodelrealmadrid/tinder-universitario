import {initializeApp,applicationDefault,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {hostedConfig} from './hosted-config.mjs';
export function hostedServices(env=process.env){
 const config=hostedConfig(env);
 // No se admite arrancar esta entrada remota desde un proceso local por accidente.
 if(!env.K_SERVICE&&!env.CLOUD_RUN_JOB)throw new Error('cloud-run-required');
 const app=initializeApp({projectId:config.project,storageBucket:config.bucket,credential:applicationDefault()},'hosted');
 return {app,config,auth:getAuth(app),db:getFirestore(app),bucket:getStorage(app).bucket(),firestoreOrigin:'https://firestore.googleapis.com',close:()=>deleteApp(app)};
}
