// Se ejecuta ANTES del SDK y de Flutter. Ninguna conexión saliente a Internet.
const origins = new Set([location.origin,'http://127.0.0.1:9099','http://127.0.0.1:8088','http://127.0.0.1:9198']);
const originalFetch = window.fetch.bind(window);
const audit = (event) => originalFetch('/__demo/audit',{
  method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(event),
}).catch(()=>{});
function check(input,method) {
  const url=new URL(input,location.href);
  if(url.protocol==='blob:' && url.origin===location.origin) {
    audit({kind:'local-blob',method});return;
  }
  if(url.protocol==='data:') return;
  const safe=origins.has(url.origin);
  audit({kind:safe?'local':'blocked',method,origin:url.origin,path:url.pathname});
  if(!safe) throw new Error(`DEMO: conexión externa bloqueada a ${url.origin}`);
}
window.fetch = function(input,...args) {
  check(typeof input==='string'||input instanceof URL?input:input.url,'fetch');
  return originalFetch(input,...args);
};
const open=XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open=function(method,url,...args) {check(url,'xhr');return open.call(this,method,url,...args);};
const NativeWebSocket=window.WebSocket;
window.WebSocket=class extends NativeWebSocket {
  constructor(url,...args) { check(String(url).replace(/^ws:/,'http:').replace(/^wss:/,'https:'),'websocket');super(url,...args); }
};
document.addEventListener('securitypolicyviolation',event=>audit({
  kind:'csp-blocked',directive:event.effectiveDirective,origin:event.blockedURI.split('?')[0],
}));
new PerformanceObserver(list=>{
  for(const entry of list.getEntries()) {
    const url=new URL(entry.name,location.href);
    if(!['http:','https:'].includes(url.protocol)||url.pathname==='/__demo/audit')continue;
    audit({kind:'resource',origin:url.origin,path:url.pathname});
  }
}).observe({type:'resource',buffered:true});
window.demoFirebaseReady = (project,bucket) => {
  const apps=window.firebase_core.getApps();
  const app=window.firebase_core.getApp();
  const auth=window.firebase_auth.getAuth(app);
  const db=window.firebase_firestore.getFirestore(app);
  const storage=window.firebase_storage.getStorage(app,bucket);
  const actual={project,bucket,apps:apps.map(a=>a.options.projectId),
    auth:auth.emulatorConfig,firestore:{host:db._settings.host,ssl:db._settings.ssl},
    storage:{host:storage._host,protocol:storage._protocol}};
  if(project!=='demo-tinder-universitario'||bucket!=='demo-tinder-universitario.appspot.com'||
      apps.some(a=>a.options.projectId!==project)||auth.emulatorConfig?.host!=='127.0.0.1'||
      auth.emulatorConfig?.port!==9099||db._settings.host!=='127.0.0.1:8088'||
      db._settings.ssl!==false||storage._host!=='127.0.0.1:9198'||storage._protocol!=='http') {
    audit({kind:'configuration-error',actual}); throw new Error('Los SDK no están aislados: se cancela el arranque.');
  }
  audit({kind:'ready',actual});
  document.getElementById('demo-status').textContent='DEMO LOCAL VERIFICADO · Auth 9099 · Firestore 8088 · Storage 9198 · Producción bloqueada'+(window.__demoSyntheticMic?' · MICRÓFONO SINTÉTICO DE PRUEBA':'');
};
