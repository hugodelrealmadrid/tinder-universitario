// Diagnóstico de fixtures locales: nunca imprime download URLs ni tokens.
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,getDoc} from 'firebase/firestore';
import {ref,getMetadata,deleteObject} from 'firebase/storage';
import {readFile,writeFile} from 'node:fs/promises';
const project='demo-tinder-universitario',bucket=project+'.appspot.com';
const env=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:8088},storage:{host:'127.0.0.1',port:9198}});
try {
  const ctx=env.authenticatedContext('manual_ana',{email:'ana.manual@demo.test',email_verified:true});
  const profile=(await getDoc(doc(ctx.firestore(),'users/manual_ana'))).data();
  const path=url=>{
    const u=new URL(url);
    if(u.origin!=='http://127.0.0.1:9198'||u.pathname.split('/')[3]!==bucket)throw new Error('Foto fuera del demo');
    return decodeURIComponent(u.pathname.split('/o/')[1]);
  };
  const paths=profile.photoUrls.map(path);
  for(const p of paths)await getMetadata(ref(ctx.storage(bucket),p));
  if(process.argv[2]==='capture') {
    if(paths.length!==2||path(profile.mainPhotoUrl)===paths[0])throw new Error('No se confirmó cambio de principal');
    await writeFile(new URL('../../build/photo-operation.json',import.meta.url),JSON.stringify({uploadedPath:paths[1]}));
  }
  if(['deleted','cleanup'].includes(process.argv[2])) {
    const {uploadedPath}=JSON.parse(await readFile(new URL('../../build/photo-operation.json',import.meta.url),'utf8'));
    if(paths.includes(uploadedPath))throw new Error('Referencia no eliminada');
    if(process.argv[2]==='cleanup')await deleteObject(ref(ctx.storage(bucket),uploadedPath));
    try {await getMetadata(ref(ctx.storage(bucket),uploadedPath));throw new Error('Archivo no eliminado');}
    catch(error){if(error.code!=='storage/object-not-found')throw error;}
    if(paths.length!==1||path(profile.mainPhotoUrl)!==paths[0])throw new Error('Principal restante incorrecta');
    console.log('Borrado físico, referencia y sustitución de principal verificados.');
  }
  console.log(JSON.stringify({photoCount:paths.length,mainPath:path(profile.mainPhotoUrl),paths}));
} finally {await env.cleanup();}
