import {test} from 'node:test';import assert from 'node:assert/strict';import {sealPrivateObject} from './private-object.mjs';
test('GCS remoto: sellado condicional conserva bytes y exige ausencia efectiva de tokens',async t=>{
 const old=process.env.FIREBASE_STORAGE_EMULATOR_HOST;delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;t.after(()=>{if(old===undefined)delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;else process.env.FIREBASE_STORAGE_EMULATOR_HOST=old;});
 const before={generation:'123',metageneration:'2',size:'64',md5Hash:'digest',metadata:{firebaseStorageDownloadTokens:'fake-test-only',retained:'value'}};let metadata=structuredClone(before),calls=[];
 const f={getMetadata:async()=>[structuredClone(metadata)],async setMetadata(patch,options){calls.push({patch,options});metadata={...metadata,cacheControl:patch.cacheControl,metadata:{retained:'value'},metageneration:'3'};}};
 await sealPrivateObject(f);assert.deepEqual(calls[0].options,{ifGenerationMatch:'123',ifMetagenerationMatch:'2'});assert.equal(calls[0].patch.metadata.firebaseStorageDownloadTokens,null);assert.equal(calls[0].patch.metadata.retained,'value');assert.equal(metadata.metadata.retained,'value');assert.equal(metadata.generation,before.generation);
});
test('GCS remoto: respuesta que conserva el token se rechaza, sin publicar referencia',async t=>{
 const old=process.env.FIREBASE_STORAGE_EMULATOR_HOST;delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;t.after(()=>{if(old===undefined)delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;else process.env.FIREBASE_STORAGE_EMULATOR_HOST=old;});
 const metadata={generation:'123',metageneration:'2',size:'64',md5Hash:'digest',cacheControl:'private, no-store',metadata:{firebaseStorageDownloadTokens:'fake-test-only'}};await assert.rejects(sealPrivateObject({getMetadata:async()=>[metadata],setMetadata:async()=>{}}),/private-revocation-incomplete/);
});
test('GCS remoto: conflicto de metadatos y cambio de generación detienen la operación',async t=>{
 const old=process.env.FIREBASE_STORAGE_EMULATOR_HOST;delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;t.after(()=>{if(old===undefined)delete process.env.FIREBASE_STORAGE_EMULATOR_HOST;else process.env.FIREBASE_STORAGE_EMULATOR_HOST=old;});
 const before={generation:'123',metageneration:'2',size:'64',md5Hash:'digest'};await assert.rejects(sealPrivateObject({getMetadata:async()=>[before],setMetadata:async()=>{throw Object.assign(new Error('conflict'),{code:412});}}),/conflict/);
 let n=0;await assert.rejects(sealPrivateObject({getMetadata:async()=>[{...before,generation:++n===1?'123':'999',cacheControl:'private, no-store'}],setMetadata:async()=>{}}),/private-revocation-incomplete/);
});
