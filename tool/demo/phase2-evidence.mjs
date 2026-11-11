// Comprobaciones de lectura sobre fixtures demo. No publica ni modifica mensajes.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {collection,getDocs,query,orderBy,limit} from 'firebase/firestore';
import {authenticatedMedia} from './chat-api.mjs';
const project='demo-tinder-universitario',bucket=project+'.appspot.com';
const env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});
try {
 const ctx=env.authenticatedContext('manual_ana',{email:'ana.manual@demo.test',email_verified:true});
 const messages=(await getDocs(query(collection(ctx.firestore(),'matches/manual_ana.manual_bob/messages'),orderBy('createdAt','desc'),limit(50)))).docs.map(d=>({id:d.id,...d.data()}));
 const file=new URL('../../build/phase2-before.json',import.meta.url);
 if(process.argv[2]==='before') {
  await writeFile(file,JSON.stringify({ids:messages.map(m=>m.id)}));
  console.log('Línea base de mensajes conservada; borrador aún no publicado.');
 } else {
  const before=JSON.parse(await readFile(file,'utf8'));
  const added=messages.filter(m=>!before.ids.includes(m.id));
  const note=added.find(m=>m.type==='audio'&&m.durationMs>0);
  assert.ok(note,'Falta nota nueva');assert.equal(note.senderId,'manual_ana');
  const {metadata,bytes}=await authenticatedMedia(note.mediaPath);
  assert.equal(metadata.contentType,'audio/wav');
  assert.equal(new TextDecoder().decode(bytes.slice(0,4)),'RIFF');
  const view=new DataView(bytes.buffer);assert.equal(view.getUint32(24,true),16000);
  assert.equal(view.getUint16(22,true),1);assert.equal(view.getUint16(34,true),16);
  assert.equal(note.durationMs,Math.round((bytes.length-44)/32));
  assert.ok(bytes.slice(44).some(v=>v!==0),'La señal no contiene muestras');
  if(process.argv[2]==='unread')assert.ok(!note.readAt,'Nota ya leída');
  if(process.argv[2]==='read')for(const m of added)assert.ok(m.readAt,'Falta recibo en '+m.type);
  console.log(JSON.stringify({added:added.map(m=>({id:m.id,type:m.type??'text',read:!!m.readAt})),noteDurationMs:note.durationMs,bytes:bytes.length,nonzeroSamples:true}));
 }
} finally {await env.cleanup();}
