import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source=await readFile(new URL('./browser.js',import.meta.url),'utf8');
function guard() {
  const requests=[];
  class XHR {open(method,url){requests.push({method,url});}}
  const window={fetch:async(url)=>{requests.push({url});},WebSocket:class {}};
  runInNewContext(source,{window,URL,XMLHttpRequest:XHR,
    location:{origin:'http://127.0.0.1:7357',href:'http://127.0.0.1:7357/'},
    document:{addEventListener(){}},PerformanceObserver:class{observe(){}}});
  return {window,requests,XHR};
}
test('Blob local se permite por fetch y XHR; blob de otro origen se bloquea',async()=>{
  const {window,XHR}=guard();
  await window.fetch('blob:http://127.0.0.1:7357/local-image');
  new XHR().open('GET','blob:http://127.0.0.1:7357/local-image');
  assert.throws(()=>window.fetch('blob:https://outside.invalid/image'),/DEMO/);
  assert.throws(()=>new XHR().open('GET','blob:http://127.0.0.1:9999/image'),/DEMO/);
});
test('Firebase producción y otros hosts nunca llegan al transporte original',()=>{
  const {window,requests,XHR}=guard();
  for(const url of ['https://firebasestorage.googleapis.com/v0/b/real/o/file',
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
    'https://firestore.googleapis.com/v1/projects/real',
    'http://127.0.0.1:9999/','https://outside.invalid/']) {
    assert.throws(()=>window.fetch(url),/DEMO/);
    assert.throws(()=>new XHR().open('GET',url),/DEMO/);
  }
  assert.ok(requests.every(r=>r.url==='/__demo/audit'));
});
test('Los tres endpoints demo y servidor local permanecen permitidos',async()=>{
  const {window}=guard();
  for(const port of [7357,9099,8088,9198])await window.fetch(`http://127.0.0.1:${port}/local`);
});

test('FASE2 fixture de micrófono exige origen local y activación explícita', async()=>{
  const {installSyntheticMic}=await import('./synthetic-mic.js');
  const previous=globalThis.location;
  try {
    globalThis.location={origin:'https://outside.invalid',href:'https://outside.invalid/?syntheticMic=1'};
    assert.throws(installSyntheticMic,/demo local/);
    globalThis.location={origin:'http://127.0.0.1:7357',href:'http://127.0.0.1:7357/'};
    assert.throws(installSyntheticMic,/demo local/);
  } finally {if(previous===undefined)delete globalThis.location;else globalThis.location=previous;}
});
