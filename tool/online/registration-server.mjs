import {createServer} from 'node:http';
import {readFile,stat} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const sdk=fileURLToPath(new URL('../../build/registration-firebase/',import.meta.url));
const bootstrap=fileURLToPath(new URL('./registration-bootstrap.mjs',import.meta.url));
const root=fileURLToPath(new URL('../../build/registration-web/',import.meta.url));
await stat(resolve(root,'main.dart.js'));
const policy="default-src 'self'; connect-src 'self' blob: https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://firestore.googleapis.com https://www.gstatic.com https://fonts.gstatic.com; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval' https://www.gstatic.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data: https://fonts.gstatic.com; media-src 'none'; worker-src 'self' blob:; frame-src https://tinder-universitario.firebaseapp.com; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'";
const mime={'.mjs':'text/javascript; charset=utf-8','.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.ttf':'font/ttf','.woff2':'font/woff2'};
createServer(async(req,res)=>{
 res.setHeader('Content-Security-Policy',policy);res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');
 if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
 try{const url=new URL(req.url,'http://localhost:7358');let path=decodeURIComponent(url.pathname);if(path==='/')path='/index.html';const sdkRequest=path.startsWith('/firebase-sdk/');const file=path==='/registration-bootstrap.js'?bootstrap:sdkRequest?resolve(sdk,path.slice('/firebase-sdk/'.length)):resolve(root,'.'+path);if(file!==bootstrap&&!file.startsWith((sdkRequest?sdk:root).replace(/[\\/]$/,'')+sep))throw Error();let bytes=await readFile(file);if(path==='/index.html')bytes=Buffer.from(bytes.toString().replace('<script src="flutter_bootstrap.js" async></script>','<script type="module" src="/registration-bootstrap.js"></script>'));if(path==='/flutter_bootstrap.js')bytes=Buffer.from(bytes.toString().replace(/serviceWorkerSettings:\s*\{[^}]*\}/,''));res.setHeader('Content-Type',mime[extname(file)]??'application/octet-stream');res.end(req.method==='HEAD'?undefined:bytes);}
 catch{res.writeHead(404).end('Recurso no disponible.');}
}).listen(7358,'127.0.0.1',()=>console.log('Registro personal real: http://localhost:7358/ · sin proxy de credenciales ni backend'));
