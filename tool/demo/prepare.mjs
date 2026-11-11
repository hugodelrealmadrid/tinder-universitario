import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = new URL('../../', import.meta.url);
const vendor = new URL('./vendor/', import.meta.url);
await mkdir(vendor, {recursive:true});
await writeFile(new URL('.gitignore',vendor),'*\n');
const config = JSON.parse(await readFile(new URL('.dart_tool/package_config.json',root),'utf8'));
const pkg = config.packages.find(p=>p.name==='firebase_core_web');
if (!pkg) throw new Error('Primero ejecuta flutter pub get.');
const pkgRoot = new URL(pkg.rootUri.replace(/\/?$/,'/'),new URL('.dart_tool/package_config.json',root));
const versionFile = await readFile(new URL('lib/src/firebase_sdk_version.dart',pkgRoot),'utf8');
const version = /supportedFirebaseJsSdkVersion = '([0-9.]+)'/.exec(versionFile)?.[1];
if (!version) throw new Error('No se pudo verificar la versión del SDK Web.');
for(const name of ['app','auth','firestore','firestore-pipelines','storage']) {
  const url=`https://www.gstatic.com/firebasejs/${version}/firebase-${name}.js`;
  const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000)});
  if(!response.ok) throw new Error(`No se descargó el SDK público ${name}: HTTP ${response.status}`);
  const text=(await response.text()).replaceAll(`https://www.gstatic.com/firebasejs/${version}/`,'./')
    .replace(/\/\/# sourceMappingURL=.*$/gm,'');
  if (/(?:from\s*|import\s*)["']https?:/.test(text)) throw new Error(`Importación externa en ${name}`);
  await writeFile(new URL(`firebase-${name}.js`,vendor),text);
}
const source=(await readFile(new URL('firestore.rules',root),'utf8')).replace(/\r\n/g,'\n');
const rules=source; // Fase 5: idénticas reglas, referencias privadas en todas las plataformas.
if(rules.includes('tinder-universitario.firebasestorage.app') || rules.includes('https://firebasestorage'))
  throw new Error('Persisten URLs de fotos reales en las reglas demo.');
await writeFile(new URL('firestore.demo.rules',import.meta.url),rules);
await writeFile(new URL('sdk-version.json',vendor),JSON.stringify({version},null,2));
const flutterPkg=config.packages.find(p=>p.name==='flutter');
const flutterRoot=new URL(flutterPkg.rootUri.replace(/\/?$/,'/'),new URL('.dart_tool/package_config.json',root));
const fonts=new URL('../../bin/cache/artifacts/material_fonts/',flutterRoot);
for(const name of ['regular','thin','light','medium','bold','black','italic','bolditalic']) {
  await copyFile(new URL(`roboto-${name}.ttf`,fonts),new URL(`roboto-${name}.ttf`,vendor));
}
await copyFile(new URL('roboto_license.txt',fonts),new URL('roboto_license.txt',vendor));
console.log(`SDK público ${version} preparado localmente; reglas demo generadas en ${fileURLToPath(new URL('firestore.demo.rules',import.meta.url))}. Sin consultas a proyectos Firebase.`);
