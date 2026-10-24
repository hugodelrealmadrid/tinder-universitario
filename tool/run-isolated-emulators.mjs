import {spawn} from 'node:child_process';
import {existsSync,readFileSync} from 'node:fs';
import {resolve,isAbsolute,relative} from 'node:path';
import {isolationPaths,isolatedEnvironment,prepareIsolation,projectRoot,assertLoopbackPortsFree} from './emulator-isolation.mjs';

const [action,...options]=process.argv.slice(2);
if(!['demo','tests','compare','export'].includes(action))throw new Error('Use demo/compare --import PATH, tests, or export --output NEW_PATH');
const role=['tests','compare'].includes(action)?'tests':'demo';
const p=isolationPaths(role);
const expected=['demo','compare'].includes(action)?'--import':action==='export'?'--output':null;
if(expected?(options.length!==2||options[0]!==expected):options.length!==0)throw new Error('Invalid arguments');
const env=isolatedEnvironment(role);
if(!env.JAVA_HOME||!existsSync(resolve(env.JAVA_HOME,'bin/java.exe')))throw new Error('Set JAVA_HOME to local Java 21');
env.PATH=resolve(env.JAVA_HOME,'bin')+';'+(env.PATH??env.Path??'');delete env.Path;
const cli=resolve(projectRoot,'tool/node_modules/firebase-tools/lib/bin/firebase.js');
let args;
if(['demo','compare'].includes(action)){
 const source=resolve(options[1]),rel=relative(projectRoot,source);
 if(!isAbsolute(options[1])||rel.startsWith('..')||isAbsolute(rel))throw new Error('Import must be inside this workspace');
 const m=JSON.parse(readFileSync(resolve(source,'firebase-export-metadata.json'),'utf8').replace(/^\uFEFF/,''));
 if(!m.auth||!m.storage||!m.firestore)throw new Error('A complete local export is required');
 const accounts=JSON.parse(readFileSync(resolve(source,m.auth.path,'accounts.json'),'utf8').replace(/^\uFEFF/,''));
 if(accounts.users?.length!==10||accounts.users.some(u=>!u.email?.endsWith('@demo.test')))throw new Error('Unexpected demo accounts');
 const buckets=JSON.parse(readFileSync(resolve(source,m.storage.path,'buckets.json'),'utf8'));
 if(buckets.buckets?.length!==1||buckets.buckets[0].id!=='demo-tinder-universitario.appspot.com')throw new Error('Unexpected bucket');
 args=action==='demo'?['emulators:start','--only','auth,firestore,storage','--import',source]:
  ['emulators:exec','--only','firestore','--import',source,'node "'+resolve(projectRoot,'tool/demo/compare-recovered-firestore.mjs')+'"'];
}else if(action==='tests'){
 const suite=['rules.test.mjs','phase3.test.mjs','phase5.test.mjs'].map(f=>'"'+resolve(projectRoot,'tool',f)+'"').join(' ');
 args=['emulators:exec','--only','auth,firestore,storage','node --test --test-concurrency=1 '+suite];
}else{
 const target=resolve(options[1]),rel=relative(projectRoot,target);
 if(!isAbsolute(options[1])||rel.startsWith('..')||isAbsolute(rel)||existsSync(target))throw new Error('Export requires a new workspace directory');
 args=['emulators:export',target];
}
if(action!=='export')await assertLoopbackPortsFree(role==='demo'?[9099,8088,9198,4400]:[9199,8188,9298,4410]);
prepareIsolation(role);
args.push('--project',p.project,'--config',p.config,'--non-interactive');
console.log(JSON.stringify({action,project:p.project,TEMP:env.TEMP,TMP:env.TMP,cwd:p.run}));
const child=spawn(process.execPath,[cli,...args],{cwd:p.run,env,stdio:'inherit',windowsHide:true});
child.on('error',e=>{console.error(e.message);process.exitCode=1;});
child.on('exit',(code)=>{process.exitCode=code??1;});
