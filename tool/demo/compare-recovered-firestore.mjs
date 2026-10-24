// Semantic comparison in a separate Firestore emulator imported from the backup.
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
for(const [hub,port]of [[4400,8088],[4410,8188]]){
 const state=await fetch('http://127.0.0.1:'+hub+'/emulators').then(r=>r.json());assert.equal(state.firestore.host,'127.0.0.1');assert.equal(state.firestore.port,port);
}
function normalize(value){
 if(Array.isArray(value))return value.map(normalize);
 if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,k==='referenceValue'?value[k].split('/documents/')[1]:normalize(value[k])]));
 return value;
}
async function dump(port,project){
 const root=`http://127.0.0.1:${port}/v1/projects/${project}/databases/(default)/documents`,result={};
 async function request(url,body){const r=await fetch(url,{method:body?'POST':'GET',headers:{Authorization:'Bearer owner','Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(20000)});assert.equal(r.status,200);return r.json();}
 async function walk(parent=''){
  let token;do{const listed=await request(root+(parent?'/'+parent:'')+':listCollectionIds',{pageSize:1000,...(token?{pageToken:token}:{})});
   for(const id of listed.collectionIds??[]){let page;do{const url=new URL(root+'/'+(parent?parent+'/':'')+id);url.searchParams.set('pageSize','1000');url.searchParams.set('showMissing','true');if(page)url.searchParams.set('pageToken',page);
    const docs=await request(url);for(const doc of docs.documents??[]){const path=doc.name.split('/documents/')[1];if(doc.fields)result[path]=normalize(doc.fields);await walk(path);}page=docs.nextPageToken;
   }while(page);}token=listed.nextPageToken;
  }while(token);
 }
 await walk();return result;
}
const before=await dump(8188,'demo-tinder-phase3-tests'),after=await dump(8088,'demo-tinder-universitario');
const differences=[];for(const path of new Set([...Object.keys(before),...Object.keys(after)]))if(JSON.stringify(before[path])!==JSON.stringify(after[path]))differences.push({path,missingBefore:!before[path],missingAfter:!after[path],fields:[...new Set([...Object.keys(before[path]??{}),...Object.keys(after[path]??{})])].filter(k=>JSON.stringify(before[path]?.[k])!==JSON.stringify(after[path]?.[k]))});
for(const d of differences){
 d.beforeState=before[d.path]?.state?.stringValue??null;d.afterState=after[d.path]?.state?.stringValue??null;
 // The existing reconciler finalizes referenced uploads. No file/reference,
 // content or privilege change is accepted by this narrow classification.
 d.expectedPublicationCompletion=/^(chatUploads|profilePhotoAssets)\//.test(d.path)&&!d.missingBefore&&!d.missingAfter&&d.fields.length===2&&d.fields.includes('state')&&d.fields.includes('expiresAt')&&d.beforeState==='ready'&&d.afterState==='published'&&!!before[d.path]?.expiresAt&&!after[d.path]?.expiresAt;
}
const unexpected=differences.filter(d=>!d.expectedPublicationCompletion);
const result={beforeDocuments:Object.keys(before).length,afterDocuments:Object.keys(after).length,differences,identical:differences.length===0,expectedPublicationCompletions:differences.length-unexpected.length,unexpectedChanges:unexpected};
if(process.env.RECOVERY_WORK)await writeFile(resolve(process.env.RECOVERY_WORK,'comparacion-logica-firestore-clasificada.json'),JSON.stringify(result,null,2),{flag:'wx'});
console.log(JSON.stringify(result,null,2));if(unexpected.length)process.exitCode=2;
