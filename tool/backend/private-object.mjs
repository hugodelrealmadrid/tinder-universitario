// Firebase Emulator conserva tokens fuera de metadata y regenera el último.
// Migración local: reescritura GCS condicional de los mismos bytes sin tokens.
export async function sealPrivateObject(file){
 const host=process.env.FIREBASE_STORAGE_EMULATOR_HOST;
 if(!host){await file.setMetadata({metadata:{firebaseStorageDownloadTokens:null}});return;}
 if(!/^127\.0\.0\.1:(9198|9298)$/.test(host)||!file.bucket.name.startsWith('demo-')||!/^(university_cards|chat_media|profile_photos)\//.test(file.name))throw new Error('private-emulator-only');
 const [meta]=await file.getMetadata();
 if(meta.metadata?.firebaseStorageDownloadTokens){
  if(Number(meta.size)>16*1024*1024)throw new Error('private-size-invalid');
  const [bytes]=await file.download(),custom={...meta.metadata};delete custom.firebaseStorageDownloadTokens;
  await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:meta.generation},metadata:{contentType:meta.contentType,cacheControl:'private, no-store',metadata:custom}});
 }
 const [sealed]=await file.getMetadata();
 if(sealed.metadata?.firebaseStorageDownloadTokens)throw new Error('private-revocation-incomplete');
}
