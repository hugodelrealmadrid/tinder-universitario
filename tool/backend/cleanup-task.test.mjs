import test from 'node:test';import assert from 'node:assert/strict';import {runCleanupTask} from './cleanup-task.mjs';
test('Job de carnets solo ejecuta limpieza de verificación, nunca toca medios migrados',async()=>{let calls=0;await runCleanupTask({cleanupDue:async()=>calls++,get db(){throw Error('media-access-forbidden');}},'university_cards');assert.equal(calls,1);});
test('Ámbito de limpieza inválido falla antes de cualquier operación',async()=>{let calls=0;await assert.rejects(runCleanupTask({cleanupDue:async()=>calls++},'wrong'),/invalid-cleanup-scope/);assert.equal(calls,0);});
