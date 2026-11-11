import {Stories} from '../backend/stories.mjs';
import {VerificationBackend} from '../backend/verification.mjs';
import {watchStagingNotifications} from './notifications-watch.mjs';
import {createServer} from 'node:http';import {readFile,stat} from 'node:fs/promises';import {resolve,extname,sep} from 'node:path';import {execFileSync} from 'node:child_process';
import {emulatorServices} from '../backend/emulator.mjs';import {requestHandler} from '../backend/http-handler.mjs';
if(execFileSync('git',['branch','--show-current']).toString().trim()!=='codex/ligo')throw Error('ligo-branch-required');
const services=await emulatorServices('demo-ligo-staging',{auth:9399,firestore:8288,storage:9498,hub:4420});
const storiesEnabled=process.argv[2]==='--stories';
const notificationsEnabled=storiesEnabled||process.argv[2]==='--notifications';
if(storiesEnabled){
 const stories=new Stories(new VerificationBackend(services));
 const clean=()=>stories.cleanup().catch(()=>console.error('story-cleanup-retry'));
 void clean();setInterval(clean,60000).unref();
}
if(notificationsEnabled)watchStagingNotifications(services);
createServer(requestHandler(services,{origins:['http://127.0.0.1:7465'],publicRegistrationEnabled:notificationsEnabled||process.argv[2]==='--academic-guided',notificationsEnabled,storiesEnabled})).listen(7466,'127.0.0.1');
const root=resolve(({
  '--dossier':'build/ligo-20-dossier/web',
  '--admin-photos':'build/ligo-admin-photos/web',
  '--dossier-premium':'build/ligo-dossier-premium/web',
  '--academic':'build/ligo-academic/web',
  '--academic-guided':'build/ligo-academic-guided/web',
  '--notifications':'build/ligo-notifications/web',
  '--stories':'build/ligo-stories/web',
})[process.argv[2]]??'build/ligo-staging/web');
// FlutterFire imports ES modules from this pinned SDK directory. Flutter's
// renderer fetches font bytes directly, so the font path also needs connect-src.
const firebaseSdk='https://www.gstatic.com/firebasejs/12.19.0/';
const fonts='https://fonts.gstatic.com/s/';
const csp=[
  "default-src 'none'",
  `script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' ${firebaseSdk}`,
  `script-src-elem 'self' 'unsafe-inline' ${firebaseSdk}`,
  "style-src 'self' 'unsafe-inline'",
  "manifest-src 'self'",
  "img-src 'self' blob: data:",
  `font-src 'self' data: ${fonts}`,
  "media-src 'self' blob:",
  `connect-src 'self' blob: http://127.0.0.1:9399 http://127.0.0.1:8288 ws://127.0.0.1:8288 http://127.0.0.1:9498 http://127.0.0.1:7466 ${fonts}`,
  "worker-src 'self' blob:",
  "frame-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join('; ');
const mime={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.jpg':'image/jpeg','.ttf':'font/ttf','.otf':'font/otf'};
createServer(async(req,res)=>{res.setHeader('Content-Security-Policy',csp);res.setHeader('Cache-Control','no-store');res.setHeader('Permissions-Policy','microphone=(self),camera=()');res.setHeader('X-Content-Type-Options','nosniff');try{let p=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://127.0.0.1:7465').pathname));if(p!==root&&!p.startsWith(root+sep)){res.writeHead(403).end();return;}if((await stat(p)).isDirectory())p=resolve(p,'index.html');const bytes=await readFile(p);res.setHeader('Content-Type',mime[extname(p)]??'application/octet-stream');res.end(bytes);}catch{res.writeHead(404).end();}}).listen(7465,'127.0.0.1',()=>console.log('Staging local: http://127.0.0.1:7465/; backend 7466; producción bloqueada por CSP.'));
