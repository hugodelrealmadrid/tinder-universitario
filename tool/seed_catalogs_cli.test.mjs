import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateCatalogs, createMissing } from './seed_catalogs_cli.mjs';
const catalogs = JSON.parse((await readFile(new URL('./catalogs.seed.json',import.meta.url),'utf8')).replace(/^\uFEFF/,''));
test('33 POST con IDs fijos, proyecto exacto y solo dos campos', async () => {
  const calls = [];
  const result = await createMissing(catalogs,'fake-test-token',async (url, options) => {
    calls.push(url);
    assert.equal(options.method,'POST');
    assert.equal(options.redirect,'error');
    assert.match(url,/^https:\/\/firestore.googleapis.com\/v1\/projects\/tinder-universitario\/databases\/\(default\)\/documents\/(careers|interests)\?documentId=[a-z_]+$/);
    assert.deepEqual(Object.keys(JSON.parse(options.body).fields).sort(),['isActive','name']);
    return {ok:true};
  });
  assert.equal(result.length,33); assert.equal(new Set(calls).size,33);
});
test('Repetición omite existentes sin PATCH, DELETE ni sobrescrituras', async () => {
  const result = await createMissing(catalogs,'fake-test-token',async (_url,options) => {
    assert.equal(options.method,'POST');
    return {ok:false,status:409,json:async()=>({error:{status:'ALREADY_EXISTS'}})};
  });
  assert.ok(result.every(item=>item.status==='existente, sin cambios'));
});
test('Rechaza colecciones e IDs adicionales antes de cualquier solicitud', async () => {
  for (const data of [{...catalogs,users:{}},{...catalogs,careers:{...catalogs.careers,otra:{name:'Otra',isActive:true}}}]) {
    await assert.rejects(createMissing(data,'fake',()=>assert.fail('No debe conectarse')));
  }
  assert.equal(validateCatalogs(catalogs).length,33);
});
test('Un error de permisos detiene la ejecución sin intentar otra escritura', async () => {
  let calls=0;
  await assert.rejects(createMissing(catalogs,'fake',async()=>{calls++;return {ok:false,status:403};}),/HTTP 403/);
  assert.equal(calls,1);
});
