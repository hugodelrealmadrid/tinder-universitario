import { readFile } from 'node:fs/promises';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
const projectId = process.argv[2];
if (!projectId) throw new Error('Uso: node tool/seed_catalogs.mjs ID_PROYECTO');
// Usa credenciales de administrador externas; nunca se empaquetan en Flutter.
initializeApp({ projectId, credential: applicationDefault() });
const db = getFirestore();
const catalogs = JSON.parse((await readFile(new URL('./catalogs.seed.json', import.meta.url), 'utf8')).replace(/^\uFEFF/, ''));
for (const [collection, entries] of Object.entries(catalogs)) {
  for (const [id, data] of Object.entries(entries)) {
    const ref = db.collection(collection).doc(id);
    await db.runTransaction(async tx => {
      if (!(await tx.get(ref)).exists) tx.create(ref, data);
    });
    console.log(`${collection}/${id}: existente o creado`);
  }
}
console.log('Carga terminada; los documentos existentes no se sobrescribieron.');
