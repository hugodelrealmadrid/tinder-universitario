import {mkdirSync,realpathSync} from 'node:fs';
import {dirname,resolve,relative,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createConnection} from 'node:net';

export const projectRoot=resolve(dirname(fileURLToPath(import.meta.url)),'..');
export function isolationPaths(role,root=projectRoot){
 if(!['demo','tests'].includes(role))throw new Error('Unknown emulator environment');
 const base=resolve(root,'build','emulator-runtime',role);
 return {base,temp:resolve(base,'temp'),run:resolve(base,'run'),project:role==='demo'?'demo-tinder-universitario':'demo-tinder-phase3-tests',config:resolve(root,role==='demo'?'firebase.demo.json':'firebase.phase3-tests.json')};
}
export function isolatedEnvironment(role,parent=process.env,root=projectRoot){
 const p=isolationPaths(role,root);
 // Do not inherit endpoints, credentials, runtime flags or production projects.
 const env={...parent};
 for(const key of ['FIREBASE_AUTH_EMULATOR_HOST','FIRESTORE_EMULATOR_HOST','FIREBASE_STORAGE_EMULATOR_HOST','FIREBASE_DATABASE_EMULATOR_HOST','GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_TOKEN','CLOUDSDK_AUTH_ACCESS_TOKEN','GOOGLE_CLOUD_PROJECT','GCLOUD_PROJECT','FIREBASE_CONFIG','NODE_OPTIONS','JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS'])delete env[key];
 Object.assign(env,{TEMP:p.temp,TMP:p.temp,TMPDIR:p.temp,GCLOUD_PROJECT:p.project,GOOGLE_CLOUD_PROJECT:p.project,
  FIREBASE_EMULATORS_PATH:resolve(root,'tool/emulator-cache'),JAVA_TOOL_OPTIONS:'-Xmx384m',CI:'true'});
 if(role==='tests')Object.assign(env,{RULES_PROJECT:p.project,RULES_FIRESTORE_PORT:'8188',RULES_STORAGE_PORT:'9298'});
 return env;
}
export async function assertLoopbackPortsFree(ports){
 await Promise.all(ports.map(port=>new Promise((resolve,reject)=>{
  const socket=createConnection({host:'127.0.0.1',port});
  socket.setTimeout(1500);
  socket.once('connect',()=>{socket.destroy();reject(new Error('Local port already in use: '+port));});
  socket.once('timeout',()=>{socket.destroy();reject(new Error('Cannot verify local port: '+port));});
  socket.once('error',e=>{socket.destroy();if(e.code==='ECONNREFUSED')resolve();else reject(e);});
 })));
}
export function prepareIsolation(role){
 const p=isolationPaths(role),root=realpathSync(projectRoot);
 for(const path of [p.temp,p.run]){
  mkdirSync(path,{recursive:true});
  const rel=relative(root,realpathSync(path));
  if(rel.startsWith('..')||isAbsolute(rel))throw new Error('Runtime directory escapes workspace');
 }
 return p;
}
