// Firebase Emulator conserva tokens fuera de metadata y regenera el último.
// Migración local: reescritura GCS condicional de los mismos bytes sin tokens.
export async function sealPrivateObject(file){
 const host=process.env.FIREBASE_STORAGE_EMULATOR_HOST;
 if(!host){
  const [before]=await file.getMetadata();
  if(!before.generation||!before.metageneration)throw new Error('private-precondition-required');
  await file.setMetadata({cacheControl:'private, no-store',metadata:{...(before.metadata??{}),firebaseStorageDownloadTokens:null}},{ifGenerationMatch:before.generation,ifMetagenerationMatch:before.metageneration});
  const [sealed]=await file.getMetadata();
  if(sealed.generation!==before.generation||sealed.size!==before.size||sealed.md5Hash!==before.md5Hash||sealed.metadata?.firebaseStorageDownloadTokens||sealed.cacheControl!=='private, no-store')throw new Error('private-revocation-incomplete');
  return;
 }
 if(!(/^127\.0\.0\.1:(9198|9298)$/.test(host)||(file.bucket.name==='demo-ligo-staging.appspot.com'&&host==='127.0.0.1:9498')||(file.bucket.name==='demo-ligo-validation.appspot.com'&&host==='127.0.0.1:9698'))||!file.bucket.name.startsWith('demo-')||!/^(university_cards|chat_media|profile_photos|story_media)\//.test(file.name))throw new Error('private-emulator-only');
 const [meta]=await file.getMetadata();
 if(meta.metadata?.firebaseStorageDownloadTokens){
  if(Number(meta.size)>16*1024*1024)throw new Error('private-size-invalid');
  const [bytes]=await file.download(),custom={...meta.metadata};delete custom.firebaseStorageDownloadTokens;
  await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:meta.generation},metadata:{contentType:meta.contentType,cacheControl:'private, no-store',metadata:custom}});
 }
 const [sealed]=await file.getMetadata();
 if(sealed.metadata?.firebaseStorageDownloadTokens)throw new Error('private-revocation-incomplete');
}
