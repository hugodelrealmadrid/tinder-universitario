import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {isolationPaths,isolatedEnvironment,assertLoopbackPortsFree} from './emulator-isolation.mjs';
test('Demo y pruebas tienen temporales y directorios de ejecución distintos',()=>{
 const a=isolationPaths('demo'),b=isolationPaths('tests');
 assert.notEqual(a.temp,b.temp);assert.notEqual(a.run,b.run);assert.notEqual(a.project,b.project);
 for(const r of ['demo','tests']){const e=isolatedEnvironment(r);assert.equal(e.TEMP,e.TMP);assert.equal(e.TMPDIR,e.TEMP);}
});
test('El proceso hijo resuelve os.tmpdir al directorio de su entorno',()=>{
 for(const role of ['demo','tests']){
  const e=isolatedEnvironment(role),r=spawnSync(process.execPath,['-p','require("node:os").tmpdir()'],{env:e,encoding:'utf8',windowsHide:true});
  assert.equal(r.status,0);assert.equal(r.stdout.trim(),e.TEMP);
 }
});
test('No hereda endpoints, credenciales ni opciones de ejecución del otro entorno',()=>{
 const parent={FIRESTORE_EMULATOR_HOST:'127.0.0.1:8088',FIREBASE_AUTH_EMULATOR_HOST:'bad',GOOGLE_APPLICATION_CREDENTIALS:'private.json',NODE_OPTIONS:'bad',JAVA_TOOL_OPTIONS:'bad',TEMP:'shared'};
 const a=isolatedEnvironment('tests',parent);assert.equal(a.RULES_PROJECT,'demo-tinder-phase3-tests');assert.equal(a.GCLOUD_PROJECT,a.RULES_PROJECT);
 for(const key of ['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST','GOOGLE_APPLICATION_CREDENTIALS','NODE_OPTIONS'])assert.equal(a[key],undefined);
 assert.equal(parent.TEMP,'shared');assert.equal(parent.JAVA_TOOL_OPTIONS,'bad');
});
test('Rechaza nombres de entorno no previstos',()=>{assert.throws(()=>isolationPaths('production'));assert.throws(()=>isolatedEnvironment('../demo'));});
test('No arranca otro emulador sobre un puerto ocupado; permite uno libre',async()=>{
 const server=createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const port=server.address().port;
 try{await assert.rejects(assertLoopbackPortsFree([port]),/already in use/);}finally{await new Promise(resolve=>server.close(resolve));}
 await assertLoopbackPortsFree([port]);
});
