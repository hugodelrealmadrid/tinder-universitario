// Inspector oficial de la app propia; no lee campos de entrada ni credenciales.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
const endpoint=(await readFile('build/android-usb-vm.txt','utf8')).trim();
assert.match(endpoint,/^ws:\/\/127\.0\.0\.1:\d+\//);
const socket=new WebSocket(endpoint),pending=new Map();let sequence=0;
socket.addEventListener('message',e=>{
 const v=JSON.parse(e.data),item=pending.get(v.id);if(!item)return;
 pending.delete(v.id);clearTimeout(item.timer);v.error?item.reject(Error(v.error.message)):item.resolve(v.result);
});
function call(method,params={}){return new Promise((resolve,reject)=>{
 const id=++sequence,timer=setTimeout(()=>{pending.delete(id);reject(Error('VM timeout'));},15000);
 pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));
});}
await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
try {
 const vm=await call('getVM'),isolate=vm.isolates.find(i=>i.name==='main');assert.ok(isolate);
 const info=await call('getIsolate',{isolateId:isolate.id});
 const main=info.libraries.find(l=>l.uri.endsWith('/main_demo_android.dart'));assert.ok(main);
 const evaluate=async expression=>{
  const v=await call('evaluate',{isolateId:isolate.id,targetId:main.id,expression,disableBreakpoints:true});
  assert.notEqual(v.type,'Error');return v.valueAsString;
 };
 const project=await evaluate('Firebase.apps.map((a) => a.options.projectId).join(",")');assert.equal(project,'demo-tinder-universitario');
 const firestoreHost=await evaluate('FirebaseFirestore.instance.settings.host');assert.equal(firestoreHost,'127.0.0.1:8088');
 const tree=await call('ext.flutter.inspector.getRootWidgetSummaryTree',{isolateId:isolate.id,objectGroup:'demo-usb-audit'});
 const names=new Set();function walk(n){if(!n||typeof n!=='object')return;if(typeof n.description==='string')names.add(n.description.split('(')[0]);for(const c of n.children??[])walk(c);}
 walk(tree.result);
 const screen=[...names].filter(n=>/^(LoginScreen|UniversityGate|HomeScreen|ProfileGate|AuthGate)$/.test(n));
 assert.ok(screen.length>0,'Sin pantalla Flutter reconocida');
 // Peticiones sin credenciales desde el propio proceso Android. Solo localhost;
 // los códigos aparecen en logcat como DEMO_USB_HTTP_<puerto>=<código>.
 const backend=info.libraries.find(l=>l.uri.endsWith('/backend_client.dart'));assert.ok(backend);
 for(const [port,path] of [[7357,'/__demo/api/verification/own'],[7360,'/verification/own'],[9099,'/'],[8088,'/'],[9198,'/v0/b/demo-tinder-universitario.appspot.com/o/profile_photos%2Fmanual_ana%2Fmain']]) {
  const expression=`http.get(Uri.parse('http://127.0.0.1:${port}${path}')).timeout(const Duration(seconds: 5)).then((r) => print('DEMO_USB_HTTP_${port}=' + r.statusCode.toString())).catchError((Object _) { print('DEMO_USB_HTTP_${port}=ERROR'); })`;
  const r=await call('evaluate',{isolateId:isolate.id,targetId:backend.id,expression,disableBreakpoints:true});
  assert.notEqual(r.type,'Error');
 }
 const result={project,firestoreHost,screen,flutterMounted:true};
 await writeFile('audit-android-usb-runtime.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 await call('ext.flutter.inspector.disposeGroup',{isolateId:isolate.id,objectGroup:'demo-usb-audit'}).catch(()=>{});
}finally{socket.close();}
