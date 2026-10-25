import {readClient,PROJECT} from './read-client.mjs';
import {saveEncrypted,privateDirectory,canonical,sha} from './private-backup.mjs';
import {writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
export async function captureFirestore(read){
 const probe=await read(root+':runQuery',{structuredQuery:{from:[{collectionId:'users'}],limit:1}}),readTime=probe.at(-1)?.readTime;
 if(!readTime)throw Error('snapshot-time-missing');
 const documents=[],missing=[];
 async function walk(parent){
  let page;do{
   const c=await read(parent+':listCollectionIds',{pageSize:1000,readTime,...(page?{pageToken:page}:{})});page=c.nextPageToken;
   for(const id of (c.collectionIds??[]).sort()){
    let docPage;do{const q=new URLSearchParams({pageSize:'1000',showMissing:'true',readTime});if(docPage)q.set('pageToken',docPage);
     const d=await read(parent+'/'+encodeURIComponent(id)+'?'+q);docPage=d.nextPageToken;
     for(const doc of d.documents??[]){if(doc.createTime)documents.push(doc);else missing.push(doc.name);await walk('https://firestore.googleapis.com/v1/'+doc.name);}
    }while(docPage);
   }
  }while(page);
 }
 await walk(root);documents.sort((a,b)=>a.name.localeCompare(b.name));missing.sort();return {readTime,documents,missing};
}
async function captureAuth(read){
 const config=await read(`https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`),users=[];let page;
 do{const q=new URLSearchParams({maxResults:'1000'});if(page)q.set('nextPageToken',page);const d=await read(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet?`+q);users.push(...(d.users??[]));page=d.nextPageToken;}while(page);
 const h=config.signIn?.hashConfig;
 if(!h?.signerKey||h.algorithm!=='SCRYPT'||h.saltSeparator===undefined||h.rounds===undefined||h.memoryCost===undefined)throw Error('auth-hash-config-incomplete');
 if(users.some(u=>!u.passwordHash||u.mfaInfo?.length))throw Error('auth-backup-requires-review');
 users.sort((a,b)=>a.localId.localeCompare(b.localId));return {config,users};
}
async function listObjects(read){
 const buckets=await read(`https://storage.googleapis.com/storage/v1/b?project=${PROJECT}`),objects=[];
 for(const bucket of buckets.items??[]){let page;do{const q=new URLSearchParams({versions:'true',maxResults:'1000'});if(page)q.set('pageToken',page);const d=await read(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket.name)}/o?`+q);objects.push(...(d.items??[]));page=d.nextPageToken;}while(page);}
 objects.sort((a,b)=>(a.bucket+'/'+a.name+'/'+a.generation).localeCompare(b.bucket+'/'+b.name+'/'+b.generation));return {buckets:buckets.items??[],objects};
}
export function crc32c(bytes){let crc=0xffffffff;for(const b of bytes){crc^=b;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0x82f63b78:0);}const out=Buffer.alloc(4);out.writeUInt32BE((crc^0xffffffff)>>>0);return out.toString('base64');}
export async function backup(){
 if(process.argv[2]!=='--read-only-backup')throw Error('explicit-backup-flag-required');
 const read=await readClient(),startedAt=new Date().toISOString();
 const auth=await captureAuth(read);const firestore=await captureFirestore(read);const storage=await listObjects(read);
 const files=[];for(const meta of storage.objects){if(Number(meta.size)>32*1024*1024)throw Error('large-object-review-required');
  const bytes=await read(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(meta.bucket)}/o/${encodeURIComponent(meta.name)}?alt=media&generation=${meta.generation}`,undefined,{binary:true});
  if(bytes.length!==Number(meta.size)||crc32c(bytes)!==meta.crc32c||(meta.md5Hash&&createHash('md5').update(bytes).digest('base64')!==meta.md5Hash))throw Error('storage-checksum-failed');
  files.push({metadata:meta,sha256:sha(bytes),bytesBase64:bytes.toString('base64')});
 }
 const releases=await read(`https://firebaserules.googleapis.com/v1/projects/${PROJECT}/releases?pageSize=100`);if(releases.nextPageToken)throw Error('rules-pagination-review-required');
 const rules=[];for(const release of releases.releases??[])rules.push({release,ruleset:await read('https://firebaserules.googleapis.com/v1/'+release.rulesetName)});
 const indexes=await read(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/collectionGroups/-/indexes`);if(indexes.nextPageToken)throw Error('indexes-pagination-review-required');
 const authAgain=await captureAuth(read),storageAgain=await listObjects(read),firestoreAgain=await captureFirestore(read);
 if(canonical(auth)!==canonical(authAgain)||canonical(storage)!==canonical(storageAgain)||canonical(firestore.documents)!==canonical(firestoreAgain.documents)||canonical(firestore.missing)!==canonical(firestoreAgain.missing))throw Error('concurrent-change-backup-not-complete');
 const dir=fileURLToPath(new URL('../../build/online-backups/'+startedAt.replace(/[:.]/g,'-')+'/',import.meta.url));privateDirectory(dir);
 const data={format:'tinder-private-backup-v1',project:PROJECT,startedAt,completedAt:new Date().toISOString(),auth,firestore,storage:{...storage,files},rules,indexes};
 const verification=saveEncrypted(dir+'backup.dpapi',data);
 const counts={auth:auth.users.length,firestore:firestore.documents.length,objects:files.length,bytes:files.reduce((n,f)=>n+Number(f.metadata.size),0)};
 const manifest={format:data.format,project:PROJECT,...verification,counts,verified:true,firestoreReadTime:firestore.readTime,encryption:'Windows DPAPI CurrentUser; restaurar con el mismo perfil de Windows',consistency:'Firestore a readTime fijo; Auth/Storage/Firestore iguales en dos lecturas. No es transacción distribuida.'};
 writeFileSync(dir+'verified.json',JSON.stringify(manifest,null,2),{flag:'wx'});console.log(JSON.stringify({respaldo:dir,...counts,verificado:true,sha256:verification.cipherSha256}));
}
if(process.argv[1]&&import.meta.url===new URL('file:///'+process.argv[1].replaceAll('\\','/')).href)backup().catch(e=>{console.error(JSON.stringify({respaldoCompleto:false,codigo:/^[a-z0-9-]+$/.test(e.message)?e.message:'backup-failed-no-sensitive-details'}));process.exitCode=1;});
