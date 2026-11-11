// Solo lectura del demo local: no registra muestras, rutas ni tokens de descarga.
import assert from 'node:assert/strict';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {collection,getDocs,query,orderBy,limit} from 'firebase/firestore';
import {authenticatedMedia} from './chat-api.mjs';
const project='demo-tinder-universitario';
const hub=await fetch('http://127.0.0.1:4400/emulators').then(r=>r.json());
for(const [name,port] of [['auth',9099],['firestore',8088],['storage',9198]])assert.equal(hub[name]?.port,port);
const env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});
try {
 const ctx=env.authenticatedContext('manual_ana',{email:'ana.manual@demo.test',email_verified:true});
 const messages=(await getDocs(query(collection(ctx.firestore(),'matches/manual_ana.manual_bob/messages'),orderBy('createdAt','desc'),limit(50)))).docs;
 for(const d of messages){const m=d.data();if(m.type!=='audio')continue;
  const {metadata:meta,bytes:b}=await authenticatedMedia(m.mediaPath);
  if(new TextDecoder().decode(b.slice(0,4))!=='RIFF'){console.log(JSON.stringify({id:d.id,mime:meta.contentType,bytes:b.length,format:'no-WAV'}));continue;}
  const v=new DataView(b.buffer,b.byteOffset,b.byteLength);let sum=0,peak=0,nonzero=0,n=0;
  if(v.getUint16(20,true)!==1||v.getUint16(22,true)!==1||v.getUint16(34,true)!==16||new TextDecoder().decode(b.slice(36,40))!=='data'){
   console.log(JSON.stringify({id:d.id,mime:meta.contentType,bytes:b.length,format:'WAV adjunto: no es nota canónica PCM16 mono'}));continue;
  }
  // Las notas propias usan cabecera canónica PCM de 44 bytes.
  for(let p=44;p+1<b.length;p+=2){const s=v.getInt16(p,true)/32768;sum+=s*s;peak=Math.max(peak,Math.abs(s));if(s!==0)nonzero++;n++;}
  console.log(JSON.stringify({id:d.id,created:m.createdAt?.toDate().toISOString(),read:!!m.readAt,mime:meta.contentType,bytes:b.length,rate:v.getUint32(24,true),channels:v.getUint16(22,true),bits:v.getUint16(34,true),durationMs:m.durationMs,pcmMs:Math.round(n*1000/v.getUint32(24,true)),peak,rms:Math.sqrt(sum/Math.max(1,n)),nonzeroSamples:nonzero}));
 }
}finally{await env.cleanup();}
