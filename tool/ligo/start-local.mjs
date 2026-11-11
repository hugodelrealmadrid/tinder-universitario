import {spawn,execFileSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdir,readFile,writeFile,readdir,stat} from 'node:fs/promises';
import {openSync,closeSync,existsSync} from 'node:fs';
import {resolve,dirname,relative,isAbsolute,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');process.chdir(root);
const project='demo-ligo-staging',ports=[9399,8288,9498,4420,4520,9165,7465,7466];
const home=resolve(root,'build/ligo-staging/persistent'),pointer=join(home,'latest.json');
const hash=b=>createHash('sha256').update(b).digest('hex');
const stamp=()=>new Date().toISOString().replaceAll(':','-').replaceAll('.','-')+'-'+randomUUID().slice(0,8);
if(execFileSync('git',['branch','--show-current'],{encoding:'utf8'}).trim()!=='codex/ligo')throw Error('Se requiere codex/ligo.');
const stories=process.argv.includes('--stories');
const web=stories?'build/ligo-stories/web/index.html':'build/ligo-staging/web/index.html';
if(!existsSync(web))throw Error('Falta la compilación Web existente.');
for(const port of ports)await new Promise((ok,no)=>{const s=createServer();s.once('error',()=>no(Error('Puerto ocupado: '+port+'. No se detendrá ningún servicio.')));s.listen(port,'127.0.0.1',()=>s.close(ok));});
let imported=null;
if(existsSync(pointer)){
 const manifest=JSON.parse(await readFile(pointer,'utf8'));if(manifest.project!==project)throw Error('Proyecto de respaldo incorrecto.');
 imported=resolve(home,manifest.directory);if(!imported.startsWith(home+'/')&&!imported.startsWith(home+'\\'))throw Error('Ruta de respaldo inválida.');
 for(const f of manifest.files){const p=resolve(imported,f.path);if(relative(imported,p).startsWith('..')||isAbsolute(relative(imported,p))||hash(await readFile(p))!==f.sha256)throw Error('Falló integridad del respaldo.');}
 if(!existsSync(join(imported,'firebase-export-metadata.json')))throw Error('Exportación incompleta.');
}else if(!process.argv.includes('--reconstruct-fixtures'))throw Error('No hay respaldo persistente. No se iniciará vacío. La reconstrucción requiere autorización y --reconstruct-fixtures.');
await mkdir(home,{recursive:true});await mkdir(join(home,'exports'),{recursive:true});
const run=join(home,'runs',stamp());await mkdir(join(run,'temp'),{recursive:true});
const env={...process.env,TEMP:join(run,'temp'),TMP:join(run,'temp'),JAVA_HOME:process.env.JAVA_HOME??'C:/Program Files/Android/Android Studio/jbr',GCLOUD_PROJECT:project,GOOGLE_CLOUD_PROJECT:project,FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:9399',FIRESTORE_EMULATOR_HOST:'127.0.0.1:8288',FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:9498',FIREBASE_EMULATOR_HUB:'127.0.0.1:4420',FIREBASE_CLI_DISABLE_UPDATE_CHECK:'true',CI:'1'};
for(const key of ['GOOGLE_APPLICATION_CREDENTIALS','FIREBASE_TOKEN','GOOGLE_OAUTH_ACCESS_TOKEN'])delete env[key];
env.PATH=join(env.JAVA_HOME,'bin')+';'+(env.PATH??env.Path??'');delete env.Path;
const config=join(run,'firebase.json');await writeFile(config,JSON.stringify({firestore:{rules:resolve('firestore.rules'),indexes:resolve('staging/firestore.dossier.indexes.json')},storage:{rules:resolve('storage.rules')},emulators:{auth:{host:'127.0.0.1',port:9399},firestore:{host:'127.0.0.1',port:8288,websocketPort:9165},storage:{host:'127.0.0.1',port:9498},hub:{host:'127.0.0.1',port:4420},logging:{host:'127.0.0.1',port:4520},ui:{enabled:false},singleProjectMode:true}}));
const cli=resolve('tool/node_modules/firebase-tools/lib/bin/firebase.js'),children=[];
function launch(args,name,extraEnv=env){const fd=openSync(join(run,name+'.log'),'ax');let p;try{p=spawn(process.execPath,args,{cwd:root,env:extraEnv,stdio:['ignore',fd,fd],windowsHide:true});}finally{closeSync(fd);}children.push(p);return p;}
function completed(p){return new Promise((ok,no)=>{p.once('error',no);p.once('exit',code=>code===0?ok():no(Error('Proceso terminó con código '+code)));});}
const emulators=launch([cli,'emulators:start','--only','auth,firestore,storage','--project',project,'--config',config,'--non-interactive',...(imported?['--import',imported]:[])],'emulators');
let ready=false;
for(let i=0;i<120;i++){if(emulators.exitCode!==null)throw Error('Emuladores detenidos; consultar '+run);try{const r=await fetch('http://127.0.0.1:4420/emulators');const h=await r.json();ready=['auth','firestore','storage'].every(n=>h[n]?.host==='127.0.0.1'&&h[n]?.port===({auth:9399,firestore:8288,storage:9498})[n]);if(ready)break;}catch{}await new Promise(r=>setTimeout(r,1000));}
if(!ready)throw Error('Emuladores no iniciaron; se conservan todos los archivos.');
if(!imported){await completed(launch(['tool/ligo/seed.mjs'],'seed'));await completed(launch(['tool/ligo/seed-visual.mjs','--create-fictitious-only'],'seed-visual'));}
async function filesOf(dir,prefix=''){let a=[];for(const e of await readdir(join(dir,prefix),{withFileTypes:true})){const name=join(prefix,e.name);if(e.isDirectory())a.push(...await filesOf(dir,name));else if(e.isFile()){const bytes=await readFile(join(dir,name));a.push({path:name,bytes:bytes.length,sha256:hash(bytes)});}else throw Error('Tipo de archivo de respaldo inválido.');}return a;}
let saving=null;
async function save(){if(saving)return saving;saving=(async()=>{const directory=join('exports',stamp()),dest=join(home,directory),temp=join(run,'export-temp',stamp());await mkdir(temp,{recursive:true});const response=await fetch('http://127.0.0.1:4420/_admin/export',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({path:dest,initiatedBy:'ligo-local-persistence',targets:['auth','firestore','storage']})});if(!response.ok)throw Error('Exportación local falló: HTTP '+response.status+' '+await response.text());const meta=JSON.parse(await readFile(join(dest,'firebase-export-metadata.json'),'utf8'));if(!meta.auth||!meta.firestore||!meta.storage)throw Error('Falta un servicio en la exportación.');const files=await filesOf(dest);const manifest={project,directory,createdAt:new Date().toISOString(),files};for(const f of files)if(hash(await readFile(join(dest,f.path)))!==f.sha256)throw Error('Integridad de exportación incorrecta.');await writeFile(join(dest,'integrity.json'),JSON.stringify(manifest,null,2),{flag:'wx'});await writeFile(pointer,JSON.stringify(manifest,null,2));console.log('Respaldo completo verificado: '+dest);return manifest;})().finally(()=>saving=null);return saving;}
await save().catch(e=>console.error('Respaldo inicial pendiente: '+e.message));
const serverTemp=join(run,'server-temp');await mkdir(serverTemp,{recursive:true});const server=launch(['tool/ligo/server.mjs',...(stories?['--stories']:[])],'web-backend',{...env,TEMP:serverTemp,TMP:serverTemp});
console.log('LIGO: http://127.0.0.1:7465/ · respaldo cada 5 minutos · Ctrl+C guarda antes de cerrar.');console.log('Logs: '+run);
const timer=setInterval(()=>save().catch(e=>console.error('No se actualizó el respaldo: '+e.message)),300000);
let stopping=false;async function stop(){if(stopping)return;stopping=true;clearInterval(timer);try{await save();}catch(e){console.error('Falló el respaldo final; los anteriores permanecen intactos: '+e.message);}for(const p of [server,emulators])if(p.exitCode===null&&p.pid){try{execFileSync('taskkill',['/PID',String(p.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});}catch{}}process.exit();}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
for(const p of [server,emulators])p.on('exit',()=>{if(!stopping){console.error('Un servicio terminó. No se reiniciará ni reemplazará ningún dato automáticamente.');clearInterval(timer);}});
