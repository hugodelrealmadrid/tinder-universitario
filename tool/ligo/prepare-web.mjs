import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import {createHash} from 'node:crypto';
const root=resolve('build/ligo-staging/web'),cache=process.argv[2]==='--cache-dir'?resolve(process.argv[3]):null;
const cfg=JSON.parse(await readFile('.dart_tool/package_config.json','utf8'));const packageConfig=pathToFileURL(resolve('.dart_tool/package_config.json'));const pkg=cfg.packages.find(p=>p.name==='firebase_core_web'),base=new URL(pkg.rootUri.replace(/\/?$/,'/'),packageConfig);const source=await readFile(new URL('lib/src/firebase_sdk_version.dart',base),'utf8'),version=/supportedFirebaseJsSdkVersion = '([0-9.]+)'/.exec(source)?.[1];if(!version)throw Error('sdk-version-required');
if(cache&&JSON.parse(await readFile(resolve(cache,'sdk-version.json'),'utf8')).version!==version)throw Error('cached-sdk-version-mismatch');
await mkdir(resolve(root,'vendor'),{recursive:true});const hashes={};
for(const name of ['app','auth','firestore','firestore-pipelines','storage']){
 const file='firebase-'+name+'.js';let text;
 if(cache)text=await readFile(resolve(cache,file),'utf8');else{const r=await fetch('https://www.gstatic.com/firebasejs/'+version+'/'+file,{redirect:'error',signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error('public-sdk-download-'+r.status);text=await r.text();}
 text=text.replaceAll('https://www.gstatic.com/firebasejs/'+version+'/','./').replace(/\/\/# sourceMappingURL=.*$/gm,'');if(/(?:from\s*|import\s*)["']https?:/.test(text))throw Error('external-sdk-import');
 await writeFile(resolve(root,'vendor',file),text);hashes[file]=createHash('sha256').update(text).digest('hex');
}
const flutter=cfg.packages.find(p=>p.name==='flutter');const fontRoot=new URL('../../bin/cache/artifacts/material_fonts/',new URL(flutter.rootUri.replace(/\/?$/,'/'),packageConfig));await mkdir(resolve(root,'assets/staging_fonts'),{recursive:true});
for(const style of ['regular','thin','light','medium','bold','black','italic','bolditalic'])await copyFile(new URL('roboto-'+style+'.ttf',fontRoot),resolve(root,'assets/staging_fonts/roboto-'+style+'.ttf'));await copyFile(new URL('roboto_license.txt',fontRoot),resolve(root,'assets/staging_fonts/roboto_license.txt'));
const fontFile=resolve(root,'assets/FontManifest.json'),fonts=JSON.parse(await readFile(fontFile,'utf8')).filter(x=>x.family!=='Roboto');fonts.push({family:'Roboto',fonts:[...['regular','thin','light','medium','bold','black'].map((name,i)=>({asset:'staging_fonts/roboto-'+name+'.ttf',weight:[400,100,300,500,700,900][i]})),{asset:'staging_fonts/roboto-italic.ttf',style:'italic',weight:400},{asset:'staging_fonts/roboto-bolditalic.ttf',style:'italic',weight:700}]});await writeFile(fontFile,JSON.stringify(fonts));
await copyFile(new URL('./staging-bootstrap.js',import.meta.url),resolve(root,'staging-bootstrap.js'));
const index=resolve(root,'index.html');let html=await readFile(index,'utf8');html=html.replace('<script src="flutter_bootstrap.js" async></script>','<script type="module" src="staging-bootstrap.js"></script>');await writeFile(index,html);
await writeFile(resolve(root,'vendor/sdk-version.json'),JSON.stringify({version,sha256:hashes},null,2));console.log(JSON.stringify({stagingOnly:true,publicSdkVersion:version,localSdkModules:5,localFonts:8,productionResourcesContacted:false}));
