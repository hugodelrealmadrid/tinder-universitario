import {readFile,readdir} from 'node:fs/promises';
const folder=new URL('../../build/phase3-fixtures-before/storage_export/metadata/',import.meta.url);
const results=[];
for(const name of await readdir(folder)){
 const m=JSON.parse(await readFile(new URL(name,folder),'utf8'));
 if(m.bucket!=='demo-tinder-universitario.appspot.com'||!m.name.startsWith('chat_media/'))continue;
 const token=m.downloadTokens?.[0];if(!token)continue;
 const url=`http://127.0.0.1:9198/v0/b/${m.bucket}/o/${encodeURIComponent(m.name)}?alt=media&token=${encodeURIComponent(token)}`;
 const response=await fetch(url);results.push(response.status);await response.body?.cancel();
}
console.log(JSON.stringify({previousChatTokens:results.length,statuses:results,allRevoked:results.every(s=>s!==200)}));
if(results.some(s=>s===200))process.exitCode=1;
