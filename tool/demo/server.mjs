import {createServer} from 'node:http';
import {readFile,stat,appendFile,mkdir} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const build=resolve(root,'build/demo-web');
const demo=resolve(root,'tool/demo');
const events=[];
const policy="default-src 'self'; connect-src 'self' blob: http://127.0.0.1:9099 http://127.0.0.1:8088 http://127.0.0.1:9198; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data: http://127.0.0.1:9198; font-src 'self' data:; media-src 'self' blob: data: http://127.0.0.1:9198; worker-src 'self' blob:; frame-src 'self' http://127.0.0.1:9099; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'";
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.ttf':'font/ttf','.woff2':'font/woff2','.css':'text/css'};
await stat(resolve(build,'main.dart.js'));
await mkdir(resolve(root,'build'),{recursive:true});
createServer(async(req,res)=>{
  res.setHeader('Content-Security-Policy',policy);
  res.setHeader('Cache-Control','no-store');
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('Referrer-Policy','no-referrer');
  try {
    const path=new URL(req.url,'http://127.0.0.1:7357').pathname;
    if(path.startsWith('/__demo/api/')) {
      if(req.headers.origin && req.headers.origin!=='http://127.0.0.1:7357') {res.writeHead(403).end();return;}
      let size=0;const chunks=[];for await(const b of req){size+=b.length;if(size>16*1024*1024){res.writeHead(413).end();return;}chunks.push(b);}
      const response=await fetch('http://127.0.0.1:7360/'+path.slice('/__demo/api/'.length)+new URL(req.url,'http://127.0.0.1:7357').search,{
        method:req.method,headers:{Authorization:req.headers.authorization??'',Origin:'http://127.0.0.1:7357',
          'Content-Type':req.headers['content-type']??'application/json','X-Chat-Path':req.headers['x-chat-path']??''},
        ...(req.method==='GET'?{}:{body:Buffer.concat(chunks)})});
      res.writeHead(response.status,{'Content-Type':response.headers.get('content-type')??'application/json','Cache-Control':'no-store'});
      res.end(Buffer.from(await response.arrayBuffer()));return;
    }
    if(path==='/__demo/start.html') {
      res.setHeader('Content-Type','text/html; charset=utf-8');
      res.end('<!doctype html><html><head><title>Arranque demo aislado</title></head><body>Preparando página local sin cachés anteriores…<script type="module" src="/_demo/start.js"></script></body></html>');return;
    }
    if(path==='/__demo/probe.html') {
      res.setHeader('Content-Type','text/html; charset=utf-8');
      res.end('<!doctype html><html><head><title>Verificación CSP demo</title></head><body><h1>Aislamiento de red del entorno demo</h1><p>Prueba con un dominio reservado .invalid, sin credenciales ni datos.</p><button id="probe">Probar bloqueo externo</button><p id="probe-result">Pendiente</p><button id="blob-probe">Probar lectura de blob local</button><p id="blob-result">Pendiente</p><script src="/_demo/probe.js"></script></body></html>');return;
    }
    if(path==='/__demo/audit'&&req.method==='POST') {
      if(req.headers.origin && req.headers.origin!=='http://127.0.0.1:7357') {res.writeHead(403).end();return;}
      let body='';for await(const chunk of req){body+=chunk;if(body.length>16384){res.writeHead(413).end();return;}}
      const event={...JSON.parse(body),at:new Date().toISOString()};
      events.push(event);if(events.length>5000)events.shift();
      await appendFile(resolve(root,'audit-demo-network.log'),JSON.stringify(event)+'\n');
      res.writeHead(204).end();return;
    }
    if(path==='/__demo/status') {
      res.setHeader('Content-Type','application/json');
      res.end(JSON.stringify({project:'demo-tinder-universitario',policy,events},null,2));return;
    }
    if(path==='/__demo/reset-audit'&&req.method==='POST') {
      events.length=0;res.writeHead(204).end();return;
    }
    let folder=build,relative=decodeURIComponent(path).replace(/^\//,'');
    if(path.startsWith('/_demo/firebase/')){folder=resolve(demo,'vendor');relative=path.slice('/_demo/firebase/'.length);}
    else if(path.startsWith('/assets/demo_fonts/')){folder=resolve(demo,'vendor');relative=path.slice('/assets/demo_fonts/'.length);}
    else if(path.startsWith('/_demo/')){folder=demo;relative=path.slice('/_demo/'.length);}
    else if(path==='/') relative='index.html';
    const file=resolve(folder,relative);
    if(!file.startsWith(folder+sep)){res.writeHead(403).end();return;}
    let data=await readFile(file);
    if(relative==='assets/FontManifest.json'&&folder===build) {
      const manifest=JSON.parse(data.toString());
      manifest.push({family:'Roboto',fonts:[
        {asset:'demo_fonts/roboto-regular.ttf',weight:400},
        {asset:'demo_fonts/roboto-thin.ttf',weight:100},
        {asset:'demo_fonts/roboto-light.ttf',weight:300},
        {asset:'demo_fonts/roboto-medium.ttf',weight:500},
        {asset:'demo_fonts/roboto-bold.ttf',weight:700},
        {asset:'demo_fonts/roboto-black.ttf',weight:900},
        {asset:'demo_fonts/roboto-italic.ttf',style:'italic',weight:400},
        {asset:'demo_fonts/roboto-bolditalic.ttf',style:'italic',weight:700},
      ]});data=Buffer.from(JSON.stringify(manifest));
    }
    if(relative==='flutter_bootstrap.js'&&folder===build) {
      data=Buffer.from(data.toString().replace(/serviceWorkerSettings:\s*\{[^}]*\}/,''));
    }
    if(relative==='index.html' && folder===build) {
      data=Buffer.from(data.toString().replace('<body>',`<body><div id="demo-status" role="status" style="position:fixed;top:0;left:0;right:0;height:26px;z-index:999999;background:#16452d;color:white;text-align:center;font:12px Arial;line-height:26px">Preparando entorno DEMO local…</div>`)
        .replace(/<script src="flutter_bootstrap.js" async><\/script>/,'<script type="module" src="/_demo/bootstrap.js"></script>'));
    }
    res.setHeader('Content-Type',mime[extname(file)]??'application/octet-stream');res.end(data);
  } catch(error) {res.writeHead(404).end('Recurso local no disponible.');}
}).listen(7357,'127.0.0.1',()=>console.log('DEMO WEB: http://127.0.0.1:7357 · conexiones externas bloqueadas por CSP'));
