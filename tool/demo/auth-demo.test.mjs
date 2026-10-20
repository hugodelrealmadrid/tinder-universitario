import {test} from 'node:test';
import assert from 'node:assert/strict';
import {demoAuthModule} from './auth-demo.js';
test('Auth conecta al emulador de forma síncrona antes de restaurar sesión',()=>{
  const sequence=[];const instance={emulatorConfig:null};
  const module=demoAuthModule({browserSessionPersistence:'session',
    initializeAuth(app,options){sequence.push('initialize');assert.equal(options.persistence,'session');return instance;},
    connectAuthEmulator(auth,url){sequence.push('emulator');assert.equal(url,'http://127.0.0.1:9099');auth.emulatorConfig={host:'127.0.0.1',port:9099};}});
  assert.equal(module.initializeAuth({options:{projectId:'demo-tinder-universitario'}},{}),instance);
  sequence.push('returned');assert.deepEqual(sequence,['initialize','emulator','returned']);
  assert.throws(()=>module.initializeAuth({options:{projectId:'real'}},{}),/proyecto ajeno/);
  instance.emulatorConfig={host:'outside.invalid',port:9099};
  assert.throws(()=>module.initializeAuth({options:{projectId:'demo-tinder-universitario'}},{}),/endpoint ajeno/);
});
